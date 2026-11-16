# -----------------------------------------------------------------------------
# Amazon ECR — Registro Imutável de Imagens Docker
# -----------------------------------------------------------------------------
# A imutabilidade de tags (`IMMUTABLE`) impede que uma tag já publicada
# (ex.: `app:dev-a1b2c3d`) seja sobrescrita. Isso garante que exatamente a mesma
# imagem validada em `dev` e `staging` seja promovida para `prod`.
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  count = var.create_shared_resources ? 1 : 0

  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = var.ecr_repository_name
    Imutavel    = "true"
    Escopo      = "compartilhado-dev-staging-prod"
    Description = "Registro central de imagens imutáveis usadas na promoção entre dev, staging e prod"
  }
}

# Política de ciclo de vida do ECR:
# Mesmo após o encerramento dos ambientes efêmeros (dev e staging), as imagens
# permanecem no ECR para auditoria, rollback rápido e promoção para produção.
# Apenas imagens antigas acima do limite de retenção ou sem tag são expiradas.
resource "aws_ecr_lifecycle_policy" "app" {
  count = var.create_shared_resources ? 1 : 0

  repository = aws_ecr_repository.app[0].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove camadas intermediárias sem tag após 7 dias"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Mantém as 50 imagens imutáveis mais recentes (ex.: dev-<sha>) para auditoria e rollback"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["dev-", "rc-", "prod-"]
          countType     = "imageCountMoreThan"
          countNumber   = 50
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Referência de leitura caso o stack de ambiente rode separado do stack compartilhado
data "aws_ecr_repository" "existing" {
  count = var.create_shared_resources ? 0 : 1
  name  = var.ecr_repository_name
}

locals {
  ecr_repository_arn = var.create_shared_resources ? aws_ecr_repository.app[0].arn : data.aws_ecr_repository.existing[0].arn
  ecr_repository_url = var.create_shared_resources ? aws_ecr_repository.app[0].repository_url : data.aws_ecr_repository.existing[0].repository_url
}

