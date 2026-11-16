# -----------------------------------------------------------------------------
# Rede Isolada por Ambiente (VPC, Subnets e Security Group para ECS Fargate)
# -----------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "env" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

resource "aws_internet_gateway" "env" {
  vpc_id = aws_vpc.env.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

resource "aws_subnet" "app" {
  count = 2

  vpc_id                  = aws_vpc.env.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = var.is_ephemeral

  tags = {
    Name = "${var.project_name}-${var.environment}-subnet-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.env.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.env.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rt"
  }
}

resource "aws_route_table_association" "app" {
  count = 2

  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-${var.environment}-ecs-tasks-sg"
  description = "Controla o tráfego de entrada e saída das tasks Fargate no ambiente ${var.environment}."
  vpc_id      = aws_vpc.env.id

  ingress {
    description = "Tráfego HTTP para o container da aplicação"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress necessário para o ECS Agent alcançar ECR e CloudWatch Logs,
  # e para a aplicação acessar AWS APIs (SSM/S3) via ecsTaskRole
  egress {
    description = "Saída HTTPS para AWS APIs (ECR, CloudWatch, SSM, S3)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-tasks-sg"
  }
}
