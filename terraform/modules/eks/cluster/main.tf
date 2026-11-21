data "aws_partition" "current" {}



resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.cluster_version

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = length(var.cluster_public_access_cidrs) > 0
    public_access_cidrs     = var.cluster_public_access_cidrs
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
}

resource "aws_vpc_security_group_ingress_rule" "codebuild_to_eks_api" {
  security_group_id            = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = var.codebuild_security_group_id
  description                  = "Allow CodeBuild to reach the private EKS API endpoint."
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_eks_fargate_profile" "system" {
  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "system"
  pod_execution_role_arn = var.fargate_pod_execution_role_arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = "kube-system"
    labels = {
      "k8s-app" = "kube-dns"
    }
  }

  selector {
    namespace = "kube-system"
    labels = {
      "k8s-app" = "metrics-server"
    }
  }
}

resource "aws_eks_fargate_profile" "website" {
  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "website"
  pod_execution_role_arn = var.fargate_pod_execution_role_arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = "website"
  }

  depends_on = [aws_eks_fargate_profile.system]
}

resource "aws_eks_fargate_profile" "monitoring" {
  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "monitoring"
  pod_execution_role_arn = var.fargate_pod_execution_role_arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = "monitoring"
  }

  depends_on = [aws_eks_fargate_profile.website]
}

// ==== Addons ====
// coredns, metrics-server, vpc-cni, kube-proxy

// coredns
data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  configuration_values        = jsonencode({ computeType = "Fargate" })
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [
    aws_eks_fargate_profile.system
  ]
}

// metrics-server
data "aws_eks_addon_version" "metrics_server" {
  addon_name         = "metrics-server"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "metrics-server"
  addon_version = data.aws_eks_addon_version.metrics_server.version

  depends_on = [aws_eks_fargate_profile.system]
}

// vpc-cni
data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "vpc-cni"
  addon_version = data.aws_eks_addon_version.vpc_cni.version

  depends_on = [aws_eks_fargate_profile.system]
}

// kube-proxy
data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = var.cluster_version
  most_recent        = true
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "kube-proxy"
  addon_version = data.aws_eks_addon_version.kube_proxy.version

  depends_on = [aws_eks_fargate_profile.system]
}

resource "aws_eks_access_entry" "codebuild" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.codebuild_role_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "codebuild" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.codebuild_role_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["website"]
  }

  depends_on = [
    aws_eks_access_entry.codebuild,
    aws_eks_fargate_profile.website
  ]
}