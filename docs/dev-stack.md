---
title: The dev stack
description: The services, Kayra's configuration and users, the kayra-cli contexts, the gateway's routes, and the make targets.
weight: 20
---

# The dev stack

| Service | What it is | On the host |
|---|---|---|
| `etcd` | single-node etcd 3.6: Kayra's store under `/kayra`, APISIX's under `/apisix` | `127.0.0.1:2379` |
| `kayra` | `kayra serve` | `127.0.0.1:8081` |
| `reconciler` | `kayra reconciler`, same image and configuration | - |
| `apisix` | APISIX 3.19, the gateway in front of Kayra and of your APIs | `127.0.0.1:9080`; Admin API and UI `127.0.0.1:9180`; control API `127.0.0.1:9092`; prometheus `127.0.0.1:9091` |
| `gateway-init` | loads APISIX's routes, then exits | - |
| `httpbin` | an upstream to try routes and plugins on | through APISIX, `/httpbin/*` |

Every port is bound to `127.0.0.1`: the stack's keys are known.

## Make targets

```text
make up           build kayra-dev:local from KAYRA_SRC (../kayra), start the stack
make down         stop it, keep etcd's data
make clean        stop it and wipe etcd: Kayra's objects and APISIX's routes
make ps | logs    the containers; logs SERVICE=reconciler follows one
make health       Kayra and the gateway answer
make routes       load the stack's APISIX routes back as they were
make cli          build kayra-cli into bin/
make contexts     mint tokens, save them as kayra-cli contexts on the gateway
make token        print a token, SUBJECT=jdoe by default
make api-add      route API to UPSTREAM through APISIX
make api-rm       remove API's routes
make example      run the example API on the host (LIB_SRC=../lib: against a lib checkout)
make check        lint the scripts, build the example
```

`make build` (and so `make up`) builds Kayra's image from your checkout,
with `podman build --build-context src=$KAYRA_SRC`: `podman compose`
cannot pass a second build context, so the compose file only names the
image. `--format docker` keeps the image's `HEALTHCHECK`.

## Kayra's configuration

`kayra/kayra.yaml.tmpl` is a complete Kayra configuration, rendered into
the image by `kayra/render-config.sh`, with `app.api_domain: infrapi.io`:
Kayra's API groups are `system.infrapi.io`, `catalog.infrapi.io`,
`authorization.infrapi.io`, and yours `<name>.infrapi.io`. Platform
`sandbox`, region `eu-west-1`.

Two authentication providers, both `local`: tokens signed by keys Kayra
holds itself. The keys are generated when the image is built, never
committed, so a token minted with one build is refused by the next: run
`make contexts` again after `make build`.

| Provider | Groups come from | Mint with |
|---|---|---|
| `self` | the token's own `groups` claim | `kayra token mint --provider self --group <group>...` |
| `local` | `kayra/users.yaml`, by the token's subject, as LDAP would | `kayra token mint --provider local --subject <id>` |

`sysadmin.groups` is `sandbox-core-sysadmin`: the group Kayra's cluster
endpoints (namespaces, API registrations, cluster RBAC) require.

### Users

`kayra/users.yaml`, copied into the image:

| User | Groups |
|---|---|
| `admin` | `sandbox-core-sysadmin` |
| `jdoe` | `sandbox-thetenant-admins` |
| `nobody` | none |

There is no password login, the `password` fields are unused: tokens come
from `kayra token mint`, in the `kayra` container.

### Contexts

`make contexts` mints three tokens and saves them as `kayra-cli` contexts,
pointing at the gateway, so one server serves Kayra's API and yours:

| Context | Token |
|---|---|
| `dev-admin` (current) | provider `self`, group `sandbox-core-sysadmin` |
| `dev-jdoe` | provider `local`, subject `jdoe` |
| `dev-nobody` | provider `local`, subject `nobody` |

They go to `kayra-cli`'s own file, `~/.config/kayra/config`, beside your
other contexts (`KAYRA_CONTEXT_FILE` to keep them apart). For `curl`, take
a context's token:

```bash
ADMIN=$(kayra-cli context token dev-admin)
JDOE=$(kayra-cli context token dev-jdoe)
```

**kayra-cli**

```bash
kayra-cli auth whoami --context dev-jdoe
# authorization:  users
# email:          jdoe@infrapi.io
# groups:         sandbox-thetenant-admins
# name:           John Doe
# provider:       local
# sub:            jdoe
```

**curl**

```bash
curl -s -X POST http://localhost:9080/oauth2/userinfo -H "Authorization: Bearer $JDOE"
# {"authorization":"users","email":"jdoe@infrapi.io","groups":["sandbox-thetenant-admins"],"name":"John Doe","provider":"local","sub":"jdoe"}
```

## The gateway

APISIX runs in traditional mode, `apisix/config.yaml`: its routes are in
etcd. `gateway-init` loads the stack's own at start, from
`apisix/routes.sh`:

| Route | Matches | Goes to |
|---|---|---|
| `kayra` | `/apis`, `/oauth2/*`, `/apis/{system,catalog,authorization}.infrapi.io/*` | `kayra:8081` |
| `openapi-stub` | `GET /apis/<api>/-/openapi.json`, for an API with no route of its own | an OpenAPI document with one resource, `widgets` (`apisix/openapi-stub.lua`) |
| `hooks` | `/hooks/*` | `{"status":"done"}`: the reconcile pipeline's answer |
| `healthz` | `GET /healthz` | `{"status":"ok"}` |
| `httpbin` | `/httpbin/*` | the `httpbin` service |

An API you develop gets two routes of its own, from `apisix/add-api.sh`
(`make api-add API=<api> UPSTREAM=<host:port>`), matched before the stub:

| Route | Matches | Goes to |
|---|---|---|
| `<api>-openapi` | `GET /apis/<api>/-/openapi.json` | `<upstream>/-/openapi.json`, the spec Kayra reads |
| `<api>` | `/apis/<api>/*` | `<upstream>`, unchanged |

`host.containers.internal`, the default upstream's host, is the host as
podman resolves it in a container. Your API must listen on an address the
containers reach: `127.0.0.1` is not, `0.0.0.0` is.

Inspect them through the Admin API or its UI at
<http://localhost:9180/ui/>, with the admin key of `apisix/config.yaml`:

```bash
APISIX_KEY=podman-admin-api-key
curl -s http://localhost:9180/apisix/admin/routes -H "X-API-KEY: $APISIX_KEY" | jq '.list[].value | {id, uri, uris}'
curl -s http://localhost:9080/httpbin/get
```

Routes live in etcd: they survive restarts, and go with `make clean`.

## The reconcile pipeline

Every API registration without a `mode` of its own runs the `dev` mode
of `kayra/kayra.yaml.tmpl`, after the reconciler stored the API's spec:

1. `POST http://apisix:9080/hooks/<api>/namespaces/<namespace>/sync` with
   `{"sync_id": "<expected sync id>"}`
2. `GET http://apisix:9080/hooks/<api>/namespaces/<namespace>/sync/<sync id>`,
   polled until `.status` is `done` (success) or `failed`/`canceled`.

The `hooks` route answers `done` to both. To see a failed sync, make it
answer `failed`, then trigger a sync; `make routes` puts it back:

```bash
curl -s -X PATCH http://localhost:9180/apisix/admin/routes/hooks -H "X-API-KEY: $APISIX_KEY" \
  -d '{"plugins": {"mocking": {"response_status": 200, "content_type": "application/json", "response_example": "{\"status\":\"failed\"}"}}}'
```

## Change Kayra's configuration

To change anything else in it, the pipeline included, copy it out of the
image, keys included, and mount it back into both Kayra services:

```bash
podman compose -f compose.yaml cp kayra:/etc/kayra/kayra.yaml kayra.local.yaml
```

```yaml title="compose.override.yaml"
services:
  kayra:
    volumes: ["./kayra.local.yaml:/etc/kayra/kayra.yaml:ro,z"]
  reconciler:
    volumes: ["./kayra.local.yaml:/etc/kayra/kayra.yaml:ro,z"]
```

then `make up COMPOSE="podman compose -f compose.yaml -f compose.override.yaml"`.
`kayra.local.yaml` holds the signing keys: it is gitignored, keep it out
of commits.
