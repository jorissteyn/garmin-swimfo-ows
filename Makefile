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
# -Djava.awt.headless=true lets the package tool scale launcher icons on
# headless machines (e.g. over SSH without X); without it `make release`
# crashes with "Can't connect to X11 window server".
export _JAVA_OPTIONS := -Djava.io.tmpdir=$(TMP_DIR) -Djava.awt.headless=true

PRG           = $(OUT_DIR)/$(APP_NAME).prg
PRG_DEV       = $(OUT_DIR)/$(APP_NAME)-dev.prg
IQ_BETA       = $(OUT_DIR)/$(APP_NAME)-beta.iq
IQ_PROD       = $(OUT_DIR)/$(APP_NAME)-prod.iq
TEST_PRG      = $(OUT_DIR)/$(APP_NAME)-test.prg

# App id lifecycle: the committed manifest.xml carries $(APP_ID_MARKER) as a
# placeholder. Every build target swaps in a real UUID before monkeyc runs
# and reverts it via a shell trap — so the manifest always returns to the
# placeholder, even on build failure or Ctrl-C. Never commit a manifest with
# a real id.
APP_ID_BETA    = 4296c8ec-ce06-4e75-becf-e30dda703700
APP_ID_PROD    = 871b853b-bf14-48a4-95ad-6dcc2c6ae471
APP_ID_MARKER  = set by make release command

SOURCES       = $(shell find source -name '*.mc')
RESOURCES     = $(shell find resources -type f)

# ── Targets ───────────────────────────────────────────────────

.PHONY: help build build-dev release-beta release-prod test run sim-start sim-stop clean keygen \
       server-build server-start server-stop server-run server-debug server-clean \
       server-list-remote-locations \
       extremen e

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

build: $(PRG) ## Compile watch-ready PRG (prod server URL, BETA app id)

$(PRG): $(SOURCES) $(RESOURCES) $(JUNGLE) $(KEY) | $(OUT_DIR)
	@mkdir -p $(TMP_DIR)
	@sed -i 's|$(APP_ID_MARKER)|$(APP_ID_BETA)|' manifest.xml; \
	trap 'sed -i "s|$(APP_ID_BETA)|$(APP_ID_MARKER)|" manifest.xml' EXIT INT TERM; \
	$(MC) -o $@ -f $(JUNGLE) -y $(KEY) -d $(DEVICE) -w

build-dev: $(PRG_DEV) ## Compile simulator PRG (localhost server URL, BETA app id)

$(PRG_DEV): $(SOURCES) $(RESOURCES) $(JUNGLE) dev.jungle $(KEY) | $(OUT_DIR)
	@mkdir -p $(TMP_DIR)
	@sed -i 's|$(APP_ID_MARKER)|$(APP_ID_BETA)|' manifest.xml; \
	trap 'sed -i "s|$(APP_ID_BETA)|$(APP_ID_MARKER)|" manifest.xml' EXIT INT TERM; \
	$(MC) -o $@ -f $(JUNGLE):dev.jungle -y $(KEY) -d $(DEVICE) -w

release-beta: $(KEY) | $(OUT_DIR) ## Build .iq for beta channel (BETA app id)
	@mkdir -p $(TMP_DIR)
	@sed -i 's|$(APP_ID_MARKER)|$(APP_ID_BETA)|' manifest.xml; \
	trap 'sed -i "s|$(APP_ID_BETA)|$(APP_ID_MARKER)|" manifest.xml' EXIT INT TERM; \
	$(MC) -o $(IQ_BETA) -f $(JUNGLE) -y $(KEY) -e -r -w

release-prod: $(KEY) | $(OUT_DIR) ## Build .iq for Connect IQ Store (PROD app id)
	@mkdir -p $(TMP_DIR)
	@sed -i 's|$(APP_ID_MARKER)|$(APP_ID_PROD)|' manifest.xml; \
	trap 'sed -i "s|$(APP_ID_PROD)|$(APP_ID_MARKER)|" manifest.xml' EXIT INT TERM; \
	$(MC) -o $(IQ_PROD) -f $(JUNGLE) -y $(KEY) -e -r -w

test: $(TEST_PRG) | sim-start ## Compile and run unit tests in simulator
	$(DO) $< $(DEVICE) -t

$(TEST_PRG): $(SOURCES) $(RESOURCES) $(JUNGLE) dev.jungle $(KEY) | $(OUT_DIR)
	@mkdir -p $(TMP_DIR)
	@sed -i 's|$(APP_ID_MARKER)|$(APP_ID_BETA)|' manifest.xml; \
	trap 'sed -i "s|$(APP_ID_BETA)|$(APP_ID_MARKER)|" manifest.xml' EXIT INT TERM; \
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
	rm -rf $(OUT_DIR)/* $(OUT_DIR)/.[!.]*

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

# ── Server (Node.js/TypeScript API proxy) ─────────────────────

server-build: ## Install server deps and compile TypeScript
	cd server && npm install && npm run build

server-start: server-build ## Start API proxy server in background
	@if [ -f server/.pid ] && kill -0 $$(cat server/.pid) 2>/dev/null; then \
		echo "Server already running (PID $$(cat server/.pid))"; \
	else \
		[ -f server/.env ] || cp server/.env.example server/.env; \
		(cd server && exec node dist/index.js) & \
		echo $$! > server/.pid; \
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
	cd server && node dist/index.js

PORT      ?= 31415
LOCATION  ?= vlissingen

# Optional flag for `make server-debug [extremen|e]` — dumps the raw RWS
# Groepering response and the chronological HW/LW classification. The alias
# words are .PHONY no-ops so make doesn't complain about undefined targets.
EXTREMEN_ARG := $(filter extremen e,$(MAKECMDGOALS))

extremen e:
	@:

server-debug: server-build ## Refresh cache + print pages; pass [extremen|e] for raw RWS HW/LW dump
	@curl -s http://localhost:$(PORT)/conditions/$(LOCATION) > /dev/null && echo "Refreshed $(LOCATION)" || echo "Server not reachable, showing stale cache"
	@node server/dist/debug.js
	@if [ -n "$(EXTREMEN_ARG)" ]; then echo ""; node server/dist/debug-extremen.js $(LOCATION); fi

server-clean: server-stop ## Remove server build artifacts, cache, and logs
	rm -rf server/node_modules server/dist server/cache server/logs server/.pid

server-list-remote-locations: server-build ## List every RWS station that has tide-extrema data
	@node server/dist/list-remote-locations.js

# ── Helpers ───────────────────────────────────────────────────

$(OUT_DIR):
	mkdir -p $@ $(TMP_DIR)

$(KEY):
	@echo "Error: Developer key '$(KEY)' not found. Run 'make keygen' first."
	@exit 1
