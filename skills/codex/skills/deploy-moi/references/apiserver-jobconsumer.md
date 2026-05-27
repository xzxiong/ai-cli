# apiserver & job-consumer: Implementation Details

Why does Stage 4b exist? These two services have special requirements that often cause them to fail on first start.

## Service: apiserver

**What it does**: REST API server for the MatrixFlow system
- Handles auth (/auth/login)
- Serves user endpoints (/user/me/api-key)
- Integrates with document parsing pipeline
- Manages workflows and jobs

**Technology Stack**:
- Language: Python (FastAPI)
- Location: `workflow_be/src/byoa/main.py`
- Dependencies: managed by `poetry` (workflow_be/pyproject.toml)
- Configuration: `optools/matrixflow/.env`

**Startup Process** (from Makefile):
```bash
# Step 1: Load environment variables
. optools/matrixflow/.env

# Step 2: Navigate to service source
cd workflow_be/src

# Step 3: Set Python path to find local modules
export PYTHONPATH=$(ROOT_DIR)/workflow_be:$(ROOT_DIR)/workflow_be/src

# Step 4: Set dynamic library path (macOS: libmagic.dylib, Linux: varies)
export DYLD_LIBRARY_PATH="$(DYLD_LIBRARY_PATH)"

# Step 5: Ensure Python dependencies installed
poetry install

# Step 6: Start the service
poetry run python3 byoa/main.py >> $(LOG_DIR)/apiserver.log 2>&1 &
```

**Logs**: `tmp/apiserver.log`

**Port**: 8000 (configurable via FLASK_PORT or FASTAPI_PORT)

**Why it fails initially**:
1. Poetry needs time to resolve dependencies
2. First `poetry install` can take 30-60 seconds
3. `make start` may not wait long enough
4. MySQL or other dependencies might not be ready yet

**Verification**:
```bash
curl -X POST http://127.0.0.1:8000/auth/login \
  -H 'Content-Type: application/json' \
  --data-raw '{"account_name":"local-moi-account","username":"admin:accountadmin","password":"123456","type":"workspace"}'

# Success: Returns JSON with "Access-Token" field
# Failure: Connection refused or error response
```

---

## Service: job-consumer

**What it does**: Background worker that processes async jobs
- Polls RabbitMQ for task messages
- Executes document parsing jobs
- Updates job status in database
- Retries failed jobs
- Sends completion notifications

**Technology Stack**:
- Language: Python (consumer pattern)
- Location: `workflow_be/src/byoa/job_consumer.py`
- Dependencies: same as apiserver (shared `poetry` environment)
- Configuration: `optools/matrixflow/.env`
- Message Queue: RabbitMQ (via amqp)

**Startup Process** (from start-jobconsumer.sh):
```bash
# Step 1: Load shell configuration
. ~/.bashrc

# Step 2: Get ROOT_DIR and LOG_DIR
ROOT_DIR="/Users/jacksonxie/go/src/github.com/matrixorigin/matrixflow"
LOG_DIR=${ROOT_DIR}/tmp

# Step 3: Load environment variables
. optools/matrixflow/.env

# Step 4: Navigate to service source
cd workflow_be/src

# Step 5: Set Python path (same as apiserver)
export PYTHONPATH=${ROOT_DIR}/workflow_be:${ROOT_DIR}/workflow_be/src

# Step 6: Enable metrics collection
export JOB_CONSUMER_METRICS_ENABLED=true

# Step 7: Set dynamic library path
DYLD_LIBRARY_PATH=${DYLD_LIBRARY_PATH}

# Step 8: Start as background process
poetry run python3 byoa/job_consumer.py >> ${LOG_DIR}/job-consumer.log 2>&1 &
```

**Logs**: `tmp/job-consumer.log`

**No fixed port**: Runs as a daemon, polls RabbitMQ internally

**Why it fails initially**:
1. RabbitMQ topics might not be created yet (handled by Stage 3)
2. Poetry environment not fully initialized
3. MySQL connection might not be ready
4. Job consumer tries to connect on startup and times out

**Verification**:
```bash
# Check if process is running
ps aux | grep "job_consumer.py" | grep -v grep

# Check logs for errors
tail -50 tmp/job-consumer.log

# Look for these healthy signs:
# - "Connected to RabbitMQ"
# - "Listening on topic: task"
# - "Consumer started"

# Look for these unhealthy signs:
# - "Connection refused"
# - "ModuleNotFoundError"
# - "No such file"
```

---

## Environment Variables (from optools/matrixflow/.env)

Both services need these to be set:

| Variable | Example | Purpose |
|----------|---------|---------|
| `DATABASE_URI` | `mysql+asyncmy://dump:111@127.0.0.1:6001/moi` | Async DB connection (apiserver + job-consumer) |
| `DATABASE_SYNC_URI` | `mysql://dump:111@127.0.0.1:6001/moi` | Sync DB connection (migrations) |
| `MINIO_ENDPOINT` | `127.0.0.1:9100` | File storage for parsed documents |
| `MINIO_ACCESS_KEY` | `minio` | MinIO credentials |
| `MINIO_SECRET_KEY` | `minio123` | MinIO credentials |
| `OPENXML_SERVER_URL` | `http://127.0.0.1:8817/parse` | Document parser service |
| `OPENAI_API_KEY` | `sk-...` | LLM for content generation |
| `JOB_CONSUMER_INTERVAL_SECS` | `5` | Polling interval (job-consumer only) |
| `LOG_LEVEL` | `INFO` | Logging verbosity |

---

## Poetry Environment

Both services share the same Poetry environment: `workflow_be/pyproject.toml`

**Key dependencies**:
- FastAPI (apiserver)
- SQLAlchemy (database ORM)
- pydantic (data validation)
- aio-pika (RabbitMQ client)
- pandas (data processing)
- pillow (image processing)

**Why poetry can be slow**:
- First install resolves dependency tree (can take minutes)
- Transitive dependencies can be numerous
- Network requests to PyPI
- Compilation of C extensions (numpy, etc.)

**Optimization**:
```bash
# Use cached lock file instead of resolving
cd workflow_be
poetry install --no-update

# Or force faster installation
poetry config installer.parallel-jobs 4
poetry install
```

---

## Platform Differences

### macOS (Darwin)
- DYLD_LIBRARY_PATH needed for libmagic.dylib
- scripts/deploy.sh detects with `uname -s`
- Example: `DYLD_LIBRARY_PATH=/usr/local/opt/libmagic/lib`

### Linux
- LD_LIBRARY_PATH might be needed instead
- May need: `apt-get install libmagic1`
- Example: `LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu`

### Docker (if running in container)
- Libraries pre-installed in image
- DYLD_LIBRARY_PATH may not be needed
- PYTHONPATH handling might differ

---

## Troubleshooting

### apiserver won't start

**Error: ModuleNotFoundError: No module named 'byoa'**
- Solution: Check PYTHONPATH, run `poetry install` first
- Check: `echo $PYTHONPATH` from workflow_be/src directory

**Error: Cannot connect to mysql**
- Solution: Verify MySQL container running, check DATABASE_URI in .env
- Check: `make status` shows mysql running

**Error: Address already in use (port 8000)**
- Solution: Kill existing process or use different port
- Check: `lsof -i :8000`

**Error: poetry: command not found**
- Solution: Install poetry: `curl -sSL https://install.python-poetry.org | python3 -`
- Check: `poetry --version`

### job-consumer won't start

**Error: Connection refused (RabbitMQ)**
- Solution: Check RabbitMQ container running, verify RABBITMQ_URL in .env
- Check: `docker ps | grep rmq`

**Error: ImportError: cannot import name 'X'**
- Solution: Poetry environment out of sync
- Fix: `cd workflow_be && rm -rf .venv && poetry install`

**Error: No route to host (database)**
- Solution: MySQL not ready, try again
- Fix: `make wait-mo && sleep 5 && sh start-jobconsumer.sh`

### Both services failing

**General debugging**:
```bash
# 1. Check recent errors in logs
tail -100 tmp/apiserver.log tmp/job-consumer.log

# 2. Verify all containers running
docker ps | grep -E "matrixflow|rmq"

# 3. Check if ports are free
lsof -i :8000 :9000 :5173 :6001

# 4. Verify env vars are set
grep -E "DATABASE_URI|MINIO|OPENAI" optools/matrixflow/.env

# 5. Try manual poetry install
cd workflow_be && poetry install --verbose
```

---

## When Scripts Aren't Available

If `start-apiserver.sh` or `start-jobconsumer.sh` don't exist in your environment:

### Run apiserver directly:
```bash
cd ~/go/src/github.com/matrixorigin/matrixflow
. optools/matrixflow/.env
cd workflow_be/src
export PYTHONPATH=../../workflow_be:../../workflow_be/src
export DYLD_LIBRARY_PATH="/path/to/libmagic/lib"
poetry install
poetry run python3 byoa/main.py >> ../../tmp/apiserver.log 2>&1 &
```

### Run job-consumer directly:
```bash
cd ~/go/src/github.com/matrixorigin/matrixflow
. optools/matrixflow/.env
cd workflow_be/src
export PYTHONPATH=../../workflow_be:../../workflow_be/src
export JOB_CONSUMER_METRICS_ENABLED=true
poetry run python3 byoa/job_consumer.py >> ../../tmp/job-consumer.log 2>&1 &
```

Or use Makefile targets if available:
```bash
cd ~/go/src/github.com/matrixorigin/matrixflow
make start-apiserver
make start-job-consumer  # or similar
```
