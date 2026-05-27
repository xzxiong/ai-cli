---
name: deploy-moi
description: "Automate or troubleshoot local MatrixFlow/MOI deployment: Docker infrastructure, MySQL/MatrixOne, Redis, MinIO, RabbitMQ, backend services, frontend, apiserver/job-consumer restart, and health verification. Use when the user asks to deploy locally, start services, initialize MOI/MatrixFlow, check local service status, or troubleshoot startup failures."
---

# Deploy MOI

Bring up or diagnose a local MatrixFlow/MOI development environment.

## Workflow

1. Run environment diagnostics: required tools, repo location, current containers, ports, and service state.
2. Start infrastructure with Docker/volumes: MatrixOne/MySQL, Redis, MinIO, RabbitMQ, UNO.
3. Initialize schemas and message topics.
4. Build and start backend services in dependency order.
5. Restart `apiserver` and `job-consumer` explicitly when first startup fails due to Poetry/env delays.
6. Build/start frontend when requested.
7. Verify health with service status, ports, logs, and end-to-end checks.

## Resources

- Use `scripts/deploy.sh` for the deterministic deployment path when it fits the request.
- Read `references/commands.md` for command details.
- Read `references/apiserver-jobconsumer.md` when those services fail or restart loops appear.

## Defaults

- MatrixFlow repo: `~/go/src/github.com/matrixorigin/matrixflow`.
- Keep diagnostics idempotent; report existing state before changing it.
