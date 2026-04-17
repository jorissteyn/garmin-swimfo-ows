# Swimfo - Garmin Connect IQ Data Field
# Run `make help` for available targets.

# ── Configuration ─────────────────────────────────────────────
# Override on command line: make DEVICE=venu2_sim build

GARMIN_HOME  ?= $(CURDIR)/.sdk
MC            = $(GARMIN_HOME)/bin/monkeyc
SIM           = $(GARMIN_HOME)/bin/connectiq
DO            = $(GARMIN_HOME)/bin/monkeydo

KEY          ?= developer_key.der
JUNGLE        = monkey.jungle
DEVICE       ?= fr265
OUT_DIR       = bin
APP_NAME      = ZeelandOWS

# Ensure a writable temp directory (sandbox/read-only /tmp workaround)
TMP_DIR       = $(CURDIR)/bin/.tmp
export TMPDIR := $(TMP_DIR)
export TEMP   := $(TMP_DIR)
export TMP    := $(TMP_DIR)
export _JAVA_OPTIONS := -Djava.io.tmpdir=$(TMP_DIR)

PRG           = $(OUT_DIR)/$(APP_NAME).prg
PRG_DEV       = $(OUT_DIR)/$(APP_NAME)-dev.prg
IQ            = $(OUT_DIR)/$(APP_NAME).iq
TEST_PRG      = $(OUT_DIR)/$(APP_NAME)-test.prg

SOURCES       = $(shell find source -name '*.mc')
RESOURCES     = $(shell find resources -type f)

# ── Targets ───────────────────────────────────────────────────

.PHONY: help build build-dev release test run sim-start sim-stop clean keygen \
       server-build server-start server-stop server-run server-debug server-clean

help: ## Show this help
	@echo "Swimfo — Garmin Connect IQ Data Field"
	@echo ""
	@echo "Usage: make [target] [DEVICE=fenix7_sim] [KEY=developer_key.der]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Devices: fenix7 fenix7s fenix7x venu2 venu2s fr955 fr965 epix2"

build: $(PRG) ## Compile watch-ready PRG (prod server URL)

$(PRG): $(SOURCES) $(RESOURCES) $(JUNGLE) $(KEY) | $(OUT_DIR)
	@mkdir -p $(TMP_DIR)
	$(MC) -o $@ -f $(JUNGLE) -y $(KEY) -d $(DEVICE) -w

build-dev: $(PRG_DEV) ## Compile simulator PRG (localhost server URL)

$(PRG_DEV): $(SOURCES) $(RESOURCES) $(JUNGLE) dev.jungle $(KEY) | $(OUT_DIR)
	@mkdir -p $(TMP_DIR)
	$(MC) -o $@ -f $(JUNGLE):dev.jungle -y $(KEY) -d $(DEVICE) -w

release: $(KEY) | $(OUT_DIR) ## Build .iq store package (prod server URL)
	@mkdir -p $(TMP_DIR)
	$(MC) -o $(IQ) -f $(JUNGLE) -y $(KEY) -e -r -w

test: $(TEST_PRG) | sim-start ## Compile and run unit tests in simulator
	$(DO) $< $(DEVICE) -t

$(TEST_PRG): $(SOURCES) $(RESOURCES) $(JUNGLE) dev.jungle $(KEY) | $(OUT_DIR)
	@mkdir -p $(TMP_DIR)
	$(MC) -o $@ -f $(JUNGLE):dev.jungle -y $(KEY) -d $(DEVICE) -t -w

run: $(PRG_DEV) | sim-start ## Build dev PRG and run in simulator
	$(DO) $< $(DEVICE)

sim-start: ## Start the Connect IQ simulator
	@if ! pgrep -x "simulator" > /dev/null 2>&1; then \
		echo "Starting simulator..."; \
		$(SIM) & \
		sleep 3; \
	else \
		echo "Simulator already running."; \
	fi

sim-stop: ## Stop the Connect IQ simulator
	@if pgrep -x "simulator" > /dev/null 2>&1; then \
		pkill -x "simulator"; \
		echo "Simulator stopped."; \
	else \
		echo "Simulator not running."; \
	fi

clean: ## Remove build artifacts
	rm -rf $(OUT_DIR)

keygen: ## Generate developer key (one-time setup)
	@if [ -f $(KEY) ]; then \
		echo "$(KEY) already exists. Remove it first to regenerate."; \
	else \
		openssl genrsa -out developer_key.pem 4096; \
		openssl pkcs8 -topk8 -inform PEM -outform DER \
			-in developer_key.pem -out $(KEY) -nocrypt; \
		rm developer_key.pem; \
		echo "Created $(KEY)"; \
	fi

# ── Server (Node.js API proxy) ────────────────────────────────

server-build: ## Install server dependencies
	cd server && npm install

server-start: server-build ## Start API proxy server in background
	@if [ -f server/.pid ] && kill -0 $$(cat server/.pid) 2>/dev/null; then \
		echo "Server already running (PID $$(cat server/.pid))"; \
	else \
		cd server && [ -f .env ] || cp .env.example .env; \
		cd server && node index.js & echo $$! > server/.pid; \
		echo "Server started (PID $$(cat server/.pid))"; \
	fi

server-stop: ## Stop the API proxy server
	@if [ -f server/.pid ] && kill -0 $$(cat server/.pid) 2>/dev/null; then \
		kill $$(cat server/.pid); \
		rm -f server/.pid; \
		echo "Server stopped."; \
	else \
		rm -f server/.pid; \
		echo "Server not running."; \
	fi

server-run: server-build ## Run API proxy server in foreground
	@cd server && [ -f .env ] || cp .env.example .env
	cd server && node index.js

PORT      ?= 31415
LOCATION  ?= vlissingen

server-debug: ## Fetch fresh data and print cache (LOCATION=vlissingen)
	@curl -s http://localhost:$(PORT)/conditions/$(LOCATION) > /dev/null && echo "Refreshed $(LOCATION)" || echo "Server not reachable, showing stale cache"
	@node server/debug.js

server-clean: server-stop ## Remove server build artifacts, cache, and logs
	rm -rf server/node_modules server/cache server/logs server/.pid

# ── Helpers ───────────────────────────────────────────────────

$(OUT_DIR):
	mkdir -p $@ $(TMP_DIR)

$(KEY):
	@echo "Error: Developer key '$(KEY)' not found. Run 'make keygen' first."
	@exit 1
