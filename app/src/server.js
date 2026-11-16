const http = require("node:http");

/**
 * Emite logs estruturados em JSON para stdout ou stderr.
 *
 * No Amazon ECS, o agente do ECS (control plane) utiliza a
 * `ecsTaskExecutionRole` para coletar stdout/stderr do container
 * e encaminhar ao grupo de logs correspondente no CloudWatch Logs.
 * Mesmo quando os ambientes efêmeros (dev/staging) são encerrados,
 * esses logs permanecem armazenados no CloudWatch para auditoria.
 */
function registrarLog(nivel, mensagem, metadados = {}) {
  const registro = {
    timestamp: new Date().toISOString(),
    nivel,
    mensagem,
    ambiente: process.env.APP_ENV || "local",
    imagemTag: process.env.IMAGE_TAG || "dev-local",
    ...metadados
  };

  const linha = JSON.stringify(registro);
  if (nivel === "ERROR" || nivel === "WARN") {
    console.error(linha);
    return;
  }
  console.log(linha);
}

/**
 * Responde uma requisição HTTP com payload JSON padronizado.
 */
function responderJson(res, statusCode, payload) {
  const corpo = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(corpo)
  });
  res.end(corpo);
}

/**
 * Lê de forma segura os metadados das credenciais injetadas pelo ECS
 * para a `ecsTaskRole` (data plane / tempo de execução).
 * Nunca expõe segredos ou tokens temporários na resposta HTTP.
 */
function obterStatusTaskRole() {
  const uriRelativa = process.env.AWS_CONTAINER_CREDENTIALS_RELATIVE_URI;
  const uriCompleta = process.env.AWS_CONTAINER_CREDENTIALS_FULL_URI;
  const taskRoleAtiva = Boolean(uriRelativa || uriCompleta);

  return {
    ecsTaskRoleInjetada: taskRoleAtiva,
    regiaoAws: process.env.AWS_REGION || "us-east-1",
    bucketRelatoriosConfigurado: Boolean(process.env.APP_ARTIFACTS_BUCKET),
    prefixoParametrosSsm: process.env.SSM_PARAMETER_PREFIX || "nao-configurado"
  };
}

/**
 * Cria o servidor HTTP da aplicação de referência.
 */
function criarServidor() {
  return http.createServer((req, res) => {
    const caminho = (req.url || "/").split("?")[0];
    const metodo = req.method || "GET";

    if (metodo === "GET" && caminho === "/health") {
      responderJson(res, 200, {
        status: "healthy",
        ambiente: process.env.APP_ENV || "local",
        imagemTag: process.env.IMAGE_TAG || "dev-local",
        uptimeSegundos: Math.floor(process.uptime()),
        timestamp: new Date().toISOString()
      });
      return;
    }

    if (metodo === "GET" && (caminho === "/" || caminho === "/info")) {
      const ambiente = process.env.APP_ENV || "local";
      const info = {
        servico: "portfolio-ecs-multi-env",
        ambiente,
        tipoAmbiente: ambiente === "prod" ? "permanente" : "efemero",
        imagemTag: process.env.IMAGE_TAG || "dev-local",
        commitSha: process.env.GIT_SHA || "local",
        identidadesIam: {
          pipelineCiCd: "Cria/atualiza imagem imutável no ECR e gerencia ciclo de vida no ECS",
          ecsTaskExecutionRole: "Usada pelo agente do ECS para puxar imagem do ECR e enviar logs ao CloudWatch",
          ecsTaskRole: obterStatusTaskRole()
        },
        timestamp: new Date().toISOString()
      };

      registrarLog("INFO", "Consulta de informações do serviço atendida", {
        metodo,
        caminho
      });

      responderJson(res, 200, info);
      return;
    }

    if (metodo === "GET" && caminho === "/simular-erro") {
      registrarLog("ERROR", "Erro simulado registrado em stderr para validação de CloudWatch Logs", {
        metodo,
        caminho
      });
      responderJson(res, 500, {
        erro: "Erro simulado para teste de observabilidade no CloudWatch Logs"
      });
      return;
    }

    registrarLog("WARN", "Rota não encontrada", { metodo, caminho });
    responderJson(res, 404, {
      erro: "Rota não encontrada",
      rotasDisponiveis: ["/health", "/info", "/simular-erro"]
    });
  });
}

if (require.main === module) {
  const porta = Number(process.env.PORT || 3000);
  const servidor = criarServidor();

  servidor.listen(porta, "0.0.0.0", () => {
    registrarLog("INFO", "Aplicação iniciada e pronta para receber tráfego", { porta });
  });

  // Encerramento gracioso quando o ECS envia SIGTERM ao parar tasks efêmeras ou durante rolling update
  const encerrarGraciosamente = (sinal) => {
    registrarLog("INFO", "Sinal de encerramento recebido; finalizando conexões ativas", { sinal });
    servidor.close(() => {
      registrarLog("INFO", "Servidor HTTP encerrado com sucesso");
      process.exit(0);
    });
  };

  process.on("SIGTERM", () => encerrarGraciosamente("SIGTERM"));
  process.on("SIGINT", () => encerrarGraciosamente("SIGINT"));
}

module.exports = {
  criarServidor,
  obterStatusTaskRole,
  registrarLog
};
