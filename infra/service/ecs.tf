# ECS on Fargate: runs the container image and keeps the desired number of
# tasks alive. Fargate means there are no servers to manage.

# The ECR repository is created once, outside this module (infra/bootstrap),
# so deleting the service never deletes the images. We only look it up here.
data "aws_ecr_repository" "app" {
  name = var.ecr_repository_name
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_ecs_cluster" "main" {
  name = var.project_name

  # Per-task CPU, memory and network metrics in CloudWatch.
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# IAM: execution role used by ECS itself (not by our application) to start the task: pull the image from ECR and write the container's logs. 
# The application gets no AWS permissions at all, because it never calls an AWS API; that is why there is no task role.
data "aws_iam_policy_document" "ecs_tasks_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.project_name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume_role.json
}

# Least privilege: only this repository and only this log group, instead of the broader AWS-managed AmazonECSTaskExecutionRolePolicy.
data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # This action cannot be limited to a resource.
  }

  statement {
    sid       = "PullImage"
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    resources = [data.aws_ecr_repository.app.arn]
  }

  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "pull-image-and-write-logs"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}


# Task definition: what to run
resource "aws_ecs_task_definition" "app" {
  family                   = var.project_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # Each task gets its own network interface.
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    # Must match the CPU architecture of the image. CI builds on an amd64 runner, so the image is x86_64.
    cpu_architecture = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name      = "app"
      essential = true

      # Deployed by digest: this is exactly the image that CI built and tested.
      image = "${data.aws_ecr_repository.app.repository_url}@${var.image_digest}"

      portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
      environment  = [{ name = "PORT", value = tostring(var.container_port) }]

      # The app only writes to stdout, so the filesystem can be read-only.
      readonlyRootFilesystem = true

      # The service needs no Linux capabilities.
      linuxParameters = { capabilities = { drop = ["ALL"] } }

      # No container-level health check: the distroless image has no shell or curl to run one. The load balancer checks /healthz instead.
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])
}

# Service: keep the tasks running and roll out new versions
resource "aws_ecs_service" "app" {
  name            = var.project_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Rolling deployment without downtime: start the new tasks first (up to
  # double the count), and only stop old tasks once the new ones are healthy.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # If the new tasks never become healthy, ECS stops the deployment and goes
  # back to the last working task definition by itself.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Make "terraform apply" wait until the deployment is finished. If the
  # circuit breaker rolled back, apply fails, so the pipeline turns red
  # instead of reporting a deploy that did not happen.
  wait_for_steady_state = true

  # Give a new task time to start before failed health checks count.
  health_check_grace_period_seconds = 30

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true # Needed to reach ECR without a NAT gateway (docs/SPEC.md, section 5).
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  # The target group must be attached to a listener before the service uses it.
  depends_on = [aws_lb_listener.http]
}
