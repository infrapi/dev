# InfraPI dev stack: etcd, Kayra (serve, reconciler) and APISIX, on podman.
#
#   make up         build Kayra's image and start the stack
#   make contexts   mint tokens and save them as kayra-cli contexts
#   make help       everything else
#
# See docs/dev-stack.md and docs/create-an-api.md.

# where your Kayra checkout is: the image is built from it
KAYRA_SRC ?= ../kayra
IMAGE     ?= kayra-dev:local
COMPOSE   ?= podman compose -f compose.yaml
GATEWAY   ?= http://localhost:9080
ADMIN_URL ?= http://localhost:9180
BIN       := $(CURDIR)/bin
KAYRA_CLI := $(BIN)/kayra-cli

# the example API, see docs/create-an-api.md
EXAMPLE  ?= examples/compute
API      ?= compute.infrapi.io
UPSTREAM ?= host.containers.internal:8080

# a lib checkout to run the example against, instead of the version its
# go.mod pins: make example LIB_SRC=../lib
LIB_SRC ?=

SERVICE ?=
SUBJECT ?= jdoe

.DEFAULT_GOAL := help
.PHONY: help build up down clean restart ps logs health routes token contexts cli \
        api-add api-rm example-env example check

help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'
	@echo; echo "  KAYRA_SRC=$(KAYRA_SRC)  API=$(API)  UPSTREAM=$(UPSTREAM)"

# ---------------------------------------------------------------- the stack

build: ## Build kayra-dev:local from $(KAYRA_SRC), new signing keys included
	@test -f "$(KAYRA_SRC)/go.mod" || { echo "no Kayra checkout at $(KAYRA_SRC): clone infrapi/kayra there, or set KAYRA_SRC"; exit 1; }
	podman build --format docker --build-context src=$(KAYRA_SRC) -t $(IMAGE) kayra

up: build ## Build, then start the stack
	$(COMPOSE) up -d
	@echo; echo "  Kayra   http://localhost:8081   gateway $(GATEWAY)   APISIX Admin API $(ADMIN_URL)"
	@echo "  next:   make contexts"

down: ## Stop the stack, keep etcd's data
	$(COMPOSE) down

clean: ## Stop the stack and wipe etcd: Kayra's objects and APISIX's routes
	$(COMPOSE) down -v

restart: ## Restart SERVICE, or every service
	$(COMPOSE) restart $(SERVICE)

ps: ## List the stack's containers
	$(COMPOSE) ps

logs: ## Follow the logs of SERVICE (kayra, reconciler, apisix...), or all
	$(COMPOSE) logs -f $(SERVICE)

health: ## Check Kayra and the gateway answer
	@curl -fsS http://localhost:8081/-/healthz && echo "  kayra"
	@curl -fsS $(GATEWAY)/healthz && echo "  gateway"

routes: ## Load the stack's APISIX routes back as they were
	$(COMPOSE) run --rm gateway-init

# ---------------------------------------------------------- tokens and CLI

cli: $(KAYRA_CLI) ## Build kayra-cli from $(KAYRA_SRC) into bin/
	@echo; echo "  kayra-cli is in bin/, run:"; echo; echo '    export PATH="$(BIN):$$PATH"'; echo

$(KAYRA_CLI): $(shell find $(KAYRA_SRC)/cmd/cli $(KAYRA_SRC)/internal/clicontext -name '*.go' 2>/dev/null)
	@mkdir -p $(BIN)
	cd $(KAYRA_SRC) && go build -o $(KAYRA_CLI) ./cmd/cli

token: ## Print a token for SUBJECT (jdoe, nobody: kayra/users.yaml) from the local provider
	@$(COMPOSE) exec -T kayra kayra token mint --provider local --subject $(SUBJECT) --ttl 8h

contexts: $(KAYRA_CLI) ## Save dev-admin, dev-jdoe and dev-nobody as kayra-cli contexts, on the gateway
	@set -e; \
	admin=$$($(COMPOSE) exec -T kayra kayra token mint --provider self --group sandbox-core-sysadmin --ttl 8h); \
	jdoe=$$($(COMPOSE) exec -T kayra kayra token mint --provider local --subject jdoe --ttl 8h); \
	nobody=$$($(COMPOSE) exec -T kayra kayra token mint --provider local --subject nobody --ttl 8h); \
	$(KAYRA_CLI) context set dev-nobody --server $(GATEWAY) --api-domain infrapi.io --token "$$nobody"; \
	$(KAYRA_CLI) context set dev-jdoe   --server $(GATEWAY) --api-domain infrapi.io --token "$$jdoe"; \
	$(KAYRA_CLI) context set dev-admin  --server $(GATEWAY) --api-domain infrapi.io --token "$$admin"
	@echo; echo "  kayra-cli is in bin/, run:"; echo; echo '    export PATH="$(BIN):$$PATH"'; echo

# --------------------------------------------------------------- your API

api-add: ## Route API through APISIX to UPSTREAM (default: the example on the host's 8080)
	APISIX_ADMIN_URL=$(ADMIN_URL) sh apisix/add-api.sh $(API) $(UPSTREAM)

api-rm: ## Remove API's routes
	APISIX_ADMIN_URL=$(ADMIN_URL) sh apisix/add-api.sh -d $(API)

example-env: $(EXAMPLE)/.env

$(EXAMPLE)/.env:
	cp $(EXAMPLE)/.env.example $@

example: example-env ## Run the example API on the host, port 8080 (LIB_SRC=../lib: against a lib checkout)
ifeq ($(LIB_SRC),)
	cd $(EXAMPLE) && go run .
else
	@mkdir -p $(BIN)
	printf 'go 1.26.7\n\nuse (\n\t%s\n\t%s\n)\n' $(abspath $(EXAMPLE)) $(abspath $(LIB_SRC)) > $(BIN)/go.work
	cd $(EXAMPLE) && GOWORK=$(BIN)/go.work go run .
endif

check: ## Lint the scripts and build the example
	sh -n apisix/routes.sh && sh -n apisix/add-api.sh && sh -n kayra/render-config.sh
	cd $(EXAMPLE) && go vet ./... && go build -o /dev/null .
