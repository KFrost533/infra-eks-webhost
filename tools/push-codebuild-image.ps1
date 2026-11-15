param(
    [string]$AwsRegion = "ap-southeast-1",
    [string]$ProjectName = "infra-eks-webhost",
    [string]$ImageTag = "tools-v1"
)

$ErrorActionPreference = "Stop"

$accountId = & aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0) {
    throw "Unable to determine the AWS account. Check the AWS CLI credentials."
}

$repositoryName = "$ProjectName-build-tools"
$repositoryUri = "$accountId.dkr.ecr.$AwsRegion.amazonaws.com/$repositoryName"
$imageUri = "${repositoryUri}:$ImageTag"

& aws ecr describe-repositories --region $AwsRegion --repository-names $repositoryName *> $null
if ($LASTEXITCODE -ne 0) {
    throw "The ECR repository '$repositoryName' does not exist. Apply the Terraform configuration first."
}

$ecrPassword = & aws ecr get-login-password --region $AwsRegion
if ($LASTEXITCODE -ne 0) {
    throw "Unable to obtain ECR credentials."
}

$ecrPassword | & docker login --username AWS --password-stdin "$accountId.dkr.ecr.$AwsRegion.amazonaws.com"
if ($LASTEXITCODE -ne 0) {
    throw "Docker could not authenticate to ECR."
}

& docker build `
    --file tools\codebuild\Dockerfile `
    --build-arg "HELM_VERSION=3.17.3" `
    --tag $imageUri `
    .
if ($LASTEXITCODE -ne 0) {
    throw "Building the private CodeBuild tools image failed."
}

& docker push $imageUri
if ($LASTEXITCODE -ne 0) {
    throw "Pushing the private CodeBuild tools image to ECR failed."
}

Write-Host "Pushed $imageUri"
