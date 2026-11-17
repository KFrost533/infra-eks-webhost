resource "aws_security_group" "function" {
  name        = "${var.project_name}-fargate-control"
  description = "Lambda access to EKS and AWS APIs."
  vpc_id      = var.vpc_id
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "eks" {
  security_group_id            = var.cluster_security_group_id
  referenced_security_group_id = aws_security_group.function.id
  description                  = "Fargate control Lambda to private EKS API."
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}
