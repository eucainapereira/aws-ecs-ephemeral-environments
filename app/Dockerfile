# syntax=docker/dockerfile:1

# Estágio 1: Validação de testes e preparação dos artefatos da aplicação
FROM node:20-alpine AS test-stage

WORKDIR /app

COPY package.json ./
COPY src ./src
COPY test ./test

# Executa os testes unitários nativos durante o build para garantir integridade antes do push ao ECR
RUN npm test

# Estágio 2: Imagem final enxuta e segura para execução no Amazon ECS Fargate
FROM node:20-alpine AS runtime

ARG IMAGE_TAG=dev-local
ARG GIT_SHA=local

LABEL org.opencontainers.image.title="portfolio-ecs-multi-env" \
      org.opencontainers.image.description="Aplicação containerizada de referência para ambientes dev, staging e prod no Amazon ECS" \
      org.opencontainers.image.revision="${GIT_SHA}"

WORKDIR /app

# Cria usuário sem privilégios de root seguindo boas práticas de segurança em containers
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=test-stage --chown=appuser:appgroup /app/package.json ./package.json
COPY --from=test-stage --chown=appuser:appgroup /app/src ./src

ENV NODE_ENV=production \
    PORT=3000 \
    IMAGE_TAG=${IMAGE_TAG} \
    GIT_SHA=${GIT_SHA}

USER appuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/health || exit 1

CMD ["node", "src/server.js"]

