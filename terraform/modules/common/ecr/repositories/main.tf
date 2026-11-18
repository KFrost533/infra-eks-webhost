// My own application that handles youtube data
resource "aws_ecr_repository" "website" {
  name                 = "${var.project_name}-website"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "website" {
  repository = aws_ecr_repository.website.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the most recent 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = {
        type = "expire"
      }
    }]
  })
}

// Grafana ECR repository and lifecycle policy
resource "aws_ecr_repository" "grafana" {
  name                 = "${var.project_name}-grafana"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "grafana" {
  repository = aws_ecr_repository.grafana.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the most recent 5 Grafana images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}

// Loki ECR repository and lifecycle policy
resource "aws_ecr_repository" "loki" {
  name                 = "${var.project_name}-loki"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "loki" {
  repository = aws_ecr_repository.loki.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the most recent 5 Loki images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}

// Alloy ECR repository and lifecycle policy
resource "aws_ecr_repository" "alloy" {
  name                 = "${var.project_name}-alloy"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "alloy" {
  repository = aws_ecr_repository.alloy.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the most recent 5 Alloy images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}