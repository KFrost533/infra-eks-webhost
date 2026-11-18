# EKS Website Hosting

The infrastructure is organised as local Terraform modules:

| Module | Responsibility |
|---|---|
| `eks` | EKS cluster, Fargate profiles, add-ons and optional Fargate control |
| `common` | Networking, IAM, log groups, ECR, CodeBuild, GitHub connection and alerts |

The shared root in `terraform\stacks\main` and the EKS root in `terraform\stacks\eks` use separate
Terraform states. Module directories group functionality, not resource lifetime:
for example, `common/network` is created and destroyed by the EKS stack.

The intended release flow is:

```text
GitHub push → CodeBuild → private ECR → Helm → EKS Fargate Pods
```

This design uses Fargate; it does not create EC2 worker nodes.

## Network and egress

- Public and private subnets span two Availability Zones.
- Public subnets and an Internet Gateway are reserved for an internet-facing Application Load Balancer.
- Both private subnets route internet traffic through one NAT Gateway in the first public subnet.
- ECR API and Docker interface endpoints plus an S3 gateway endpoint let CodeBuild and Fargate push/pull private ECR images without NAT.
- CloudWatch Logs, STS, EC2, and Elastic Load Balancing interface endpoints support private AWS API access.
- Fargate backend connections to a public MongoDB deployment use the NAT Gateway's static public IP. MongoDB commonly uses TCP 27017, not HTTPS; allow the deployment's required ports and DNS access. Browser-side calls originate from the visitor's browser and do not traverse the VPC. CodeBuild can access public TCP port 443 through NAT to download the Node.js base image and npm dependencies; this permits HTTPS to any public destination, not just package registries.
- The NAT Gateway is a single-AZ dependency; an outage in that AZ interrupts egress from both private subnets.
- The public EKS API endpoint is disabled unless `cluster_admin_cidrs` is set. CodeBuild reaches the private EKS API from the VPC.

The public network is prepared, but the AWS Load Balancer Controller and the public ALB are not installed yet. The Helm chart's Ingress is disabled by default.

## Provision infrastructure

Prerequisites: Terraform 1.5.7+, AWS CLI credentials, Docker, and permissions to create VPC, EKS, IAM, ECR, CodeBuild, CodeConnections, and CloudWatch resources.

**Existing deployments:** do not apply either root until state has been migrated
as described below. Otherwise Terraform may plan deletion or duplicate creation.

For a new deployment, from the repository root:

```powershell
Copy-Item terraform\stacks\main\terraform.tfvars.example terraform\stacks\main\terraform.tfvars
Copy-Item terraform\stacks\eks\terraform.tfvars.example terraform\stacks\eks\terraform.tfvars
```

Replace `YOUR_PUBLIC_IP/32` in `terraform\stacks\eks\terraform.tfvars` with the
operator's public IPv4 CIDR. The shared root creates ECR, the GitHub connection,
IAM roles, CodeBuild policy and log groups, plus Fargate control IAM and SNS
when enabled; it does not create EKS, VPC, NAT or the CodeBuild project.
Configure `website_repository_url` in the shared root so the CodeBuild source
and GitHub OIDC trust target the same repository.
It looks up an existing GitHub Actions IAM OIDC provider in the same AWS
account; create or manage that provider separately before planning. It is not
created, modified or deleted by this stack. If an earlier state already manages
`module.iam.aws_iam_openid_connect_provider.github`, transfer its ownership
without deleting it before applying this configuration, and review the plan.
Review its plan and apply it first:

```powershell
terraform -chdir=terraform\stacks\main init
terraform -chdir=terraform\stacks\main validate
terraform -chdir=terraform\stacks\main plan
terraform -chdir=terraform\stacks\main apply
```

Authorize the GitHub connection in AWS and push the private CodeBuild tools
image before deploying workloads. When EKS is needed, pass the current shared
output to the EKS root in the same PowerShell session:

```powershell
$env:TF_VAR_shared = terraform -chdir=terraform\stacks\main output -json eks_shared
if ($LASTEXITCODE -ne 0) { throw "Failed to read shared outputs." }
terraform -chdir=terraform\stacks\eks init
terraform -chdir=terraform\stacks\eks validate
terraform -chdir=terraform\stacks\eks plan
terraform -chdir=terraform\stacks\eks apply
```

Refresh `TF_VAR_shared` after every shared apply and in each new shell before
running EKS plan, apply or destroy. Both roots must use the same AWS account;
the EKS provider checks the account and region from the shared output. Keep
the shared resources in place while the EKS stack exists. Do not destroy shared
IAM, ECR or the connection first. Shared IAM, log storage, ECR images and other
remaining resources can still incur charges. Turning off
`enable_fargate_control` in the shared root deletes its Lambda log group and
the logs in it; review this change and its impact on the running EKS stack.

### Remove and recreate EKS

To stop EKS and NAT charges, refresh `TF_VAR_shared`, review
`terraform -chdir=terraform\stacks\eks plan -destroy`, then run
`terraform -chdir=terraform\stacks\eks destroy`. This destroys the cluster, VPC,
NAT, endpoints, CodeBuild project, Lambda, EventBridge and CloudWatch alarms,
**not** the shared IAM, SNS topic and email subscription. EKS does not support
pausing its control plane or NAT Gateway.
Delete any externally managed load balancers or other dependent resources as
necessary; they may prevent VPC deletion or continue to incur charges.

Recreate with the EKS commands above. Cluster objects, Secrets, Jobs and the
saved stop/restore annotations are lost; restore application manifests and
Secrets through the normal secure deployment process. The NAT public IP can
change, so update MongoDB and other IP allowlists. Reapply the Fargate log
router and RBAC, and verify workloads and DNS. The SNS email subscription
remains if the shared topic is retained.

### Migrate an existing local state

Do not run either apply or destroy until ownership is split. Back up the
existing state securely, stop other Terraform operations, and confirm the
backend, AWS account and state contents. The example below is **only** for
the previous local `terraform\terraform.tfstate` with the module addresses
shown; for another state location, remote backend or older resource addresses,
prepare a migration for that state instead. If both destination and source
already contain resources, resolve ownership before proceeding.

After backing up and verifying the state, move the previous local state into
`terraform\stacks\main\terraform.tfstate` only if that destination has no
state. Initialize both roots without applying. From `terraform\stacks\main`,
move each existing EKS-side module into `..\eks\terraform.tfstate` using
`terraform state mv -state-out=..\eks\terraform.tfstate <module> <module>`.
Move only modules that exist in the source state:

```text
module.network
module.eks
module.codebuild
module.fargate_control_network
module.fargate_control_access
module.fargate_control
module.fargate_control_bus
module.fargate_control_monitoring
module.fargate_control_schedule
```

Leave `module.ecr`, `module.iam`, `module.cloudwatch`,
`module.github_connection`, `module.codebuild_policy`,
`module.fargate_control_iam`, and `module.lambda_alerts` in the shared state.
Each state move changes files
immediately; stop and inspect both states if one fails. Refresh the shared
outputs and inspect **both** plans before any apply: no existing resource
should be unexpectedly created, destroyed or replaced. Any earlier Fargate
control refactoring without `moved` blocks may require additional
resource-address migration before these module moves. No state migration is
performed automatically.

If the EKS state already owns `module.codebuild_policy`,
`module.fargate_control_iam`, or `module.lambda_alerts`, these modules now
belong to the shared state. Back up both states and, from
`terraform\stacks\eks`, use
`terraform state mv -state-out=..\main\terraform.tfstate <module> <module>`
for each module present in the EKS state, after confirming it is absent from
the shared state. Use `module.codebuild_policy` for the policy and quote the
instance addresses `'module.fargate_control_iam[0]'` and
`'module.lambda_alerts[0]'` when present. Check both plans before applying.
Do not recreate the SNS
topic or its subscriptions. If `website_repository_url` was configured in the
EKS tfvars, move that setting to the shared tfvars before applying.

EKS control plane, NAT Gateway, interface endpoints, Fargate, ALB and data
transfer can incur charges. Review costs and complete plans before applying.

## Fargate monitoring

The Fargate pod execution role and a 30-day CloudWatch Logs group are provisioned by Terraform. After applying, configure the Fargate log router before creating application Pods, using an administrator with access to the EKS Kubernetes API:

```powershell
terraform -chdir=terraform\stacks\eks output -raw fargate_logging_manifest | kubectl apply -f -
```

New Fargate Pods will then send their container output to `/aws/eks/<cluster-name>/fargate`. Existing Pods must be restarted to pick up the router configuration. Avoid writing secrets or personal data to application logs.

Metrics Server provides current CPU and memory usage via `kubectl top pods`; it does not store history or create CloudWatch metrics or alarms. Historical Fargate Pod metrics and alerting still require a Fargate-compatible telemetry collector and separate configuration. The EKS control-plane log group does not replace Pod monitoring.

To find the fixed outbound IP for a MongoDB network allowlist, run `terraform -chdir=terraform\stacks\eks output -raw nat_gateway_public_ip` from the repository root after applying. Allow that address on the MongoDB deployment when required. Do not put connection strings or credentials in Terraform variables, state, logs, or the container image.

## Scheduled Fargate stop and restore

The optional Lambda discovers **all** Fargate profile selectors, suspends matching CronJobs, scales matching Deployments and StatefulSets to zero, deletes matching unfinished Jobs and Pods, and waits for Fargate nodes to disappear. This includes CoreDNS, Metrics Server and website workloads. Website access, cluster DNS, monitoring, and scheduled jobs stop; jobs interrupted by the stop are not resumed. The EKS control plane, NAT Gateway, endpoints and other resources continue to incur charges. Newly created Pods, autoscalers, deployments or add-on reconciliation can recreate workloads; keep automatic deployments and scaling disabled during the stopped period. The Lambda fails if matching Pods or Fargate nodes remain after its wait.

The previous replica count and CronJob suspend state are stored in annotations on each resource when it is stopped. The restore action restores those settings, including an original replica count of zero or an already-suspended CronJob. It does **not** recreate deleted Jobs, standalone Pods, or resources deleted or replaced while stopped. Do not remove the `fargate-control.kfrost533.dev/previous-state` annotations or run Helm upgrades while stopped. Restore requests do not wait for application or DNS readiness; check the cluster afterward.

To configure:

1. Build the function from the repository root with Node.js 22 and npm:
   ```powershell
   Set-Location terraform\modules\eks\fargate-control\lambda
   npm ci
   npm run build
   npm run typecheck
   npm test
   Set-Location ..\..\..\..\..
   ```
   Repeat the build before applying changes to the Lambda source. The generated `dist` bundle is not committed.
2. Set `enable_fargate_control = true` in `terraform\stacks\main\terraform.tfvars`, apply the shared root and refresh `TF_VAR_shared`. This creates IAM and the SNS topic. Leave `enable_fargate_stop_schedule = false` in `terraform\stacks\eks\terraform.tfvars`, then review and apply the EKS plan for the Lambda, network access, event bus, alarms and a **disabled** schedule. The Lambda needs VPC NAT access to the regional EKS API and uses the existing STS endpoint.
3. Using an administrator kubeconfig for the target cluster, apply `kubectl apply -f terraform\modules\eks\fargate-control\lambda\scaler-rbac.yaml` from the repository root. This grants the Lambda's EKS access-entry group cluster-wide list/patch/delete permissions, separate from IAM. Review the manifest and verify the target cluster first.
4. In the SNS console, create an email subscription to the topic shown by `terraform -chdir=terraform\stacks\eks output -raw lambda_alerts_topic_arn` and confirm it using the link in the email. Notifications are not delivered before confirmation.
5. In GitHub repository settings, set secret `FARGATE_RESTORE_ROLE_ARN` to `terraform -chdir=terraform\stacks\eks output -raw fargate_restore_role_arn`, and variables `AWS_REGION` to the deployment region and `FARGATE_CONTROL_BUS_NAME` to `terraform -chdir=terraform\stacks\eks output -raw fargate_control_bus_name`. Only the configured repository's `main` branch can assume the role; it can send matching events to the control bus, not invoke Lambda directly. Protect the main branch and workflow.
6. During a controlled maintenance window, run **Control EKS Fargate** on `main` with `stop`, check the corresponding CloudWatch logs and alarms, then run it with `start`. Verify original replicas, CronJob state, Pod readiness and DNS. A timeout or partial failure can leave some workloads stopped; inspect logs before retrying.
7. Only after successful testing, set `enable_fargate_stop_schedule = true`, review and apply the plan. EventBridge Scheduler invokes the stop alias daily at **17:00 Asia/Tokyo**. To stop scheduling, set the variable to `false` and apply.

GitHub Actions confirms only that EventBridge accepted the request, not that it matched a rule or that Lambda completed. Check the request ID in `/aws/lambda/<project>-fargate-control` logs for `FARGATE_CONTROL_SUCCESS` or `FARGATE_CONTROL_FAILURE`. Check workload readiness separately. EventBridge and Lambda deliver asynchronously and can duplicate or delay events; avoid overlapping stop/start requests and verify the outcome before issuing another. Retries are disabled and event age is limited to 60 seconds, but ordering and exactly-once execution are not guaranteed. Verify the configured bus name: EventBridge can accept an event addressed to a nonexistent bus without delivering it.

The reusable Lambda monitoring module sends SNS notifications via a composite alarm: a CloudWatch Logs metric filter detects the function's explicit failure marker, while Lambda `Errors`, `Throttles`, and `AsyncEventsDropped` metrics cover failures including timeouts and dropped asynchronous invocations. EventBridge rule `FailedInvocations` alarms cover failed delivery to Lambda. Scheduler delivery failures before Lambda invocation are not covered by these alarms. CloudWatch/EventBridge metrics and delivery are not a guaranteed audit trail; inspect logs and verify results. The composite sends a notification on transition to ALARM, not for each failure while it remains in ALARM. Additional log metrics, alarms, SNS notifications and EventBridge usage may incur charges. To monitor another Lambda, instantiate the monitoring module with its log group, failure filter pattern and topic; no other Lambda functions are configured here.

## Weekly YouTube CSV email

The optional EKS CronJob emails a CSV of **all saved YouTube search-result rows** every Monday at 09:00 `Asia/Tokyo`. It does not run a new YouTube search or deduplicate results from different searches. It runs separately from the existing daily search scheduler, which is unchanged. The job requires the cluster, MongoDB and SES SMTP endpoint to be reachable at the scheduled time.

The CSV is UTF-8 with a BOM and contains date, keyword, video ID, title, URL, channel and publication date. Spreadsheet formula-like values are escaped. The attachment is limited to 6 MiB to leave room for MIME encoding within the SES SMTP message limit. If the full CSV exceeds that limit, the job fails without sending a partial report.

Before enabling it:

1. Verify the sender identity in Amazon SES in the same region as the SMTP endpoint. In the SES sandbox, verify the recipient too; review sending quotas and request production access if necessary.
2. Create region-specific SES SMTP credentials with least-privilege permission to send from the verified identity. SMTP credentials are not the same as ordinary AWS access keys.
3. Use a secure secret-management process to provision the `youtube-report-ses` Kubernetes Secret in the `website` namespace with these keys:

   | Key | Value |
   |---|---|
   | `REPORT_SMTP_HOST` | Regional SES SMTP hostname, for example `email-smtp.ap-southeast-1.amazonaws.com` |
   | `REPORT_SMTP_USER` | SES SMTP user name |
   | `REPORT_SMTP_PASS` | SES SMTP password |
   | `REPORT_SMTP_FROM` | Verified sender email address |
   | `REPORT_TO` | One recipient email address |

   Do not commit these values, place them in Terraform variables, or pass them as shell command arguments. Restrict Secret access and protect Kubernetes Secret data at rest. The job reuses the `ACCESS_MONGODB_URI` key in the existing `website-secrets` Secret.
4. Ensure the private Fargate workload can reach MongoDB and the SES SMTP endpoint via NAT, including DNS and outbound TCP 587. The connection requires STARTTLS.
5. Set `enable_weekly_report = true` in `terraform\stacks\eks\terraform.tfvars`, review and apply the EKS Terraform plan, and run a CodeBuild deployment. CodeBuild passes this setting to Helm on each deployment; leaving it false disables the CronJob. For manual Helm deployments, set `weeklyReport.enabled=true` and retain the image values.

The job has no automatic retry after a failed attempt because SES may have accepted a message before a connection failure. Kubernetes scheduling is best effort: prolonged cluster or network outages may cause a run to be missed. Check `kubectl get cronjob -n website` and `kubectl get jobs -n website`; inspect a failed job's logs without exposing Secret values. Set up separate job-failure alerting and SES delivery/bounce monitoring if needed. Acceptance by SES does not guarantee delivery, and manually rerunning a job can send a duplicate email.

## Prepare CI

Keep `enable_github_webhook = false` and do not deploy until the MongoDB connection and secret provisioning are verified. The repository, application, buildspec and chart are intended to live together in `KFrost533/infra-eks-webhost` on the `main` branch. Create the repository and review all staged files before pushing; the ignore files are safeguards, not a substitute for checking for secrets and private data.

The CodeBuild project uses a private ECR build image containing Helm. Once infrastructure is approved and created, build and push that tools image from a workstation with Docker and internet access:

```powershell
Set-Location <repository-root>
.\tools\push-codebuild-image.ps1
```

Then:

1. Authorise the pending GitHub CodeConnections connection in the AWS Console and grant it access to the combined repository.
2. Configure the Fargate log router and create the `website` namespace using an administrator kubeconfig. The CodeBuild role is intentionally limited to editing resources in that namespace.
3. Configure MongoDB access and backups, and provision a Kubernetes Secret named `website-secrets` in the `website` namespace with keys `ACCESS_MONGODB_URI` and `API_KEY_ENCRYPTION_KEY`. Use a secure secret-management process; do not commit values or put them in Helm values or Terraform state. Keep the encryption key stable.
4. After the application and deployment are verified, set `enable_github_webhook = true` in `terraform\stacks\eks\terraform.tfvars`, review the plan, and apply it. Every push to `main` will trigger a build.

The buildspec builds and pushes an image tagged with the source commit and unique build ID, then runs `helm upgrade --install`. Concurrent builds or retries can deploy an older commit after a newer one. A CodeBuild project concurrency limit of one is not a queue: additional builds are rejected while one runs. Design and verify deployment ordering and retry handling before enabling automated releases. The Helm chart deploys to Fargate Pods. Public access requires the AWS Load Balancer Controller to be installed and the chart Ingress enabled after the controller is ready.

The application connects directly to MongoDB with Mongoose; existing SQLite data is not imported. The chart requires the Secret before Pods can start. Test connectivity, permissions, backup and recovery before deployment. Monitor MongoDB connection counts and errors, and tune connection pools only after observing workload and capacity. The application and its administrative endpoints should not be publicly exposed without an appropriate authentication design.
