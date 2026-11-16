# -----------------------------------------------------------------------------
# Amazon CloudWatch Logs — Retenção Persistente de Logs por Ambiente
# -----------------------------------------------------------------------------
# Mesmo após o pipeline CI/CD encerrar o Service/Task dos ambientes efêmeros
# (`dev` e `staging`), os grupos de log permanecem intactos (`skip_destroy = true`)
# preservando o histórico completo de `stdout` e `stderr` para auditoria.
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ecs_app" {
  name              = "/ecs/${var.project_name}/${var.environment}"
  retention_in_days = var.log_retention_days
  skip_destroy      = true

  tags = {
    Name        = "/ecs/${var.project_name}/${var.environment}"
    Persistencia = "mantido-apos-teardown"
  }
}
