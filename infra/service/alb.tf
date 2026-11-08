# Application Load Balancer: the single public entry point of the service.
#
# Request path:  client -> listener (:80) -> target group -> a healthy task
# The target group only contains tasks that pass the /healthz check, so a task
# that is starting up, or has failed, does not receive traffic.

resource "aws_lb" "main" {
  name               = var.project_name
  load_balancer_type = "application"
  internal           = false # Reachable from the internet
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Drop requests with malformed headers instead of passing them to the app.
  drop_invalid_header_fields = true

  # Left off on purpose so the whole stack can be destroyed after a demo. For a long-lived production service this should be true.
  enable_deletion_protection = false
}

resource "aws_lb_target_group" "app" {
  name     = var.project_name
  vpc_id   = aws_vpc.main.id
  port     = var.container_port
  protocol = "HTTP"

  # Fargate tasks have their own network interface, so they are registered by IP address, not by instance.
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15 # Seconds between checks.
    timeout             = 5
    healthy_threshold   = 2 # Two passes in a row: the task is healthy.
    unhealthy_threshold = 3 # Three failures in a row: it is taken out.
  }
}

# Plain HTTP for the MVP
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
