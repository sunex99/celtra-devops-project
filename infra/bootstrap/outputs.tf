output "ecr_repository_url" {
  description = "Where the pipeline pushes the image."
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_name" {
  description = "Pass this to infra/service as ecr_repository_name."
  value       = aws_ecr_repository.app.name
}
