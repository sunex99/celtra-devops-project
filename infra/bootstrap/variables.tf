variable "aws_region" {
  description = "AWS region to create the resources in."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Used for resource tags."
  type        = string
  default     = "data-service"
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository. Must match ecr_repository_name in infra/service."
  type        = string
  default     = "data-service"
}

variable "ecr_images_to_keep" {
  description = "Number of most recent images to keep; older ones are deleted."
  type        = number
  default     = 20
}
