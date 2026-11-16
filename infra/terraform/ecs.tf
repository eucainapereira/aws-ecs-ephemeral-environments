# -----------------------------------------------------------------------------
# Amazon ECS (Cluster, Task Definition e Service)
# -----------------------------------------------------------------------------
# - Ambientes `dev` e `staging` utilizam FARGATE_SPOT e iniciam com desired_count = 0.
#   O pipeline CI/CD escala para 1 durante a janela de testes e retorna para 0 ao final.
# - Ambiente `prod` utiliza FARGATE padrão com desired_count >= 2 de forma permanente.
# -----------------------------------------------------------------------------

resource "aws_ecs_cluster" "env" {
  name = "${var.project_name}-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name         = "${var.project_name}-${var.environment}-cluster"
    TipoAmbiente = var.is_ephemeral ? "efemero" : "permanente"
  }
}

resource "aws_ecs_cluster_capacity_providers" "env" {
  cluster_name = aws_ecs_cluster.env.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = var.is_ephemeral ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
    base              = 1
  }
}

# Task Definition inicial (revisões subsequentes apontando para tags imutáveis
# do ECR como `app:dev-a1b2c3d` são registradas diretamente pelo pipeline CI/CD)
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-${var.environment}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)

  # Separação explícita entre Control Plane (Execution) e Data Plane (Task)
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${local.ecr_repository_url}:${var.initial_image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          hostPort      = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "APP_ENV", value = var.environment },
        { name = "PORT", value = tostring(var.container_port) },
        { name = "IMAGE_TAG", value = var.initial_image_tag },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "SSM_PARAMETER_PREFIX", value = "/${var.project_name}/${var.environment}/" }
      ]

      # Driver awslogs: o ECS Agent usa a ecsTaskExecutionRole para enviar
      # stdout/stderr continuamente ao CloudWatch Logs
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs-${var.environment}"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://127.0.0.1:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }
    }
  ])

  tags = {
    Name = "${var.project_name}-${var.environment}-taskdef"
  }
}

resource "aws_ecs_service" "app" {
  name                               = "${var.project_name}-${var.environment}-service"
  cluster                            = aws_ecs_cluster.env.id
  task_definition                    = aws_ecs_task_definition.app.arn
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = var.is_ephemeral ? 0 : 100
  deployment_maximum_percent         = 200
  enable_execute_command             = false

  capacity_provider_strategy {
    capacity_provider = var.is_ephemeral ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = aws_subnet.app[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  # Permite que o pipeline CI/CD atualize a revisão da Task Definition e
  # controle a subida/encerramento (desired_count) sem conflito com o Terraform
  lifecycle {
    ignore_changes = [
      task_definition,
      desired_count
    ]
  }

  tags = {
    Name         = "${var.project_name}-${var.environment}-service"
    TipoAmbiente = var.is_ephemeral ? "efemero" : "permanente"
  }
}

