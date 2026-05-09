---
name: deploy-moi
description: Automate local MatrixFlow/MOI deployment (6 stages): Docker containers, MySQL, RabbitMQ, backend services (apiserver/job-consumer), frontend, and health verification. Also known as "local deploy moi", "deploy local moi", or "setup moi locally". ALWAYS use this skill when user mentions any of: deploy locally, start the services, init the environment, setup moi/matrixflow locally, check service status, troubleshoot startup failures, verify service health, test end-to-end, or similar for MatrixFlow/MOI/Catalog projects. Works cross-environment (macOS/Linux/Docker).
compatibility: Requires bash, docker-compose, mysql, curl, poetry, pnpm; assumes MatrixFlow repo at ~/go/src/github.com/matrixorigin/matrixflow
---

# Deploy MOI: Local Development Setup

This skill automates the complete local development environment setup for MatrixFlow with 6 idempotent stages.

## Core Workflow: 6-Stage Pipeline

The deployment follows this sequence (each stage is idempotent):

### Stage 1: Environment Diagnostics
- Check Docker and required tools (docker-compose, mysql, python, go, dotnet)
- Validate repo structure and Makefile
- Detect existing containers/processes
- Report current state without making changes

### Stage 2: Infrastructure Setup (Docker/Volumes)
- Pull latest container images
- Create persistent volumes (mo_data, redis_data, minio_storage, rmq_data)
- Start infrastructure: MySQL/MatrixOne, Redis, MinIO, RabbitMQ, UNO server
- Wait for health checks to pass

### Stage 3: Database & Message Queue Initialization
- Load SQL schemas (account, luke, byoa, mocloud_meta, account-local-moi, tpl_init, nl2sql, webhook)
- Create RocketMQ topics (task, connector_job, event, notify_job, load_completion, connect_rpc_event_alert)
- Verify MySQL connectivity
- Confirm MQ topics are created

### Stage 4: Build & Start Backend Services
- Build connector-rpc (Go + tRPC)
- Start all backend services in order:
  - connector-rpc, augmentation, workflow-scheduler, catalog-service
  - license-service, local-service, mock-service, openxml-service
- Log each service start to `tmp/service-name.log`
- **Note**: apiserver and job-consumer often require retry (see Stage 4b below)

### Stage 4b: Restart apiserver & job-consumer (if needed)

These services often fail on first attempt due to poetry initialization delays. This stage explicitly restarts them with proper environment setup.

**What apiserver does:**
- Loads env vars from `optools/matrixflow/.env`
- Sets PYTHONPATH to include workflow_be modules
- Runs `poetry install` to ensure dependencies are ready
- Starts Python process: `poetry run python3 byoa/main.py`
- Logs to `tmp/apiserver.log`
- Port: 8000

**What job-consumer does:**
- Loads env vars from `optools/matrixflow/.env`
- Sets PYTHONPATH to include workflow_be modules
- **Enables metrics**: `JOB_CONSUMER_METRICS_ENABLED=true`
- Starts Python process: `poetry run python3 byoa/job_consumer.py`
- Logs to `tmp/job-consumer.log`
- Runs as background daemon

**Retry sequence:**
```bash
# Option 1: Direct commands (environment-aware)
cd ~/go/src/github.com/matrixorigin/matrixflow
sh start-apiserver.sh      # Calls: make start-apiserver DYLD_LIBRARY_PATH=${DYLD_LIBRARY_PATH}
sh start-jobconsumer.sh    # Calls: poetry run python3 byoa/job_consumer.py with metrics enabled

# Option 2: Make targets (if scripts unavailable)
cd ~/go/src/github.com/matrixorigin/matrixflow
make start-apiserver
make start-job-consumer    # Alternative: may vary by Makefile version
```

- Wait 5 seconds for services to initialize
- Verify both services appear in `make status` with running PIDs

### Stage 5: Build & Start Frontend
- Checkout/update moi-frontend repo
- Install pnpm dependencies (suppress deprecation warnings)
- Prebuild/build frontend assets
- Start Vite dev server on port 5173
- Open browser to http://localhost:5173/local-moi-account/dev

### Stage 6: Verification & Testing
- Health check: Call GET /auth/login (apiserver)
- Auth test: POST /auth/login with test credentials → extract Access-Token + Refresh-Token
- API key test: GET /user/me/api-key with token → extract new API key
- CLI setup: Update genai-cli.yaml with new API key
- CLI test: Run genai-cli pipeline on a sample document
- MinIO test: Verify bucket structure with mc
- Show final service status dashboard

## Quick Start

**Full deployment (Stages 1→6):**
```bash
# Stages 2-3: Infrastructure & DB/MQ init
make start-env && make wait-mo && make init-env

# Stage 4: Start all services
make start

# Stage 4b: Restart apiserver & job-consumer (often needed)
sh start-apiserver.sh && sh start-jobconsumer.sh && make status

# Stage 6: Verify everything works
curl -X POST http://127.0.0.1:8000/auth/login \
  -H 'Content-Type: application/json' \
  --data-raw '{"account_name":"local-moi-account","username":"admin:accountadmin","password":"123456","type":"workspace"}'
```

**Checkpoint locations:**
- After `make start-env` → Containers running: `docker ps | grep matrixflow`
- After `make init-env` → DB ready: `make status` shows databases initialized
- After `make start` → Most services up: `make status` (apiserver/job-consumer may be STOPPED)
- After `sh start-apiserver.sh && sh start-jobconsumer.sh` → Full deployment: `make status` shows all GREEN

**User interaction points:**
- If MySQL isn't ready, retry `make wait-mo` before `make init-env`
- If apiserver/job-consumer show STOPPED after `make start`, **run Stage 4b**: `sh start-apiserver.sh && sh start-jobconsumer.sh`
- If frontend build fails, clear node_modules and retry pnpm install
- Check logs: `tail -f tmp/apiserver.log` or `tail -f tmp/job-consumer.log` if services won't start

## Troubleshooting Reference

| Problem | Diagnosis | Solution |
|---------|-----------|----------|
| Docker containers stuck | `docker ps -a` | `make clean-env` then restart Stage 2 |
| MySQL connection refused | `mysql -h 127.0.0.1 -P 6001 -u dump -p111 system -e "SHOW DATABASES;"` | Wait longer, then retry init-env |
| Python module not found | Check logs: `tail -f tmp/apiserver.log` | `poetry install` from workflow_be/src |
| Service port conflict | `lsof -i :8000` (apiserver) | Kill conflicting process or use different port |
| Frontend build hangs | `tail -f tmp/moi-frontend.log` | Ctrl+C, `rm -rf node_modules`, retry pnpm install |
| genai-cli fails | Check .genai-cli.yaml endpoint/api_key | Run auth login first, update api_key with new token |

## Implementation Notes

- **Idempotency**: Each stage can be re-run safely. Existing services are not killed, new ones are started alongside.
- **Concurrency**: Some builds (connector-rpc, workflow-scheduler, catalog-service) can run in parallel in Stage 4.
- **Logging**: All service logs go to `tmp/*.log` for debugging.
- **State persistence**: After Stage 2, volumes preserve data across restarts (`make stop` then `make start` works).
- **API key rotation**: Auth tokens expire hourly; testing the API key endpoint generates a fresh one.
- **Frontend hot-reload**: Vite dev server watches for changes; no rebuild needed for frontend tweaks.

## Understanding apiserver & job-consumer

Stage 4b exists because these Python services have special startup requirements. They're not always available (script-based environments may use direct commands instead).

**See [references/apiserver-jobconsumer.md](./references/apiserver-jobconsumer.md) for:**
- What these services do (REST API vs async worker)
- Full startup commands and environment setup
- Why they fail and how to debug
- Platform-specific issues (macOS DYLD_LIBRARY_PATH, Linux LD_LIBRARY_PATH)
- Poetry dependency resolution details
- When/how to run them if scripts don't exist

## When to Use This Skill

✅ **Initial setup** — Starting from a fresh clone
✅ **After breaking changes** — Reinitialized schema or containers crashed
✅ **Troubleshooting failures** — Diagnose what stage failed and why
✅ **Verifying health** — Confirm all services are running and talking to each other
✅ **Full E2E test** — Auth → API key → CLI → document parsing → verify results
✅ **Port conflicts** — Detect and resolve port clashes with existing processes

❌ **Quick service restart** — If just one service crashed, use `make stop-SERVICE` and `make start-SERVICE`
❌ **Code changes** — If you only modified a service, rebuild that service directly (e.g., `cd connector_rpc && make`)
