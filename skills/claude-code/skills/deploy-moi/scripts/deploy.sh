#!/bin/bash
# Deploy MOI: Local MatrixFlow deployment orchestrator
# Runs 6 idempotent stages: diagnose → infra → db/mq → backend → frontend → verify

set -e
cd ~/go/src/github.com/matrixorigin/matrixflow

# Configuration
DEPLOY_STAGES="${DEPLOY_STAGES:-1,2,3,4,5,6}"
SKIP_VERIFY="${SKIP_VERIFY:-0}"
CLEANUP_FIRST="${CLEANUP_FIRST:-0}"
DRY_RUN="${DRY_RUN:-0}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Stage 1: Diagnostics
stage_diagnostics() {
  log_info "Stage 1: Environment Diagnostics"

  # Check tools
  local tools=("docker" "docker-compose" "mysql" "make" "curl" "go" "python3" "dotnet")
  for tool in "${tools[@]}"; do
    if command -v "$tool" &> /dev/null; then
      local version=$($tool --version 2>&1 | head -1)
      log_ok "$tool: $version"
    else
      log_warn "$tool: NOT FOUND"
    fi
  done

  # Check repo structure
  if [ -f "Makefile" ] && [ -d "workflow_be" ] && [ -d "connector_rpc" ]; then
    log_ok "Repo structure: Valid"
  else
    log_error "Repo structure: Invalid"
    return 1
  fi

  # Check Docker daemon
  if docker ps &> /dev/null; then
    log_ok "Docker daemon: Running"
  else
    log_error "Docker daemon: Not responding"
    return 1
  fi

  # Detect existing containers
  local running=$(docker ps --format "{{.Names}}" | grep -E "rmq|matrixflow" | wc -l)
  if [ "$running" -gt 0 ]; then
    log_warn "Found $running existing containers (will preserve)"
    docker ps --filter "label!=keep" --format "table {{.Names}}\t{{.Status}}"
  else
    log_ok "No existing MatrixFlow containers"
  fi
}

# Stage 2: Infrastructure
stage_infrastructure() {
  log_info "Stage 2: Infrastructure Setup (Docker/Volumes)"

  [ "$DRY_RUN" = "1" ] && { log_warn "DRY RUN: Skipping Stage 2"; return 0; }

  log_info "Starting docker-compose (RMQ profile)..."
  docker compose -f optools/matrixflow/docker-compose.yaml --profile launch_rmq up -d || {
    log_error "Failed to start RMQ containers"
    return 1
  }

  log_info "Starting docker-compose (main profile)..."
  docker compose -f optools/matrixflow/docker-compose.yaml --profile launch up -d || {
    log_error "Failed to start main containers"
    return 1
  }

  log_ok "Infrastructure containers started"
}

# Stage 3: DB & MQ Init
stage_db_mq() {
  log_info "Stage 3: Database & Message Queue Initialization"

  [ "$DRY_RUN" = "1" ] && { log_warn "DRY RUN: Skipping Stage 3"; return 0; }

  log_info "Waiting for MySQL to be ready..."
  bash optools/script/wait_mo.sh || {
    log_error "MySQL did not become ready"
    return 1
  }
  log_ok "MySQL is ready"

  log_info "Initializing databases..."
  make init-env || {
    log_error "Failed to initialize env"
    return 1
  }
  log_ok "Database and MQ topics initialized"
}

# Stage 4: Backend Services
stage_backend() {
  log_info "Stage 4: Build & Start Backend Services"

  [ "$DRY_RUN" = "1" ] && { log_warn "DRY RUN: Skipping Stage 4"; return 0; }

  # Build && start
  log_info "Building and starting backend services..."
  make start || {
    log_error "Failed to start backend services"
    return 1
  }

  # Wait a bit for services to initialize
  log_info "Waiting 5s for services to stabilize..."
  sleep 5

  log_ok "Backend services started (main wave)"
}

# Stage 4b: Restart apiserver & job-consumer
stage_backend_retry() {
  log_info "Stage 4b: Restarting apiserver & job-consumer (often needed after initial start)"

  [ "$DRY_RUN" = "1" ] && { log_warn "DRY RUN: Skipping Stage 4b"; return 0; }

  log_info "Restarting apiserver with DYLD_LIBRARY_PATH..."
  sh start-apiserver.sh || {
    log_error "Failed to start apiserver"
    return 1
  }

  log_info "Restarting job-consumer with JOB_CONSUMER_METRICS_ENABLED..."
  sh start-jobconsumer.sh || {
    log_error "Failed to start job-consumer"
    return 1
  }

  log_info "Waiting 5s for services to initialize..."
  sleep 5

  log_ok "apiserver & job-consumer restarted successfully"
}

# Stage 5: Frontend
stage_frontend() {
  log_info "Stage 5: Build & Start Frontend"

  [ "$DRY_RUN" = "1" ] && { log_warn "DRY RUN: Skipping Stage 5"; return 0; }

  # Frontend is already started by make start, but we can verify it here
  if lsof -i :5173 &> /dev/null; then
    log_ok "Frontend is running on port 5173"
  else
    log_warn "Frontend not detected on port 5173"
  fi
}

# Stage 6: Verification
stage_verify() {
  log_info "Stage 6: Verification & Testing"

  if [ "$SKIP_VERIFY" = "1" ]; then
    log_warn "Skipping verification (SKIP_VERIFY=1)"
    return 0
  fi

  [ "$DRY_RUN" = "1" ] && { log_warn "DRY RUN: Skipping Stage 6"; return 0; }

  # Check service status
  log_info "Checking service status..."
  make status || log_warn "Status check had issues"

  # Quick health check
  log_info "Health check: Testing /auth/login endpoint..."
  local response=$(curl -s -X POST http://127.0.0.1:8000/auth/login \
    -H 'Content-Type: application/json' \
    --data-raw '{"account_name":"local-moi-account","username":"admin:accountadmin","password":"123456","type":"workspace"}')

  if echo "$response" | grep -q "Access-Token"; then
    log_ok "Auth test passed"
  else
    log_error "Auth test failed: $response"
    return 1
  fi

  log_ok "All verifications passed"
}

# Main orchestration
main() {
  log_info "Deploy MOI: Local MatrixFlow Setup"
  log_info "Stages: $DEPLOY_STAGES | Cleanup: $CLEANUP_FIRST | Dry-run: $DRY_RUN"

  if [ "$CLEANUP_FIRST" = "1" ]; then
    log_warn "Cleaning up existing environment..."
    make clean-env || true
    sleep 2
  fi

  # Run requested stages
  IFS=',' read -ra stages <<< "$DEPLOY_STAGES"
  for stage_num in "${stages[@]}"; do
    case "$stage_num" in
      1) stage_diagnostics ;;
      2) stage_infrastructure ;;
      3) stage_db_mq ;;
      4) stage_backend ;;
      4b) stage_backend_retry ;;
      5) stage_frontend ;;
      6) stage_verify ;;
      *) log_error "Unknown stage: $stage_num" ;;
    esac

    if [ $? -ne 0 ]; then
      log_error "Stage $stage_num failed"
      return 1
    fi
  done

  log_ok "✅ All stages completed successfully"
  log_info "Access the frontend at: http://localhost:5173/local-moi-account/dev"
}

main "$@"
