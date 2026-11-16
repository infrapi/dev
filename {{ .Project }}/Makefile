# InfraPI dev stack: etcd, Kayra (serve, reconciler) and APISIX, on podman
# or docker, configured by dev.yaml. Needs one of them with compose, and
# infrapi-cli (which scaffolded it: infrapi-cli dev init).
#
#   make doctor     check the prerequisites
#   make up         render .infrapi-dev/ from dev.yaml and start the stack
#   make contexts   mint tokens and save them as infrapi-cli contexts
#   make kickstart  create dev.yaml's APIs and tenants in Kayra
#   make help       everything else
#
# See https://github.com/infrapi/dev: docs/dev-stack.md, docs/create-an-api.md.

# the stack's settings, and where the files rendered from them go
DEV_CONFIG  ?= dev.yaml
DEV_DIR     := .infrapi-dev
BIN         := $(CURDIR)/bin
INFRAPI_CLI ?= infrapi-cli

# What dev.yaml says, rendered: DEV_DOMAIN, KAYRA_IMAGE, KAYRA_SRC, the
# ports... make renders it first, and again when dev.yaml changes.
-include $(DEV_DIR)/env

# The container engine: podman when it is installed, docker otherwise.
# Override it, for one command or for good:
#
#   make up ENGINE=docker        export ENGINE=docker
#
# or replace the commands themselves: make up COMPOSE="nerdctl compose ..."
ENGINE ?= $(if $(shell command -v podman 2>/dev/null),podman,docker)
# what the gateway, in a container, calls the host: where your API runs
HOST_ALIAS ?= $(if $(filter docker,$(ENGINE)),host.docker.internal,host.containers.internal)
# docker on Linux has no host.docker.internal of its own: compose.docker.yaml
# gives it one
COMPOSE_FILES ?= -f compose.yaml $(if $(filter docker,$(ENGINE)),-f compose.docker.yaml)
COMPOSE   ?= $(ENGINE) compose --env-file $(DEV_DIR)/env $(COMPOSE_FILES)
# --format docker keeps the image's HEALTHCHECK, which podman's OCI default drops
BUILD     ?= $(ENGINE) build $(if $(filter podman,$(ENGINE)),--format docker)
GATEWAY   := http://localhost:$(GATEWAY_PORT)
ADMIN_URL := http://localhost:$(ADMIN_PORT)
IMAGE     := kayra-dev:local

# the example API, see docs/create-an-api.md
EXAMPLE  ?= examples/compute
API      ?= $(EXAMPLE_API)
UPSTREAM ?= $(HOST_ALIAS):$(EXAMPLE_PORT)

# a lib checkout to run the example against, instead of the version its
# go.mod pins: make example LIB_SRC=../lib
LIB_SRC ?=

SERVICE ?=
SUBJECT ?= jdoe

# make render NEW_KEYS=1 (or make up NEW_KEYS=1): new signing keys, every
# token minted before refused
NEW_KEYS ?=

.DEFAULT_GOAL := help
.PHONY: help doctor render build up down clean reset-kayra restart ps logs health routes token contexts kickstart \
        api-add api-rm example check

help: ## Show this help
	@grep -hE '^[a-z-]+:.*## ' $(firstword $(MAKEFILE_LIST)) | awk -F':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'
	@echo; echo "  $(DEV_CONFIG): domain $(DEV_DOMAIN), kayra $(if $(KAYRA_SRC),built from $(KAYRA_SRC),$(KAYRA_IMAGE)), gateway $(GATEWAY), engine $(ENGINE)"

doctor: ## Check the prerequisites: the container engine and its compose, infrapi-cli, curl, go
	@ok=0; \
	check() { if command -v "$$1" >/dev/null 2>&1; then printf '  ok       %-12s %s\n' "$$1" "$$($$2 2>/dev/null | head -1 | cut -c1-60)"; \
	          else printf '  MISSING  %-12s %s\n' "$$1" "$$3"; ok=1; fi; }; \
	check $(ENGINE) "$(ENGINE) --version" "install podman (https://podman.io/docs/installation) or docker, or set ENGINE"; \
	if $(ENGINE) compose version >/dev/null 2>&1; then printf '  ok       %-12s %s\n' compose "$$($(ENGINE) compose version 2>/dev/null | head -1)"; \
	else printf '  MISSING  %-12s %s\n' compose "$(ENGINE) compose: podman-compose or docker-compose (podman), the compose plugin (docker)"; ok=1; fi; \
	check $(INFRAPI_CLI) "$(INFRAPI_CLI) --version" "https://infrapi.github.io/cli/getting-started/#1-install"; \
	check curl "curl --version" "your package manager"; \
	if command -v go >/dev/null 2>&1; then printf '  ok       %-12s %s\n' go "$$(go version)"; \
	else printf '  optional %-12s %s\n' go "only for make example: https://go.dev/dl/"; fi; \
	echo; echo "  engine $(ENGINE), the host seen from the containers as $(HOST_ALIAS)"; exit $$ok

# ------------------------------------------------------ dev.yaml, rendered

$(DEV_DIR)/env: $(DEV_CONFIG)
	@command -v $(INFRAPI_CLI) >/dev/null || { echo "$(INFRAPI_CLI) is not on PATH: see https://github.com/infrapi/cli"; exit 1; }
	$(INFRAPI_CLI) dev render --config $(DEV_CONFIG) --out $(DEV_DIR)

render: ## Render .infrapi-dev/ from dev.yaml; NEW_KEYS=1 for new signing keys
	$(INFRAPI_CLI) dev render --config $(DEV_CONFIG) --out $(DEV_DIR) $(if $(NEW_KEYS),--new-keys)

# ---------------------------------------------------------------- the stack

build: render ## Build kayra-dev:local from dev.yaml's kayra.src
ifeq ($(KAYRA_SRC),)
	@echo "build: kayra.src is not set in $(DEV_CONFIG): the stack runs $(KAYRA_IMAGE), nothing to build"
else
	@test -f "$(KAYRA_SRC)/go.mod" || { echo "no Kayra checkout at $(KAYRA_SRC) (kayra.src in $(DEV_CONFIG))"; exit 1; }
	$(BUILD) --build-context src=$(KAYRA_SRC) -t $(IMAGE) kayra
endif

up: render $(if $(KAYRA_SRC),build) ## Render, build if kayra.src is set, then start the stack
	$(COMPOSE) up -d
	@# compose recreates a service whose image, ports or environment changed,
	@# not one whose mounted file did: Kayra's configuration, its users, the
	@# routes. Recreate those when one changed since the last up.
	@if [ -f $(DEV_DIR)/.up ] && [ -n "$$(find $(DEV_DIR)/kayra.yaml $(DEV_DIR)/users.yaml $(DEV_DIR)/routes -newer $(DEV_DIR)/.up)" ]; then \
		echo "up: $(DEV_CONFIG) changed: recreating kayra, reconciler and gateway-init"; \
		$(COMPOSE) up -d --force-recreate --no-deps kayra reconciler gateway-init; \
	fi
	@touch $(DEV_DIR)/.up
	@echo; echo "  Kayra   http://localhost:$(KAYRA_PORT)   gateway $(GATEWAY)   APISIX Admin API $(ADMIN_URL)"
	@echo "  next:   make contexts"

down: ## Stop the stack, keep etcd's data
	$(COMPOSE) down

clean: ## Stop the stack and wipe etcd: Kayra's objects and APISIX's routes (see Reset)
	$(COMPOSE) down -v

reset-kayra: ## Wipe Kayra's objects only (namespaces, APIs, RBAC...), keep the routes and keys
	$(COMPOSE) exec -T etcd etcdctl del --prefix /kayra
	$(COMPOSE) restart kayra reconciler

restart: ## Restart SERVICE, or every service
	$(COMPOSE) restart $(SERVICE)

ps: ## List the stack's containers
	$(COMPOSE) ps

logs: ## Follow the logs of SERVICE (kayra, reconciler, apisix...), or all
	$(COMPOSE) logs -f $(SERVICE)

health: ## Check Kayra and the gateway answer
	@curl -fsS http://localhost:$(KAYRA_PORT)$(KAYRA_HEALTHZ) && echo "  kayra"
	@curl -fsS $(GATEWAY)/healthz && echo "  gateway"

routes: ## Load the stack's APISIX routes back as they were
	$(COMPOSE) run --rm gateway-init

# ---------------------------------------------------------------- tokens

token: ## Print a token for SUBJECT (a user of dev.yaml: jdoe, nobody...) from the local provider
	@$(COMPOSE) exec -T kayra kayra token mint --provider local --subject $(SUBJECT) --ttl 8h

contexts: ## Save dev-admin, dev-jdoe and dev-nobody as infrapi-cli contexts, on the gateway
	@set -e; \
	admin=$$($(COMPOSE) exec -T kayra kayra token mint --provider self --group $(SYSADMIN_GROUP) --ttl 8h); \
	jdoe=$$($(COMPOSE) exec -T kayra kayra token mint --provider local --subject jdoe --ttl 8h); \
	nobody=$$($(COMPOSE) exec -T kayra kayra token mint --provider local --subject nobody --ttl 8h); \
	$(INFRAPI_CLI) context set dev-nobody --server $(GATEWAY) --token "$$nobody"; \
	$(INFRAPI_CLI) context set dev-jdoe   --server $(GATEWAY) --token "$$jdoe"; \
	$(INFRAPI_CLI) context set dev-admin  --server $(GATEWAY) --token "$$admin"
	@echo; echo "  next:   make kickstart, for dev.yaml's APIs and tenants"

kickstart: ## Create dev.yaml's APIs and tenants in Kayra, as dev-admin, and sync
	$(INFRAPI_CLI) dev apply --config $(DEV_CONFIG) --server $(GATEWAY)

# --------------------------------------------------------------- your API

api-add: ## Route API through APISIX to UPSTREAM (default: the example, dev.yaml's example)
	$(INFRAPI_CLI) dev api add --config $(DEV_CONFIG) $(API) $(UPSTREAM)

api-rm: ## Remove API's route
	$(INFRAPI_CLI) dev api rm --config $(DEV_CONFIG) $(API)

example: $(DEV_DIR)/env ## Run the example API on the host (LIB_SRC=../lib: against a lib checkout)
ifeq ($(LIB_SRC),)
	cd $(EXAMPLE) && INFRAPI_CONFIG_DOTENV_FILE=$(CURDIR)/$(DEV_DIR)/example.env go run .
else
	@mkdir -p $(BIN)
	rm -f $(BIN)/go.work && cd $(BIN) && go work init $(abspath $(EXAMPLE)) $(abspath $(LIB_SRC))
	cd $(EXAMPLE) && INFRAPI_CONFIG_DOTENV_FILE=$(CURDIR)/$(DEV_DIR)/example.env GOWORK=$(BIN)/go.work go run .
endif

check: ## Lint the scripts, build the example
	sh -n apisix/routes.sh
	cd $(EXAMPLE) && go vet ./... && go build -o /dev/null .
