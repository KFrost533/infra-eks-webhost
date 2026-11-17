import { test } from "node:test";
import * as assert from "node:assert/strict";
import { eksToken, handler, matchesProfile, restore, stop } from "../scripts/fargate_off";

type TestResource = {
  metadata: { name: string; namespace?: string; resourceVersion: string; labels?: Record<string, string>; annotations?: Record<string, string> };
  spec: Record<string, unknown>;
  status?: { conditions?: Array<{ type: string; status: string }> };
};
const marker = "fargate-control.kfrost533.dev/previous-state";
const selectors = [{ namespace: "website", labels: { app: "web*" } }];
const makeResource = (name: string, replicas: number, labels = { app: "web" }): TestResource => ({
  metadata: { name, namespace: "website", resourceVersion: "1" },
  spec: { replicas, template: { metadata: { labels } } }
});

function fakeKube(resources: Record<string, TestResource[]>) {
  const deletions: string[] = [];
  return {
    deletions,
    async list<T>(path: string): Promise<T[]> {
      return structuredClone(resources[path] || []) as T[];
    },
    async patch(path: string, value: object): Promise<void> {
      const patch = value as { metadata: { annotations: Record<string, string | null> }; spec: Record<string, unknown> };
      const parts = path.split("/");
      const name = decodeURIComponent(parts.at(-1)!);
      const kind = parts.at(-2)!;
      const collection = Object.entries(resources).find(([key]) => key.endsWith(`/${kind}`))?.[1];
      const target = collection?.find((item) => item.metadata.name === name);
      assert.ok(target, `missing ${path}`);
      target.metadata.annotations ||= {};
      for (const [key, val] of Object.entries(patch.metadata.annotations)) {
        if (val === null) delete target.metadata.annotations[key];
        else target.metadata.annotations[key] = val;
      }
      Object.assign(target.spec, patch.spec);
    },
    async delete(path: string): Promise<void> {
      deletions.push(path);
      if (path.includes("/pods/")) {
        resources["/api/v1/pods"] = [];
        resources["/api/v1/nodes"] = [];
      }
    }
  };
}

test("profile matching supports wildcards on namespace and labels", () => {
  assert.equal(matchesProfile("web-prod", { "team-name": "api-v1" }, [
    { namespace: "web-*", labels: { "team-*": "api-?1" } }
  ]), true);
  assert.equal(matchesProfile("default", { app: "web" }, selectors), false);
});

test("EKS authentication signs the cluster ID and aliases cannot invoke the other action", async () => {
  const saved = { ...process.env };
  try {
    process.env.AWS_ACCESS_KEY_ID = "test-key";
    process.env.AWS_SECRET_ACCESS_KEY = "test-secret";
    process.env.AWS_SESSION_TOKEN = "test-session";
    const token = await eksToken("test-cluster", "ap-southeast-1");
    const url = new URL(Buffer.from(token.replace(/^k8s-aws-v1\./, ""), "base64url").toString());
    assert.equal(url.hostname, "sts.ap-southeast-1.amazonaws.com");
    assert.equal(url.searchParams.get("Action"), "GetCallerIdentity");
    assert.match(url.searchParams.get("X-Amz-SignedHeaders") || "", /x-k8s-aws-id/);
    assert.ok(url.searchParams.get("X-Amz-Security-Token"));
    const messages: string[] = [];
    const originalError = console.error;
    console.error = (message) => { messages.push(String(message)); };
    try {
      await assert.rejects(handler({ detail: { action: "stop", requestId: "test-request" } },
        { invokedFunctionArn: "arn:aws:lambda:region:account:function:test:restore" }), /matching stop or restore alias/);
      assert.deepEqual(JSON.parse(messages[0]), {
        event: "FARGATE_CONTROL_FAILURE", action: "restore", requestId: "test-request"
      });
      delete process.env.CLUSTER_NAME;
      await assert.rejects(handler({ detail: { action: "restore", requestId: "event-request" } },
        { invokedFunctionArn: "arn:aws:lambda:region:account:function:test:restore" }), /CLUSTER_NAME and AWS_REGION/);
      await assert.rejects(handler({ action: "stop" },
        { invokedFunctionArn: "arn:aws:lambda:region:account:function:test:stop", awsRequestId: "scheduler-request" }), /CLUSTER_NAME and AWS_REGION/);
      assert.equal(JSON.parse(messages[1]).requestId, "event-request");
      assert.equal(JSON.parse(messages[2]).requestId, "scheduler-request");
    } finally {
      console.error = originalError;
    }
  } finally {
    process.env = saved;
  }
});

test("stop and restore preserve prior replicas, suspension and unrelated resources", async () => {
  const deployment = makeResource("web", 3);
  const zero = makeResource("already-zero", 0);
  const stateful = makeResource("database", 2);
  const unrelated = makeResource("other", 2, { app: "other" });
  const cronjob: TestResource = {
    metadata: { name: "report", namespace: "website", resourceVersion: "1" },
    spec: { suspend: false, jobTemplate: { spec: { template: { metadata: { labels: { app: "web" } } } } } }
  };
  const paused: TestResource = {
    metadata: { name: "paused", namespace: "website", resourceVersion: "1" },
    spec: { suspend: true, jobTemplate: { spec: { template: { metadata: { labels: { app: "web" } } } } } }
  };
  const job = makeResource("running", 1);
  const completed = { ...makeResource("completed", 1), status: { conditions: [{ type: "Complete", status: "True" }] } };
  const pod: TestResource = { metadata: { name: "web-pod", namespace: "website", resourceVersion: "1", labels: { app: "web" } }, spec: { nodeName: "fargate-node" } };
  const node: TestResource = { metadata: { name: "fargate-node", resourceVersion: "1", labels: { "eks.amazonaws.com/compute-type": "fargate" } }, spec: {} };
  const resources = {
    "/apis/apps/v1/deployments": [deployment, zero, unrelated],
    "/apis/apps/v1/statefulsets": [stateful],
    "/apis/batch/v1/cronjobs": [cronjob, paused],
    "/apis/batch/v1/jobs": [job, completed],
    "/api/v1/pods": [pod],
    "/api/v1/nodes": [node]
  };
  const kube = fakeKube(resources);
  await stop(kube, selectors, 0, 3);
  assert.equal(deployment.spec.replicas, 0);
  assert.equal(stateful.spec.replicas, 0);
  assert.equal(deployment.metadata.annotations?.[marker], "3");
  assert.equal(cronjob.spec.suspend, true);
  assert.equal(unrelated.spec.replicas, 2);
  assert.ok(kube.deletions.some((path) => path.endsWith("/jobs/running")));
  assert.ok(!kube.deletions.some((path) => path.endsWith("/jobs/completed")));
  await stop(kube, selectors, 0, 1);
  assert.equal(deployment.metadata.annotations?.[marker], "3");
  await restore(kube);
  assert.equal(deployment.spec.replicas, 3);
  assert.equal(zero.spec.replicas, 0);
  assert.equal(stateful.spec.replicas, 2);
  assert.equal(cronjob.spec.suspend, false);
  assert.equal(paused.spec.suspend, true);
  assert.equal(deployment.metadata.annotations?.[marker], undefined);
});

test("failures retain recovery state and do not touch EC2 pods", async () => {
  const deployment = makeResource("web", 2);
  const resources: Record<string, TestResource[]> = {
    "/apis/apps/v1/deployments": [deployment],
    "/api/v1/nodes": [{ metadata: { name: "ec2", resourceVersion: "1" }, spec: {} }],
    "/api/v1/pods": [{ metadata: { name: "pod", namespace: "website", resourceVersion: "1", labels: { app: "web" } }, spec: { nodeName: "ec2" } }]
  };
  const kube = fakeKube(resources);
  await assert.rejects(stop(kube, selectors, 0, 1), /non-Fargate node/);
  assert.equal(deployment.spec.replicas, 2);
  assert.deepEqual(kube.deletions, []);
  resources["/api/v1/pods"] = [];
  resources["/api/v1/nodes"] = [{ metadata: { name: "stuck", resourceVersion: "1", labels: { "eks.amazonaws.com/compute-type": "fargate" } }, spec: {} }];
  await assert.rejects(stop(kube, selectors, 0, 1), /remain after the timeout/);
  assert.equal(deployment.metadata.annotations?.[marker], "2");
  await restore(kube);
  assert.equal(deployment.spec.replicas, 2);
});
