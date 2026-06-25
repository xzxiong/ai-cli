---
name: deploy-moi
description: "Automate or troubleshoot local MatrixFlow/MOI deployment: Docker infrastructure, MySQL/MatrixOne, Redis, MinIO, RabbitMQ, backend services, frontend, apiserver/job-consumer restart, and health verification. Use when the user asks to deploy locally, start services, initialize MOI/MatrixFlow, check local service status, or troubleshoot startup failures."
---

# Deploy MOI

Bring up or diagnose a local MatrixFlow/MOI development environment.

## Workflow

Use an idempotent six-stage flow:

1. Diagnostics: required tools, repo location, Docker state, ports, existing processes, and `make status`.
2. Infrastructure: start Docker volumes/services for MatrixOne/MySQL, Redis, MinIO, RabbitMQ, UNO; wait for DB readiness.
3. Initialization: load schemas and initialize message topics/queues.
4. Backend: build/start connector-rpc, augmentation, workflow-scheduler, catalog-service, license-service, local-service, mock-service, openxml-service, apiserver, and job-consumer as applicable.
5. Frontend: install/build/start the Vite frontend only when requested.
6. Verification: auth login, API key, service status, logs, buckets, and optional CLI document pipeline test.

## Critical Restart Path

`apiserver` and `job-consumer` often fail on first startup because Poetry/env initialization lags. If they are stopped after `make start`, restart them explicitly:

```bash
sh start-apiserver.sh
sh start-jobconsumer.sh
make status
```

If scripts are missing, use the repo Makefile targets and inspect `tmp/apiserver.log` and `tmp/job-consumer.log`.

## Resources

- Use `scripts/deploy.sh` for the deterministic deployment path when it fits the request.
- Read `references/commands.md` for command details.
- Read `references/apiserver-jobconsumer.md` when those services fail or restart loops appear.

## Defaults

- MatrixFlow repo: `~/go/src/github.com/matrixorigin/matrixflow`.
- Keep diagnostics idempotent; report existing state before changing it.
- Common auth check: POST `http://127.0.0.1:8000/auth/login` for `local-moi-account`.
