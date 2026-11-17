# Fluxo CI/CD, Ambientes Efêmeros e Imutabilidade no ECR

Este documento detalha o ciclo de vida das entregas entre **dev**, **staging** e **prod**, explicando como a arquitetura concilia **economia de infraestrutura (FinOps)**, **rastreabilidade** e **confiabilidade no deploy**.

---

## Ciclo de Vida por Branch (`dev`, `staging` e `main`)

```mermaid
flowchart TD
    A["Push na branch dev"] --> B["Build + Push no ECR (IMMUTABLE) + Sobe ECS DEV (desired_count = 1)"]
    B --> C["Ambiente DEV fica ativo com Link Público (http://IP:3000)"]
    C --> D["Push/Merge na branch staging"]
    D --> E["Push no ECR + Sobe ECS STAGING (desired_count = 1)"]
    E --> F["Ambiente STAGING fica ativo com Link Público (http://IP:3000)"]
    F --> G["Push/Merge na branch main"]
    G --> H["Atualiza Service Permanente de PROD + Gera Link Público de PROD"]
    H --> I["Teardown Automático: Desliga DEV e STAGING (desired_count = 0)"]
    I --> J["Imagens permanecem no ECR e Logs permanecem no CloudWatch Logs"]
```

---

## Comparativo entre Ambientes Efêmeros e Permanente

| Característica | `dev` (Branch `dev`) | `staging` (Branch `staging`) | `prod` (Branch `main`) |
| :--- | :--- | :--- | :--- |
| **Gatilho de Subida** | `git push origin dev` | `git push origin staging` | `git push origin main` |
| **Estado Após o Deploy da Branch** | `desired_count = 1` (ativo com link público para testes) | `desired_count = 1` (ativo com link público para homologação) | `desired_count >= 1` (permanente em produção) |
| **Grupo de Logs no CloudWatch** | `/ecs/aws-ecs-ephemeral-environments/dev` (14 dias) | `/ecs/aws-ecs-ephemeral-environments/staging` (30 dias) | `/ecs/aws-ecs-ephemeral-environments/prod` (90 dias) |
| **Quando é Desligado (`desired_count = 0`)** | Automaticamente quando a branch `main` faz deploy em produção | Automaticamente quando a branch `main` faz deploy em produção | Nunca (ambiente permanente) |

---

## Garantias de Persistência Pós-Teardown

Mesmo quando o pipeline encerra os ambientes de `dev` e `staging` ao final dos testes:

1. **A Imagem Continua no Amazon ECR**:
   - Configurada com `image_tag_mutability = "IMMUTABLE"` em `infra/terraform/ecr.tf`.
   - Ninguém consegue sobrescrever a tag `dev-a1b2c3d`.
   - A política de ciclo de vida (`aws_ecr_lifecycle_policy`) preserva as 50 versões imutáveis mais recentes para rastreabilidade, diagnóstico e rollback imediato.

2. **Os Logs Continuam no Amazon CloudWatch Logs**:
   - Configurados em `infra/terraform/logs.tf` com `skip_destroy = true`.
   - Como o agente do ECS envia continuamente `stdout` e `stderr` para o CloudWatch Logs por meio da `ecsTaskExecutionRole` enquanto a task está rodando, o encerramento da task (`desired-count 0`) **não apaga** os logs gerados durante os testes.
   - Engenheiros conseguem auditar falhas em execuções efêmeras mesmo horas ou dias depois de as tasks terem sido destruídas.

