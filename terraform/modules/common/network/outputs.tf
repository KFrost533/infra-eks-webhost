output "vpc_id" {
  description = "VPC identifier."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet identifiers."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet identifiers."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_public_ip" {
  description = "Public IPv4 address used by private workloads for internet egress."
  value       = aws_eip.nat.public_ip
}

output "codebuild_security_group_id" {
  description = "Security group ID assigned to CodeBuild build environments."
  value       = aws_security_group.codebuild.id
}

output "ecr_endpoint_ids" {
  description = "ECR API and Docker interface endpoint IDs."
  value = {
    api = aws_vpc_endpoint.interface["ecr.api"].id
    dkr = aws_vpc_endpoint.interface["ecr.dkr"].id
    s3  = aws_vpc_endpoint.s3.id
  }
}

output "interface_endpoint_ids" {
  description = "Interface endpoint IDs for private AWS API access."
  value       = { for name, endpoint in aws_vpc_endpoint.interface : name => endpoint.id }
}
