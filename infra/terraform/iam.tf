# -----------------------------------------------------------------------------
# Arquitetura de 3 Identidades IAM para Amazon ECS e CI/CD
# -----------------------------------------------------------------------------
# Este arquivo define explicitamente a separação de responsabilidades entre:
#   1. Identidade do Pipeline (CI/CD)       -> Build, Push no ECR e Ciclo de Vida no ECS
#   2. ECS Task Execution Role             -> Agente do ECS (Control Plane): pull ECR + logs CloudWatch
#   3. ECS Task Role                       -> Aplicação em Runtime (Data Plane): acesso AWS pelo código
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  # Mantém o ID da conta AWS marcado como sensível para ocultá-lo nas saídas de plan/apply
  aws_account_id = sensitive(coalesce(var.aws_account_id, data.aws_caller_identity.current.account_id))
}

# =============================================================================
# 1. IDENTIDADE DO PIPELINE (CI/CD) — Usuário IAM com Chaves Estáticas
# =============================================================================
# Responsabilidade:
#   - Autenticar no GitHub Actions utilizando chaves estáticas (AWS_ACCESS_KEY_ID e AWS_SECRET_ACCESS_KEY)
#   - Fazer build da imagem Docker e enviar com tag imutável para o ECR
#   - Registrar novas revisões da Task Definition no Amazon ECS
#   - Criar/atualizar Services/Tasks em dev, staging e prod
#   - Destruir/encerrar Services/Tasks de dev e staging ao término dos testes
# =============================================================================

resource "aws_iam_user" "cicd_pipeline_user" {
  count = var.create_shared_resources ? 1 : 0

  name = "${var.project_name}-cicd-pipeline-user"

  tags = {
    PapelArquitetural = "Pipeline-CICD"
  }
}

resource "aws_iam_access_key" "cicd_pipeline_keys" {
  count = var.create_shared_resources ? 1 : 0

  user = aws_iam_user.cicd_pipeline_user[0].name
}

data "aws_iam_policy_document" "cicd_permissions" {
  count = var.create_shared_resources ? 1 : 0

  # Token de autenticação global do ECR
  statement {
    sid       = "AutenticacaoGlobalECR"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Push e verificação de imagens imutáveis apenas no repositório do projeto
  statement {
    sid    = "PushEVerificacaoImagemECR"
    effect = "Allow"
    actions = [
      "ecr:DescribeRepositories",
      "ecr:CreateRepository",
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:ListImages"
    ]
    resources = [local.ecr_repository_arn]
  }

  # Registro de Task Definitions e gerenciamento de Services/Tasks em dev, staging e prod
  statement {
    sid    = "GerenciarCicloDeVidaECS"
    effect = "Allow"
    actions = [
      "ecs:CreateCluster",
      "ecs:DescribeClusters",
      "ecs:PutClusterCapacityProviders",
      "ecs:RegisterTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:CreateService",
      "ecs:UpdateService",
      "ecs:DeleteService",
      "ecs:DescribeServices",
      "ecs:RunTask",
      "ecs:StopTask",
      "ecs:DescribeTasks",
      "ecs:ListTasks",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:CreateSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress"
    ]
    resources = ["*"]
  }

  # Criação e leitura de logs no CloudWatch durante a validação automatizada dos ambientes
  statement {
    sid    = "ConsultarLogsPosTesteCloudWatch"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
      "logs:FilterLogEvents"
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${local.aws_account_id}:log-group:/ecs/${var.project_name}/*"
    ]
  }

  # Consulta dos ARNs das roles ECS pelo pipeline sem expor ou depender do ID da conta no código
  statement {
    sid     = "PermitirConsultaRolesECS"
    effect  = "Allow"
    actions = ["iam:GetRole"]
    resources = [
      "arn:aws:iam::${local.aws_account_id}:role/${var.project_name}-*-ecsTaskExecutionRole",
      "arn:aws:iam::${local.aws_account_id}:role/${var.project_name}-*-ecsTaskRole",
      "arn:aws:iam::${local.aws_account_id}:role/ecsTaskExecutionRole",
      "arn:aws:iam::${local.aws_account_id}:role/ecsTaskRole"
    ]
  }

  # iam:PassRole estritamente limitado às roles do ECS usadas pelas tasks (Execution Role e Task Role)
  statement {
    sid     = "PermitirPassRoleSomenteParaRolesECS"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      "arn:aws:iam::${local.aws_account_id}:role/${var.project_name}-*-ecsTaskExecutionRole",
      "arn:aws:iam::${local.aws_account_id}:role/${var.project_name}-*-ecsTaskRole",
      "arn:aws:iam::${local.aws_account_id}:role/ecsTaskExecutionRole",
      "arn:aws:iam::${local.aws_account_id}:role/ecsTaskRole"
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_user_policy" "cicd_pipeline_inline" {
  count = var.create_shared_resources ? 1 : 0

  name   = "${var.project_name}-cicd-pipeline-policy"
  user   = aws_iam_user.cicd_pipeline_user[0].name
  policy = data.aws_iam_policy_document.cicd_permissions[0].json
}


# =============================================================================
# TRUST POLICY COMPARTILHADA PARA ROLES DE TASK DO AMAZON ECS
# =============================================================================
data "aws_iam_policy_document" "ecs_tasks_trust_policy" {
  statement {
    sid     = "PermitirAssuncaoPeloServicoEcsTasks"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    # Proteção contra Confused Deputy: restringe à conta e região atuais
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.aws_account_id]
    }
  }
}


# =============================================================================
# 2. ECS TASK EXECUTION ROLE (ecsTaskExecutionRole) — Control Plane / Agente ECS
# =============================================================================
# Responsabilidade:
#   - Usada EXCLUSIVAMENTE pelo agente do ECS / infraestrutura Fargate antes e
#     durante o ciclo de vida do container:
#       a) Baixar a imagem privada do Amazon ECR (pull)
#       b) Enviar stdout e stderr do container para o Amazon CloudWatch Logs
#   - O código da aplicação NÃO herda essas permissões.
# =============================================================================

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.project_name}-${var.environment}-ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust_policy.json
  description        = "ECS Task Execution Role (${var.environment}): usada pelo agente do ECS para puxar imagens do ECR e enviar logs ao CloudWatch."

  tags = {
    PapelArquitetural = "ECS-ControlPlane-ExecutionRole"
  }
}

data "aws_iam_policy_document" "ecs_task_execution_permissions" {
  statement {
    sid       = "EcrAuthTokenParaPull"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPullImagemPrivada"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = [local.ecr_repository_arn]
  }

  statement {
    sid    = "CloudWatchLogsEnvioStdoutStderr"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = [
      "${aws_cloudwatch_log_group.ecs_app.arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "ecs_task_execution_inline" {
  name   = "${var.project_name}-${var.environment}-ecsTaskExecutionPolicy"
  role   = aws_iam_role.ecs_task_execution_role.id
  policy = data.aws_iam_policy_document.ecs_task_execution_permissions.json
}


# =============================================================================
# 3. ECS TASK ROLE (ecsTaskRole) — Data Plane / Código da Aplicação
# =============================================================================
# Responsabilidade:
#   - Usada EXCLUSIVAMENTE pelo código da aplicação em tempo de execução dentro
#     do container (via AWS SDK utilizando as credenciais da role injetadas
#     em AWS_CONTAINER_CREDENTIALS_RELATIVE_URI).
#   - Concede apenas acesso de negócio ao respectivo ambiente (ex.: parâmetros
#     no SSM Parameter Store e prefixo S3 do ambiente), sem permissões de ECR
#     ou de gerenciamento do ECS.
# =============================================================================

resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.project_name}-${var.environment}-ecsTaskRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust_policy.json
  description        = "ECS Task Role (${var.environment}): usada pelo código da aplicação dentro do container para acessar recursos da AWS em runtime."

  tags = {
    PapelArquitetural = "ECS-DataPlane-ApplicationTaskRole"
  }
}

data "aws_iam_policy_document" "ecs_task_runtime_permissions" {
  statement {
    sid    = "LeituraParametrosRuntimeDoAmbiente"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath"
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${local.aws_account_id}:parameter/${var.project_name}/${var.environment}/*"
    ]
  }

  statement {
    sid    = "AcessoPrefixoS3DaAplicacaoPorAmbiente"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      var.app_artifacts_bucket_arn,
      "${var.app_artifacts_bucket_arn}/${var.environment}/*"
    ]
  }
}

resource "aws_iam_role_policy" "ecs_task_runtime_inline" {
  name   = "${var.project_name}-${var.environment}-ecsTaskRuntimePolicy"
  role   = aws_iam_role.ecs_task_role.id
  policy = data.aws_iam_policy_document.ecs_task_runtime_permissions.json
}

