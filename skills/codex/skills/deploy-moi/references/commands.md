# MatrixFlow Quick Commands Reference

## Environment Startup

### Full Deployment (all stages)
```bash
# Clean slate (Stage 2→6)
CLEANUP_FIRST=1 bash scripts/deploy.sh

# Continue from existing (Stage 1→6)
bash scripts/deploy.sh

# Dry run (diagnose only, no changes)
DRY_RUN=1 bash scripts/deploy.sh
```

### Individual Stages
```bash
# Stage 1: Diagnostics only
DEPLOY_STAGES=1 bash scripts/deploy.sh

# Stages 2-3: Infra + DB/MQ only
DEPLOY_STAGES=2,3 bash scripts/deploy.sh

# Stage 4: Backend services (initial attempt)
DEPLOY_STAGES=4 bash scripts/deploy.sh

# Stage 4b: Restart apiserver & job-consumer (often needed after Stage 4)
DEPLOY_STAGES=4b bash scripts/deploy.sh

# Stages 4,4b together (recommended for full backend setup)
DEPLOY_STAGES=4,4b bash scripts/deploy.sh

# Skip verification step
SKIP_VERIFY=1 bash scripts/deploy.sh
```

### Traditional Makefile Targets
```bash
make start-env              # Stage 2: start docker-compose
make wait-mo                # Stage 3: wait for MySQL
make init-env               # Stage 3: load schemas + MQ topics
make start                  # Stages 4-5: build & start all services
make status                 # Show service status
make stop                   # Stop all services (keep containers)
make clean-env              # Remove containers + volumes
```

## Debugging & Diagnostics

### Service Status
```bash
make status                         # Overview of all services
make show-all-server-status         # Detailed status
lsof -i :8000                       # Check port conflicts
docker ps -a                        # List all containers
docker logs matrixflow-mo -f        # Stream MySQL logs
```

### Logs
```bash
tail -f tmp/apiserver.log           # Watch API server logs
tail -f tmp/job-consumer.log        # Watch job consumer logs
tail -f tmp/connector-rpc.log       # Watch connector-rpc
grep ERROR tmp/*.log                # Find errors across all logs
```

### Database
```bash
# Connect to MySQL
mysql -h 127.0.0.1 -P 6001 -u dump -p111 system
SHOW DATABASES;
SELECT COUNT(*) FROM moi.account;

# Check RocketMQ topics
docker exec rmqbroker /bin/sh -c "cd /opt/rocketmq/bin && ./mqadmin topicList -n localhost:9876"
```

### Auth & API Key
```bash
# Get new API key
curl -X POST http://127.0.0.1:8000/auth/login \
  -H 'Content-Type: application/json' \
  --data-raw '{"account_name":"local-moi-account","username":"admin:accountadmin","password":"123456","type":"workspace"}'

# Extract token from response, then call:
curl -X GET http://127.0.0.1:8000/user/me/api-key \
  -H 'access-token: <ACCESS-TOKEN>'

# Update genai-cli.yaml with new key
cd catalog_service/cli && sed -i '' "s/api_key: .*/api_key: <NEW_KEY>/" .genai-cli.yaml
```

### MinIO
```bash
# Set up mc alias
mc alias set local-ci http://localhost:9100 minio minio123

# List buckets
mc ls local-ci/

# List files in moi-connector
mc ls local-ci/moi-connector
```

## Testing & Verification

### CLI Pipeline Test
```bash
cd catalog_service/cli
./genai_cli.py pipeline run /path/to/document.docx
```

### Health Checks (POST-deploy)
```bash
# 1. API reachable
curl -s http://127.0.0.1:8000/auth/login | jq .

# 2. Frontend running
curl -s http://localhost:5173/ | head -1

# 3. Connector RPC
nc -zv localhost 9000

# 4. Database tables exist
mysql -h 127.0.0.1 -P 6001 -u dump -p111 system -e "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='moi' LIMIT 5;"
```

## Common Issues & Fixes

### MySQL Connection Refused
```bash
# Symptom: "ERROR 2013: Lost connection to MySQL server"
# Fix: Wait longer for container to start
docker logs matrixflow-mo | tail -20
make wait-mo  # Retry
```

### Poetry Module Not Found
```bash
# Symptom: "ModuleNotFoundError: No module named 'byoa'"
# Fix: Reinstall poetry environment
cd workflow_be && poetry install && poetry lock --no-update
```

### Port Already in Use
```bash
# Symptom: "Address already in use" on port 8000/5173
lsof -i :8000          # Find PID
kill -9 <PID>          # Kill process

# OR use different port
export APISERVER_PORT=8001
```

### Frontend Build Hangs
```bash
# Symptom: pnpm install takes forever
# Fix: Clear cache and retry
rm -rf moi-frontend/node_modules
rm moi-frontend/pnpm-lock.yaml
cd moi-frontend && pnpm install
```

### Services Stop Unexpectedly
```bash
# Check logs for crashes
grep -i "error\|panic\|fatal" tmp/*.log

# Restart individual service
make stop-apiserver
make start-apiserver

# Or restart all
make stop-all-services
make start
```

## Environment Variables

Key env vars used during deployment (set in `optools/matrixflow/.env`):

| Variable | Default | Purpose |
|----------|---------|---------|
| `DATABASE_URI` | `mysql+asyncmy://dump:111@127.0.0.1:6001/moi` | Async DB connection |
| `MINIO_ENDPOINT` | `127.0.0.1:9100` | MinIO API |
| `MINIO_ACCESS_KEY` | `minio` | MinIO credentials |
| `PYTHONPATH` | (set) | Python path for workflow_be |
| `JOB_CONSUMER_METRICS_ENABLED` | `false` | Disable metrics by default |
| `OPENXML_SERVER_URL` | `http://127.0.0.1:8817/parse` | Document parser URL |

## Performance Tips

- **Parallel builds**: Run `cd connector_rpc && make` and `cd workflow_scheduler && make` in separate terminals
- **Skip frontend if not needed**: Set `DEPLOY_STAGES=1,2,3,4` to skip frontend (Stage 5)
- **Preserve volumes**: Use `make stop` instead of `make clean-env` to keep data between runs
- **Cache Docker images**: Pull images once, reuse across runs
