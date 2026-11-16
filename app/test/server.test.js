const { describe, it, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { criarServidor } = require("../src/server");

describe("API de referência multi-ambiente no Amazon ECS", () => {
  let servidor;
  let baseUrl;

  before(async () => {
    process.env.APP_ENV = "staging";
    process.env.IMAGE_TAG = "staging-a1b2c3d";
    process.env.GIT_SHA = "a1b2c3d";

    servidor = criarServidor();
    await new Promise((resolve) => {
      servidor.listen(0, "127.0.0.1", () => {
        const { port } = servidor.address();
        baseUrl = `http://127.0.0.1:${port}`;
        resolve();
      });
    });
  });

  after(async () => {
    await new Promise((resolve) => servidor.close(resolve));
  });

  it("deve responder HTTP 200 no endpoint /health com metadados do container", async () => {
    const resposta = await fetch(`${baseUrl}/health`);
    assert.equal(resposta.status, 200);

    const corpo = await resposta.json();
    assert.equal(corpo.status, "healthy");
    assert.equal(corpo.ambiente, "staging");
    assert.equal(corpo.imagemTag, "staging-a1b2c3d");
    assert.equal(typeof corpo.uptimeSegundos, "number");
  });

  it("deve responder HTTP 200 no endpoint /info descrevendo ambiente efêmero e IAM Roles", async () => {
    const resposta = await fetch(`${baseUrl}/info`);
    assert.equal(resposta.status, 200);

    const corpo = await resposta.json();
    assert.equal(corpo.servico, "aws-ecs-ephemeral-environments");
    assert.equal(corpo.ambiente, "staging");
    assert.equal(corpo.tipoAmbiente, "efemero");
    assert.equal(corpo.commitSha, "a1b2c3d");
    assert.ok(corpo.identidadesIam.ecsTaskExecutionRole);
    assert.equal(corpo.identidadesIam.ecsTaskRole.ecsTaskRoleInjetada, false);
  });

  it("deve responder HTTP 404 para rotas inexistentes", async () => {
    const resposta = await fetch(`${baseUrl}/rota-invalida`);
    assert.equal(resposta.status, 404);

    const corpo = await resposta.json();
    assert.equal(corpo.erro, "Rota não encontrada");
    assert.ok(Array.isArray(corpo.rotasDisponiveis));
  });
});

