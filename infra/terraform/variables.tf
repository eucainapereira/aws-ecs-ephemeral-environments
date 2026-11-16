variable "aws_region" {
  description = "Região da AWS onde os recursos serão provisionados."
  type        = string
  default     = "us-east-2"
}

variable "aws_account_id" {
  description = "ID opcional da conta AWS mantido oculto como sensível; quando nulo, é resolvido em tempo de execução."
  type        = string
  default     = null
  sensitive   = true
}

variable "project_name" {
  description = "Nome base do projeto usado para prefixar recursos e tags."
  type        = string
  default     = "portfolio-app"
}

variable "ecr_repository_name" {
  description = "Nome do repositório no Amazon ECR (ex.: gera imagens no formato app:dev-a1b2c3d)."
  type        = string
  default     = "app"
}

variable "environment" {
  description = "Ambiente alvo da implantação: dev, staging (efêmeros) ou prod (permanente)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "O valor de environment deve ser 'dev', 'staging' ou 'prod'."
  }
}

variable "is_ephemeral" {
  description = "Indica se o ambiente é efêmero (dev/staging) com ciclo de vida sob demanda via CI/CD."
  type        = bool
  default     = true
}

variable "github_repo" {
  description = "Repositório GitHub do projeto (formato: usuario/repo)."
  type        = string
  default     = "eucainapereira/ambientes-ecs-ecr-cicd"
}

variable "create_shared_resources" {
  description = "Define se este workspace cria os recursos compartilhados entre ambientes (ECR e Usuário IAM do Pipeline CI/CD)."
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC do ambiente."
  type        = string
  default     = "10.20.0.0/16"
}

variable "container_port" {
  description = "Porta HTTP exposta pelo container da aplicação."
  type        = number
  default     = 3000
}

variable "task_cpu" {
  description = "Unidades de CPU da Task Fargate (ex.: 256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memória em MiB da Task Fargate (ex.: 512 MiB)."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Quantidade desejada inicial de tasks no ECS Service (0 para efêmeros até o CI/CD iniciar; >= 2 para prod)."
  type        = number
  default     = 0
}

variable "initial_image_tag" {
  description = "Tag inicial usada no provisionamento Terraform antes da primeira promoção via pipeline CI/CD."
  type        = string
  default     = "bootstrap-v1"
}

variable "log_retention_days" {
  description = "Dias de retenção dos logs no CloudWatch Logs mesmo após o encerramento de dev/staging."
  type        = number
  default     = 30
}

variable "app_artifacts_bucket_arn" {
  description = "ARN de um bucket S3 opcional que a aplicação acessa em runtime utilizando a ecsTaskRole."
  type        = string
  default     = "arn:aws:s3:::portfolio-app-runtime-artifacts"
}

