# The registry that holds the service image. It lives here, not in
# infra/service, for two reasons:
#   1. The pipeline pushes the image before it deploys the service, so the
#      repository has to exist first.
#   2. Destroying the service must not delete the images.

resource "aws_ecr_repository" "app" {
  name = var.ecr_repository_name

  # Tags cannot be moved to another image. CI tags images with the commit SHA,
  # so a tag always points to the same build.
  image_tag_mutability = "IMMUTABLE"

  # AWS scans each pushed image for known vulnerabilities.
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep storage small and cheap by expiring old images.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the ${var.ecr_images_to_keep} most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.ecr_images_to_keep
      }
      action = { type = "expire" }
    }]
  })
}
