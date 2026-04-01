GO ?= go
# BINARY is the output path/name of the compiled CLI binary.
BINARY ?= ai-cli
# TOOLS controls which tools are synced by install/upload targets.
TOOLS ?= all
# GOCACHE keeps go run/build cache out of restricted system paths.
GOCACHE ?= /tmp/gocache

.PHONY: help fmt test build run install upload

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*##"; print "Available targets:"} /^[a-zA-Z0-9_-]+:.*##/ {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

fmt: ## Format Go code
	$(GO) fmt ./...

test: ## Run unit tests
	$(GO) test ./...

build: ## Build ai-cli binary (override with BINARY=bin/ai-cli)
	$(GO) build -o $(BINARY) ./cmd/ai-cli

run: ## Run ai-cli with ARGS, example: make run ARGS="skills --install --tools codex"
	GOCACHE=$(GOCACHE) $(GO) run ./cmd/ai-cli $(ARGS)

install: ## Install skills/knowledge from repo to local tools (TOOLS=all|codex|kiro|claude-code)
	GOCACHE=$(GOCACHE) $(GO) run ./cmd/ai-cli skills --install --tools $(TOOLS)

upload: ## Upload local skills/knowledge to repo and run diff-merge-commit-push (TOOLS=all|codex|kiro|claude-code)
	GOCACHE=$(GOCACHE) $(GO) run ./cmd/ai-cli skills --upload --tools $(TOOLS)
