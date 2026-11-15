import { DescribeClusterCommand, DescribeFargateProfileCommand, EKSClient, ListFargateProfilesCommand } from "@aws-sdk/client-eks";
import { Sha256 } from "@aws-crypto/sha256-js";
import { defaultProvider } from "@aws-sdk/credential-provider-node";
import { HttpRequest } from "@aws-sdk/protocol-http";
import { SignatureV4 } from "@aws-sdk/signature-v4";
import { request as httpsRequest } from "node:https";

type Metadata = { name: string; namespace?: string; resourceVersion: string; labels?: Record<string, string>; annotations?: Record<string, string> };
type PodTemplate = { metadata?: { labels?: Record<string, string> } };
type Resource = {
  metadata: Metadata;
  spec: { replicas?: number; suspend?: boolean; template?: PodTemplate; jobTemplate?: { spec: { template: PodTemplate } } };
  status?: { conditions?: Array<{ type: string; status: string }> };
};
type Pod = { metadata: Metadata; spec: { nodeName?: string } };
type Node = { metadata: Metadata };
type ProfileSelector = { namespace: string; labels?: Record<string, string> };
type Kind = "deployments" | "statefulsets" | "cronjobs";
type KubeClient = {
  list<T>(path: string): Promise<T[]>;
  patch(path: string, value: object): Promise<void>;
  delete(path: string, value?: object): Promise<void>;
};

const annotation = "fargate-control.kfrost533.dev/previous-state";
const paths: Record<Kind, string> = {
  deployments: "/apis/apps/v1/deployments",
  statefulsets: "/apis/apps/v1/statefulsets",
  cronjobs: "/apis/batch/v1/cronjobs"
};
const resourcePath = (kind: Kind | "jobs", metadata: Metadata) =>
  `/apis/${kind === "cronjobs" || kind === "jobs" ? "batch" : "apps"}/v1/namespaces/${encodeURIComponent(metadata.namespace!)}/${kind}/${encodeURIComponent(metadata.name)}`;
const podPath = (metadata: Metadata) =>
  `/api/v1/namespaces/${encodeURIComponent(metadata.namespace!)}/pods/${encodeURIComponent(metadata.name)}`;

function wildcard(pattern: string, value: string): boolean {
  const expression = pattern.split("").map((character) =>
    character === "*" ? ".*" : character === "?" ? "." : character.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&")
  ).join("");
  return new RegExp(`^${expression}$`).test(value);
}

export function matchesProfile(namespace: string, labels: Record<string, string>, selectors: ProfileSelector[]): boolean {
  return selectors.some((selector) => wildcard(selector.namespace, namespace) &&
    Object.entries(selector.labels || {}).every(([key, value]) => Object.entries(labels).some(([label, actual]) =>
      wildcard(key, label) && wildcard(value, actual))));
}

function templateLabels(resource: Resource, kind: Kind | "jobs"): Record<string, string> {
  return (kind === "cronjobs" ? resource.spec.jobTemplate?.spec.template : resource.spec.template)?.metadata?.labels || {};
}

function statePatch(kind: Kind, resource: Resource, restore: boolean): object {
  const previous = resource.metadata.annotations?.[annotation];
  if (restore) {
    if (!previous) throw new Error(`Missing recovery state: ${kind}/${resource.metadata.name}`);
    const saved: unknown = JSON.parse(previous);
    if (kind === "cronjobs" ? typeof saved !== "boolean" : !Number.isInteger(saved) || (saved as number) < 0) {
      throw new Error(`Invalid recovery state: ${kind}/${resource.metadata.name}`);
    }
    return {
      metadata: { resourceVersion: resource.metadata.resourceVersion, annotations: { [annotation]: null } },
      spec: kind === "cronjobs" ? { suspend: saved } : { replicas: saved }
    };
  }
  if (previous !== undefined) return {};
  const saved = kind === "cronjobs" ? resource.spec.suspend === true : resource.spec.replicas ?? 1;
  return {
    metadata: { resourceVersion: resource.metadata.resourceVersion, annotations: { [annotation]: JSON.stringify(saved) } },
    spec: kind === "cronjobs" ? { suspend: true } : { replicas: 0 }
  };
}

export async function restore(kube: KubeClient): Promise<void> {
  for (const kind of ["deployments", "statefulsets", "cronjobs"] as const) {
    for (const resource of await kube.list<Resource>(paths[kind])) {
      if (resource.metadata.annotations?.[annotation] === undefined) continue;
      await kube.patch(resourcePath(kind, resource.metadata), statePatch(kind, resource, true));
      console.log(`Restored ${kind}/${resource.metadata.namespace}/${resource.metadata.name}`);
    }
  }
}

export async function stop(kube: KubeClient, selectors: ProfileSelector[], wait = 5000, attempts = 72): Promise<void> {
  if (!selectors.length) throw new Error("No Fargate profile selectors were found; refusing to stop.");
  const initialNodes = await kube.list<Node>("/api/v1/nodes");
  const fargateNodes = new Set(initialNodes.filter((node) =>
    node.metadata.labels?.["eks.amazonaws.com/compute-type"] === "fargate").map((node) => node.metadata.name));
  const initialPods = await kube.list<Pod>("/api/v1/pods");
  for (const pod of initialPods) {
    if (pod.metadata.namespace && matchesProfile(pod.metadata.namespace, pod.metadata.labels || {}, selectors) &&
      pod.spec.nodeName && !fargateNodes.has(pod.spec.nodeName)) {
      throw new Error(`Pod ${pod.metadata.namespace}/${pod.metadata.name} matches a Fargate profile but is on a non-Fargate node.`);
    }
  }
  for (const kind of ["cronjobs", "deployments", "statefulsets"] as const) {
    for (const resource of await kube.list<Resource>(paths[kind])) {
      const metadata = resource.metadata;
      if (!metadata.namespace || !matchesProfile(metadata.namespace, templateLabels(resource, kind), selectors)) continue;
      if (metadata.annotations?.[annotation] !== undefined) {
        const alreadyStopped = kind === "cronjobs" ? resource.spec.suspend === true : resource.spec.replicas === 0;
        if (!alreadyStopped) throw new Error(`${kind}/${metadata.namespace}/${metadata.name} restarted while a previous stop is active.`);
        continue;
      }
      await kube.patch(resourcePath(kind, metadata), statePatch(kind, resource, false));
      console.log(`Stopped ${kind}/${metadata.namespace}/${metadata.name}; previous state saved.`);
    }
  }
  for (const job of await kube.list<Resource>("/apis/batch/v1/jobs")) {
    const finished = job.status?.conditions?.some((condition) =>
      (condition.type === "Complete" || condition.type === "Failed") && condition.status === "True");
    if (!finished && job.metadata.namespace && matchesProfile(job.metadata.namespace, templateLabels(job, "jobs"), selectors)) {
      await kube.delete(resourcePath("jobs", job.metadata), { propagationPolicy: "Background" });
      console.log(`Deleted job/${job.metadata.namespace}/${job.metadata.name}; jobs are not restored.`);
    }
  }
  for (let attempt = 0; attempt < attempts; attempt++) {
    const pods = (await kube.list<Pod>("/api/v1/pods")).filter((pod) =>
      !!pod.metadata.namespace && matchesProfile(pod.metadata.namespace, pod.metadata.labels || {}, selectors));
    const nodes = (await kube.list<Node>("/api/v1/nodes")).filter((node) =>
      node.metadata.labels?.["eks.amazonaws.com/compute-type"] === "fargate");
    if (!pods.length && !nodes.length) return;
    const currentFargateNodes = new Set(nodes.map((node) => node.metadata.name));
    for (const pod of pods) {
      if (pod.spec.nodeName && !currentFargateNodes.has(pod.spec.nodeName)) {
        throw new Error(`Refusing to delete pod on a non-Fargate node: ${pod.metadata.namespace}/${pod.metadata.name}`);
      }
      await kube.delete(podPath(pod.metadata), { propagationPolicy: "Background" });
      console.log(`Deleted pod/${pod.metadata.namespace}/${pod.metadata.name}`);
    }
    await new Promise((resolve) => setTimeout(resolve, wait));
  }
  throw new Error("Fargate pods or nodes remain after the timeout. Recovery annotations were retained.");
}

class KubernetesApi implements KubeClient {
  constructor(private readonly endpoint: string, private readonly ca: string, private readonly token: string) {}

  private async request(method: string, path: string, body?: object): Promise<unknown> {
    const url = new URL(path, this.endpoint);
    const payload = body === undefined ? undefined : JSON.stringify(body);
    return new Promise((resolve, reject) => {
      const req = httpsRequest(url, {
        method, ca: Buffer.from(this.ca, "base64"), headers: {
          Authorization: `Bearer ${this.token}`,
          ...(payload ? { "Content-Type": method === "PATCH" ? "application/merge-patch+json" : "application/json" } : {})
        }
      }, (res) => {
        let response = "";
        res.setEncoding("utf8");
        res.on("data", (chunk: string) => { response += chunk; });
        res.on("end", () => {
          if (method === "DELETE" && res.statusCode === 404) return resolve(undefined);
          if (!res.statusCode || res.statusCode < 200 || res.statusCode >= 300) {
            return reject(new Error(`Kubernetes ${method} ${url.pathname} returned HTTP ${res.statusCode}: ${response}`));
          }
          try { resolve(response ? JSON.parse(response) : undefined); } catch (error) { reject(error); }
        });
      });
      req.setTimeout(15000, () => req.destroy(new Error(`Kubernetes request timed out: ${url.pathname}`)));
      req.on("error", reject);
      req.end(payload);
    });
  }

  async list<T>(path: string): Promise<T[]> {
    const items: T[] = [];
    let continuation = "";
    do {
      const query = new URLSearchParams({ limit: "500" });
      if (continuation) query.set("continue", continuation);
      const result = await this.request("GET", `${path}?${query}`);
      if (!result || typeof result !== "object" || !("items" in result) || !Array.isArray(result.items) ||
        !("metadata" in result) || !result.metadata || typeof result.metadata !== "object") {
        throw new Error(`Invalid Kubernetes list response: ${path}`);
      }
      items.push(...result.items as T[]);
      const metadata = result.metadata as { continue?: string };
      continuation = metadata.continue || "";
    } while (continuation);
    return items;
  }
  async patch(path: string, value: object): Promise<void> { await this.request("PATCH", path, value); }
  async delete(path: string, value?: object): Promise<void> { await this.request("DELETE", path, value); }
}

async function eksToken(cluster: string, region: string): Promise<string> {
  const hostname = `sts.${region}.amazonaws.com`;
  const signer = new SignatureV4({ credentials: defaultProvider(), region, service: "sts", sha256: Sha256 });
  const signed = await signer.presign(new HttpRequest({
    protocol: "https:", hostname, method: "GET", path: "/", headers: { host: hostname, "x-k8s-aws-id": cluster },
    query: { Action: "GetCallerIdentity", Version: "2011-06-15" }
  }), { expiresIn: 60, unhoistableHeaders: new Set(["x-k8s-aws-id"]) });
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(signed.query || {})) {
    for (const item of Array.isArray(value) ? value : [value]) if (item !== undefined) params.append(key, item);
  }
  return `k8s-aws-v1.${Buffer.from(`https://${hostname}/?${params}`).toString("base64url")}`;
}

export async function handler(event: { action?: string }): Promise<{ ok: true; action: string }> {
  if (event.action !== "stop" && event.action !== "restore") throw new Error("Action must be stop or restore.");
  const clusterName = process.env.CLUSTER_NAME;
  const region = process.env.AWS_REGION;
  if (!clusterName || !region) throw new Error("CLUSTER_NAME and AWS_REGION are required.");
  const eks = new EKSClient({ region });
  const response = await eks.send(new DescribeClusterCommand({ name: clusterName }));
  const endpoint = response.cluster?.endpoint;
  const ca = response.cluster?.certificateAuthority?.data;
  if (!endpoint || !ca) throw new Error("EKS cluster endpoint or CA is unavailable.");
  const kube = new KubernetesApi(endpoint, ca, await eksToken(clusterName, region));
  if (event.action === "restore") await restore(kube);
  else {
    const selectors: ProfileSelector[] = [];
    let nextToken: string | undefined;
    do {
      const profiles = await eks.send(new ListFargateProfilesCommand({ clusterName, nextToken }));
      for (const name of profiles.fargateProfileNames || []) {
        const profile = await eks.send(new DescribeFargateProfileCommand({ clusterName, fargateProfileName: name }));
        for (const selector of profile.fargateProfile?.selectors || []) {
          if (!selector.namespace) throw new Error(`Profile ${name} has a selector without a namespace.`);
          selectors.push({ namespace: selector.namespace, labels: selector.labels });
        }
      }
      nextToken = profiles.nextToken;
    } while (nextToken);
    await stop(kube, selectors);
  }
  return { ok: true, action: event.action };
}