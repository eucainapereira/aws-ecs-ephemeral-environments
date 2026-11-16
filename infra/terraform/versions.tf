terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  # Exemplo de backend remoto recomendado para produção (descomente ao provisionar na AWS)
  # backend "s3" {
  #   bucket         = "seu-bucket-terraform-state"
  #   key            = "portfolio-ecs-ambientes/terraform.tfstate"
  #   region         = "us-east-2"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Projeto     = var.project_name
      Ambiente    = var.environment
      Gerenciado  = "Terraform"
      Repositorio = var.github_repo
    }
  }
}

