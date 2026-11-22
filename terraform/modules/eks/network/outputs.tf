output "public_ip" {
  description = "Public IPv4 address used by private workloads for internet egress."
  value       = aws_eip.this.public_ip
}
