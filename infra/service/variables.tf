variable "aws_region" {
  description = "AWS region to deploy to."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "data-service"
}

variable "ecr_repository_name" {
  description = "Name of the existing ECR repository that holds the image. The repository is created once, outside this module."
  type        = string
  default     = "data-service"
}

variable "image_digest" {
  description = "Digest of the image to deploy, e.g. sha256:<64 hex characters>. Deploying by digest means the exact tested image runs."
  type        = string

  validation {
    condition     = can(regex("^sha256:[0-9a-f]{64}$", var.image_digest))
    error_message = "image_digest must look like sha256: followed by 64 lowercase hex characters."
  }
}

variable "vpc_cidr" {
  description = "IP range of the VPC. Each subnet gets a /24 slice of it."
  type        = string
  default     = "10.0.0.0/16"
}

variable "container_port" {
  description = "Port the service listens on inside the container (the PORT default in the app)."
  type        = number
  default     = 8080
}

variable "task_cpu" {
  description = "CPU units for each task (1024 = 1 vCPU). Must be a valid Fargate combination with task_memory."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memory in MiB for each task."
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "How long CloudWatch keeps the service logs."
  type        = number
  default     = 14
}

variable "alarm_actions" {
  description = "ARNs notified when an alarm fires, e.g. an SNS topic. Empty means alarms only change state."
  type        = list(string)
  default     = []
}

variable "desired_count" {
  description = "Number of running tasks. Two keeps the service up while one task is replaced."
  type        = number
  default     = 2

  validation {
    condition     = var.desired_count >= 1
    error_message = "desired_count must be at least 1."
  }
}
