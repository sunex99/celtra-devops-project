# CloudWatch alarms for the basics: the service returns errors, tasks are
# unhealthy, or responses are slow. Where notifications go is left to the
# alarm_actions variable (for example an SNS topic).
#
# For all three, "no data" counts as OK: with no traffic there are no
# requests to measure, and that is not a problem.

locals {
  # Identify this load balancer and target group in the metrics.
  alb_dimensions = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
}

# The app itself answers with 5xx.
resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${var.project_name}-5xx"
  alarm_description   = "The service returned 5 or more 5xx responses per minute for 3 minutes in a row"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = local.alb_dimensions
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions
}

# At least one task fails its /healthz check.
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project_name}-unhealthy-hosts"
  alarm_description   = "At least one task has been failing health checks for 3 minutes"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = local.alb_dimensions
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions
}

# 1 in 100 requests takes longer than one second. Averages hide this, so the alarm uses the 99th percentile.
resource "aws_cloudwatch_metric_alarm" "latency_p99" {
  alarm_name          = "${var.project_name}-latency-p99"
  alarm_description   = "The 99th percentile response time was over 1 second for 5 minutes in a row"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.alb_dimensions
  extended_statistic  = "p99"
  period              = 60
  evaluation_periods  = 5
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions
}
