# Network: one VPC with two public subnets in two availability zones.
#
# The tasks run in public subnets and get public IPs so they can pull the
# image from ECR and send logs to CloudWatch without a NAT gateway, which would
# cost money all the time (docs/ODLOCITVE.md, decision 6). They are still not
# reachable from the internet: their security group only accepts traffic from
# the load balancer.

# Availability zones that are currently usable in the chosen region.
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Two zones are enough to keep the service up if one zone has problems.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.project_name }
}

# Without this, nothing in the VPC can reach (or be reached from) the internet.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = var.project_name }
}

resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  # 10.0.0.0/24 for the first zone, 10.0.1.0/24 for the second.
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)

  # Public IPs are assigned per task by the ECS service, not by the subnet.
  map_public_ip_on_launch = false

  tags = { Name = "${var.project_name}-public-${local.azs[count.index]}" }
}

# Route all non-local traffic through the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public" }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# The VPC's default security group allows all traffic between its members.
# Declaring it with no rules removes that, so nothing uses it by accident.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
}
