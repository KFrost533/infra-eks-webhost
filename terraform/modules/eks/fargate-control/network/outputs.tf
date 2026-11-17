output "security_group_id" {
  value      = aws_security_group.function.id
  depends_on = [aws_vpc_security_group_ingress_rule.eks]
}
