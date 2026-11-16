output "ecr_repository_url" {
  description = "URL do repositório imutável no Amazon ECR para push/promoção de imagens."
  value       = local.ecr_repository_url
  sensitive   = true
}

output "cicd_pipeline_role_arn" {
  description = "ARN da Identidade do Pipeline (CI/CD) usada pelo GitHub Actions via OIDC."
  value       = var.create_shared_resources ? aws_iam_role.cicd_pipeline_role[0].arn : null
  sensitive   = true
}

output "ecs_task_execution_role_arn" {
  description = "ARN da ecsTaskExecutionRole (Control Plane / Agente do ECS)."
  value       = aws_iam_role.ecs_task_execution_role.arn
  sensitive   = true
}

output "ecs_task_role_arn" {
  description = "ARN da ecsTaskRole (Data Plane / Código da Aplicação em Runtime)."
  value       = aws_iam_role.ecs_task_role.arn
  sensitive   = true
}

output "ecs_cluster_name" {
  description = "Nome do cluster ECS do ambiente."
  value       = aws_ecs_cluster.env.name
}

output "ecs_service_name" {
  description = "Nome do ECS Service do ambiente."
  value       = aws_ecs_service.app.name
}

output "cloudwatch_log_group_name" {
  description = "Nome do grupo de logs persistente no CloudWatch Logs."
  value       = aws_cloudwatch_log_group.ecs_app.name
}

output "ecs_subnet_ids" {
  description = "IDs das subnets configuradas para as tasks Fargate do ambiente."
  value       = aws_subnet.app[*].id
}

output "ecs_security_group_id" {
  description = "ID do Security Group aplicado às tasks Fargate do ambiente."
  value       = aws_security_group.ecs_tasks.id
}

