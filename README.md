# EKS Website Hosting

The infrastructure is organised as local Terraform modules:

| Module | Responsibility |
|---|---|
| `network` | VPC, two-AZ public/private subnets, Internet Gateway, NAT Gateway, and VPC endpoints |
| `eks` | EKS control plane, Fargate profiles, CoreDNS, Metrics Server, and CodeBuild access |
| `iam` | EKS, Fargate, and CodeBuild roles and CodeBuild policy |
| `github_connection` | GitHub CodeConnections connection |
| `codebuild` | Build project and optional push webhook |
| `ecr` | Website and private CodeBuild tools image repositories |
| `cw` | EKS, Fargate, and CodeBuild log groups |

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

From the repository root:

```powershell
Copy-Item terraform\main\terraform.tfvars.example terraform\main\terraform.tfvars
```

Replace `YOUR_PUBLIC_IP/32` in `terraform.tfvars` with the operator's public IPv4 CIDR. Then validate and review the plan:

```powershell
Set-Location terraform
terraform fmt -check -recursive
Set-Location main
terraform init
terraform validate
terraform plan
```

Review costs and the complete plan before running `terraform apply`. EKS control plane, NAT Gateway, interface endpoints, Fargate, ALB, and data transfer can incur charges.

## Fargate monitoring

The Fargate pod execution role and a 30-day CloudWatch Logs group are provisioned by Terraform. After applying, configure the Fargate log router before creating application Pods, using an administrator with access to the EKS Kubernetes API:

```powershell
terraform output -raw fargate_logging_manifest | kubectl apply -f -
```

New Fargate Pods will then send their container output to `/aws/eks/<cluster-name>/fargate`. Existing Pods must be restarted to pick up the router configuration. Avoid writing secrets or personal data to application logs.

Metrics Server provides current CPU and memory usage via `kubectl top pods`; it does not store history or create CloudWatch metrics or alarms. Historical Fargate Pod metrics and alerting still require a Fargate-compatible telemetry collector and separate configuration. The EKS control-plane log group does not replace Pod monitoring.

To find the fixed outbound IP for a MongoDB network allowlist, run `terraform output -raw nat_gateway_public_ip` after applying. Allow that address on the MongoDB deployment when required. Do not put connection strings or credentials in Terraform variables, state, logs, or the container image.

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
5. Set `enable_weekly_report = true` in `terraform\main\terraform.tfvars`, review and apply the Terraform plan, and run a CodeBuild deployment. CodeBuild passes this setting to Helm on each deployment; leaving it false disables the CronJob. For manual Helm deployments, set `weeklyReport.enabled=true` and retain the image values.

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
4. After the application and deployment are verified, set `enable_github_webhook = true` in `terraform.tfvars`, review the plan, and apply it. Every push to `main` will trigger a build.

The buildspec builds and pushes an image tagged with the source commit and unique build ID, then runs `helm upgrade --install`. Concurrent builds or retries can deploy an older commit after a newer one. A CodeBuild project concurrency limit of one is not a queue: additional builds are rejected while one runs. Design and verify deployment ordering and retry handling before enabling automated releases. The Helm chart deploys to Fargate Pods. Public access requires the AWS Load Balancer Controller to be installed and the chart Ingress enabled after the controller is ready.

The application connects directly to MongoDB with Mongoose; existing SQLite data is not imported. The chart requires the Secret before Pods can start. Test connectivity, permissions, backup and recovery before deployment. Monitor MongoDB connection counts and errors, and tune connection pools only after observing workload and capacity. The application and its administrative endpoints should not be publicly exposed without an appropriate authentication design.
