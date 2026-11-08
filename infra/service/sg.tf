# Rules are separate resources (instead of inline blocks) so the two groups
# can refer to each other without a dependency cycle.

# Load balancer: the only component that accepts traffic from the internet.
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb"
  description = "Load balancer: HTTP from the internet, forwards to the tasks"
  vpc_id      = aws_vpc.main.id
}

# Plain HTTP for the MVP. (HTTPS needs a certificate and a domain)
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# The load balancer may only talk to the tasks, on the container port.
resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to the tasks"
  referenced_security_group_id = aws_security_group.tasks.id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

# Tasks: reachable only from the load balancer.
resource "aws_security_group" "tasks" {
  name        = "${var.project_name}-tasks"
  description = "Service tasks: traffic only from the load balancer"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb" {
  security_group_id            = aws_security_group.tasks.id
  description                  = "From the load balancer"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
}

# Tasks need outbound HTTPS to pull the image from ECR and ship logs to CloudWatch. Nothing else is allowed out.
resource "aws_vpc_security_group_egress_rule" "tasks_https" {
  security_group_id = aws_security_group.tasks.id
  description       = "HTTPS to AWS services (ECR, CloudWatch Logs)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
