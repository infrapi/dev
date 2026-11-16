---
title: The dev stack
description: dev init, dev.yaml, the services, the commands, the container engine, Kayra's configuration and users, the infrapi-cli contexts, the kickstart, the gateway's routes, and how to reset.
weight: 20
---

# The dev stack

The reference of a stack created by `infrapi-cli dev init`: what runs, how
it is configured, the commands, how to reset it. To create and start one
first, follow [Getting started](getting-started.md). Every command runs in
the stack's directory, or any directory below it: `infrapi-cli dev` finds
`dev.yaml` there or in a parent. The commands use
[infrapi-cli](https://infrapi.github.io/cli/getting-started/#1-install).

| Service | What it is | On the host |
|---|---|---|
| `etcd` | single-node etcd 3.6: Kayra's store under `/kayra`, APISIX's under `/apisix` | `127.0.0.1:2379` |
| `kayra` | `kayra serve` | `127.0.0.1:8081` |
| `reconciler` | `kayra reconciler`, same image and configuration | - |
| `apisix` | APISIX 3.19, the gateway in front of Kayra and of your APIs | `127.0.0.1:9080`; Admin API and UI `127.0.0.1:9180`; control API `127.0.0.1:9092`; prometheus `127.0.0.1:9091` |
| `gateway-init` | loads APISIX's routes, then exits | - |
| `httpbin` | an upstream to try routes and plugins on | through APISIX, `/httpbin/*` |

Every port is bound to `127.0.0.1`: the stack's keys are known. The ports
above are `dev.yaml`'s defaults.

## Commands

`infrapi-cli dev --help` lists them, and
[infrapi-cli's dev](https://infrapi.github.io/cli/dev/) details each one.

| Command | What it does | How |
|---|---|---|
| `infrapi-cli dev doctor` | checks the prerequisites: podman or docker, its compose, go | runs `<engine> --version`, `<engine> compose version`, `go version` |
| `infrapi-cli dev up [--new-keys]` | renders `.infrapi-dev/` from `dev.yaml`, builds if `kayra.src` is set, starts the stack | `<engine> compose up -d`; recreates kayra, reconciler and gateway-init when what they read changed |
| `infrapi-cli dev render [--new-keys]` | renders `.infrapi-dev/` alone | Go |
| `infrapi-cli dev build` | builds `kayra-dev:local` from `kayra.src` | `podman build --format docker` or `docker build` |
| `infrapi-cli dev down` | stops the stack, keeps etcd's data | `compose down` |
| `infrapi-cli dev clean` | stops it and wipes etcd: Kayra's objects and APISIX's routes (see [Reset](#reset)) | `compose down -v` |
| `infrapi-cli dev reset-kayra` | wipes Kayra's objects only, keeps the routes and keys (see [Reset](#reset)) | `compose exec etcd etcdctl del --prefix /kayra`, then `compose restart kayra reconciler` |
| `infrapi-cli dev restart [service...]` | restarts services, or every one | `compose restart` |
| `infrapi-cli dev ps` | lists the containers | `compose ps` |
| `infrapi-cli dev logs [service...]` | follows the logs: `dev logs reconciler` follows one | `compose logs -f` |
| `infrapi-cli dev health` | checks Kayra and the gateway answer | Go, two GETs |
| `infrapi-cli dev routes` | puts the stack's own gateway routes back as they were | Go, APISIX's Admin API |
| `infrapi-cli dev contexts` | mints tokens, saves them as infrapi-cli contexts on the gateway | `compose exec kayra kayra token mint`, then Go |
| `infrapi-cli dev kickstart` | creates `dev.yaml`'s APIs and tenants in Kayra, as `dev-admin` (also `dev apply`) | Go, Kayra's API |
| `infrapi-cli dev token [--subject jdoe]` | prints a token for a user of `dev.yaml` | `compose exec kayra kayra token mint` |
| `infrapi-cli dev api add [api [upstream]]` | routes an API through the gateway, `dev.yaml`'s example on the host by default | Go, APISIX's Admin API |
| `infrapi-cli dev api rm [api]` | removes that route | Go, APISIX's Admin API |
| `infrapi-cli dev example [--lib-src ../lib]` | runs the example API on the host, against a lib checkout with `--lib-src` | `go run .` |
| `infrapi-cli dev check` | lints the stack's script, vets and builds the example | `sh -n`, `go vet`, `go build` |

Every command it runs is printed first, prefixed by `+`.

## The container engine

The stack runs on podman when it is installed, docker otherwise. Override
it for one command or for good:

```bash
infrapi-cli dev up --engine docker
export ENGINE=docker
```

| | podman | docker |
|---|---|---|
| compose | `podman compose`, with `podman-compose` or `docker-compose` | the compose plugin, `docker compose` |
| the host, seen from the containers | `host.containers.internal` | `host.docker.internal`, given by `compose.docker.yaml` on Linux |
| `infrapi-cli dev build` (`kayra.src`) | `podman build --format docker`, which keeps the healthcheck | `docker build`, BuildKit |

For anything else, replace the commands themselves, with a flag of
`infrapi-cli dev` or its environment variable:

| Flag | Variable | Replaces | Default |
|---|---|---|---|
| `--engine` | `ENGINE` | the engine | podman when installed, docker otherwise |
| `--compose` | `COMPOSE` | the compose command; the stack's `--env-file` and `-f` files are added to it | `<engine> compose` |
| `--build-command` | `BUILD` | the image build command | `podman build --format docker`, or `docker build` |
| `--host-alias` | `HOST_ALIAS` | the host's name in the containers | `host.containers.internal`, or `host.docker.internal` |
| `--config` | `DEV_CONFIG` | the stack's `dev.yaml` | `dev.yaml` here or in a parent directory |

For example, `infrapi-cli dev up --compose "nerdctl compose" --host-alias host.lima.internal`.

## dev.yaml

`dev.yaml` is the stack's single source of truth. Every file the stack
runs with is rendered from it into `.infrapi-dev/` (gitignored):

| Setting | What it sets |
|---|---|
| `domain` | Kayra's `app.api_domain` (`infrapi.io`). Kayra's own groups are `system.<domain>`, `catalog.<domain>` and `authorization.<domain>`, and every API of `apis` without a dot is `<name>.<domain>` |
| `platform`, `region`, `location` | Kayra's and the example's (`sandbox`, `eu-west-1`, `dc1`). `platform` is `sandbox`, `preprod` or `prod`, as infrapi/lib takes it |
| `kayra.image` | the image Kayra and its reconciler run, `ghcr.io/infrapi/kayra:latest` |
| `kayra.src` | a Kayra checkout to build `kayra-dev:local` from instead (`infrapi-cli dev build`), `kayra.image` then ignored; relative to the stack's directory |
| `ports` | where the stack listens on `127.0.0.1` |
| `sysadmin_groups` | the groups Kayra's cluster endpoints require, `<platform>-core-sysadmin` by default. `infrapi-cli dev contexts` mints `dev-admin` with the first one |
| `users` | the users of Kayra's `local` provider, a stand-in for LDAP; `dev contexts` saves `dev-<id>` for each, but `admin` |
| `apis`, `tenants` | what `infrapi-cli dev kickstart` creates in Kayra |
| `example` | the example API, `compute`, and the host port it listens on, `8080` |

Edit it, then `infrapi-cli dev up`. Every command renders `.infrapi-dev/`
from it first, and `dev up` recreates Kayra, its reconciler and
`gateway-init` when their configuration, users or routes changed: compose
would not, since only a file they mount changed. `infrapi-cli dev render`
renders it without starting anything. An unknown key, a malformed name, a
platform infrapi/lib does not take, or a port used twice is refused before
anything starts.

What the render writes:

| File | |
|---|---|
| `env` | the domain, image and ports, for `compose --env-file` |
| `kayra.yaml`, `users.yaml` | Kayra's configuration and users, mounted into both Kayra services |
| `keys/*.pem` | the signing keys, generated once and kept |
| `routes/*.json` | the gateway's own routes, loaded by `gateway-init` |
| `example.env` | the example API's settings (`infrapi-cli dev example`) |

With `kayra.src`, `infrapi-cli dev build` (and so `dev up`) builds Kayra's
image from your checkout, with `--build-context src=<kayra.src>`: compose
cannot pass a second build context, so the compose file only names the
image.

## Kayra's configuration

`.infrapi-dev/kayra.yaml` is a complete Kayra configuration, rendered from
`dev.yaml` and a template embedded in `infrapi-cli`. Both Kayra
services mount it at `/etc/kayra/kayra.yaml`. Nothing in it reaches
outside the stack's network: no OIDC provider, no LDAP, no proxy.

Two authentication providers, both `local`: tokens signed by keys Kayra
holds itself. The keys are generated by the first `infrapi-cli dev render`, kept in
`.infrapi-dev/keys/`, never committed, and reused by every render after:
saved contexts keep working across `infrapi-cli dev up`. `infrapi-cli dev render --new-keys`
(or `infrapi-cli dev up --new-keys`) generates new ones, and every token minted
before is then refused: run `infrapi-cli dev contexts` again (see [Reset](#reset)).

| Provider | Groups come from | Mint with |
|---|---|---|
| `self` | the token's own `groups` claim | `kayra token mint --provider self --group <group>...` |
| `local` | `dev.yaml`'s `users`, by the token's subject, as LDAP would | `kayra token mint --provider local --subject <id>` |

`sysadmin.groups` is `dev.yaml`'s `sysadmin_groups`, `sandbox-core-sysadmin`:
the group Kayra's cluster endpoints (namespaces, API registrations, cluster
RBAC) require.

### Users

`dev.yaml`'s `users`, rendered to `.infrapi-dev/users.yaml`:

| User | Groups |
|---|---|
| `admin` | `sandbox-core-sysadmin` |
| `jdoe` | `sandbox-thetenant-admins` |
| `nobody` | none |

There is no password login: tokens come from `kayra token mint`, in the
`kayra` container. Edit a user's groups in `dev.yaml`, then `infrapi-cli dev up`: the
next request sees the change once the users cache lets it go
(`kayra cache clean --scope users`).

### Contexts

`infrapi-cli dev contexts` mints three tokens and saves them as `infrapi-cli` contexts,
pointing at the gateway, so one server serves Kayra's API and yours:

| Context | Token |
|---|---|
| `dev-admin` (current) | provider `self`, the first of `sysadmin_groups` |
| `dev-jdoe` | provider `local`, subject `jdoe` |
| `dev-nobody` | provider `local`, subject `nobody` |

They go to `infrapi-cli`'s own file, `~/.config/infrapi/config`, beside your
other contexts (`INFRAPI_CONTEXT_FILE` to keep them apart). For `curl`, take
a context's token:

```bash
ADMIN=$(infrapi-cli context token dev-admin)
JDOE=$(infrapi-cli context token dev-jdoe)
```

**infrapi-cli**

```bash
infrapi-cli auth whoami --context dev-jdoe
# authorization:  users
# email:          jdoe@example.com
# groups:         sandbox-thetenant-admins
# name:           John Doe
# provider:       local
# sub:            jdoe
```

**curl**

```bash
curl -s -X POST http://localhost:9080/oauth2/userinfo -H "Authorization: Bearer $JDOE"
# {"authorization":"users","email":"jdoe@example.com","groups":["sandbox-thetenant-admins"],"name":"John Doe","provider":"local","sub":"jdoe"}
```

### Kickstart

`infrapi-cli dev kickstart` creates `dev.yaml`'s `apis` and `tenants` in Kayra, as
`dev-admin` (`infrapi-cli dev apply`):

| What | |
|---|---|
| APIs | each of `apis`: `<name>.<domain>`, its `owner`, its `version` (`v1` unless set), its name's first label as short name. By default `dev`, `compute`, `puppet`, `objectstorage` (owner `sre-a`) and `telemetry` (`sre-b`) |
| Tenants | each of `tenants`: the namespace, its `admins`' cluster RBAC on `catalog.<domain>` and `authorization.<domain>`, a read-write role in the namespace. By default `core` and `sre`, run by `sandbox-core-sysadmin` |
| Subscriptions | each tenant to its `subscriptions`: `all`, or a list of APIs |
| Sync | a first sync of every API, which the reconciler carries out |

```bash
infrapi-cli dev kickstart
# apply: api dev.infrapi.io v1
# …
# apply: tenant core (dev.infrapi.io, compute.infrapi.io, puppet.infrapi.io, objectstorage.infrapi.io, telemetry.infrapi.io)
```

It reads Kayra's groups from its `/.well-known/kayra.json`, and stops if
Kayra's domain is not `dev.yaml`'s (run `infrapi-cli dev up` after changing
`domain`). You can run it again: Kayra's creates are upserts, and a
subscription that exists already is left as it is, not reset to `init`.
An API has the `openapi-stub`'s spec (one resource, `widgets`) until it
gets a route of its own with `infrapi-cli dev api add`.

**infrapi-cli**

```bash
infrapi-cli get catalog -n core subscriptions
```

**curl**

```bash
curl -s http://localhost:9080/apis/catalog.infrapi.io/v1/namespaces/core/subscriptions -H "Authorization: Bearer $ADMIN"
```

## The gateway

APISIX runs in traditional mode, `apisix/config.yaml`: its routes are in
etcd. `gateway-init` loads the stack's own at start: `apisix/routes.sh`
PUTs each body of `.infrapi-dev/routes/`, rendered from `dev.yaml`.

| Route | Matches | Goes to |
|---|---|---|
| `kayra` | `/apis`, `/oauth2/*`, `/.well-known/kayra.json`, `/.well-known/api.json`, `/apis/{system,catalog,authorization}.<domain>/*` | `kayra:8081` |
| `openapi-stub` | `GET /apis/<api>/<version>/-/openapi.json`, for an API with no route of its own | an OpenAPI document with one resource, `widgets` (embedded in `infrapi-cli`) |
| `hooks` | `/hooks/*` | `{"status":"done"}`: the reconcile pipeline's answer |
| `healthz` | `GET /healthz` | `{"status":"ok"}` |
| `httpbin` | `/httpbin/*` | the `httpbin` service |

An API you develop gets a route of its own, matched before the stub:
`infrapi-cli dev api add` routes `dev.yaml`'s example API to the host, or
`infrapi-cli dev api add <api> <host:port>` another one (`<api>` is
`<name>.<domain>` without a dot).

| Route | Matches | Goes to |
|---|---|---|
| `<api>` | `/apis/<api>/*` | `<upstream>`, unchanged: the API, and its own endpoints under `/apis/<api>/<version>/-/`, the spec Kayra reads included |

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

Routes live in etcd: they survive restarts, and go with `infrapi-cli dev clean`.

## The reconcile pipeline

Every API registration without a `mode` of its own runs the `dev` mode of
Kayra's configuration, after the reconciler stored the API's spec:

1. `POST http://apisix:9080/hooks/<api>/namespaces/<namespace>/sync` with
   `{"sync_id": "<expected sync id>"}`
2. `GET http://apisix:9080/hooks/<api>/namespaces/<namespace>/sync/<sync id>`,
   polled until `.status` is `done` (success) or `failed`/`canceled`.

The `hooks` route answers `done` to both. To see a failed sync, make it
answer `failed`, then trigger a sync; `infrapi-cli dev routes` puts it back:

```bash
curl -s -X PATCH http://localhost:9180/apisix/admin/routes/hooks -H "X-API-KEY: $APISIX_KEY" \
  -d '{"plugins": {"mocking": {"response_status": 200, "content_type": "application/json", "response_example": "{\"status\":\"failed\"}"}}}'
```

## Reset

From the lightest to the most thorough. Each one starts from a running
stack.

### Kayra's objects only

This wipes namespaces, API registrations, subscriptions, RBAC, specs,
Kayra's token caches and its personal access token key. The restart
creates a new PAT key, so earlier personal access tokens stop working,
while tokens from `infrapi-cli dev contexts` keep working. It keeps APISIX's routes
(yours from `infrapi-cli dev api add` too), the signing keys and your contexts:

```bash
infrapi-cli dev reset-kayra        # etcdctl del --prefix /kayra, then restart kayra and reconciler
infrapi-cli dev kickstart          # optional: dev.yaml's APIs and tenants again
```

### The stack's data

`infrapi-cli dev clean` stops the stack and removes the `etcd-data` volume: Kayra's
objects and APISIX's routes, the ones `infrapi-cli dev api add` added included.
`infrapi-cli dev up` starts it again on an empty etcd. `gateway-init` loads the
stack's own routes back, and the signing keys are the same, so your
contexts keep working. Personal access tokens do not: their key was in
etcd.

```bash
infrapi-cli dev clean
infrapi-cli dev up
infrapi-cli dev kickstart          # optional
infrapi-cli dev api add            # your API's route, if you had added it
```

### New signing keys

Do this when the keys may have leaked, or to check that a stale token is
refused. It renders Kayra's configuration with new keys, and every token
minted before, saved contexts included, gets a 401:

```bash
infrapi-cli dev clean
infrapi-cli dev up --new-keys
infrapi-cli dev contexts           # tokens signed with the new keys
infrapi-cli dev kickstart          # optional
```

### Everything the stack leaves on your machine

```bash
for c in dev-admin dev-jdoe dev-nobody; do infrapi-cli context delete $c; done
infrapi-cli dev clean
podman rmi kayra-dev:local      # if you built it from kayra.src (docker rmi with docker)
rm -rf .infrapi-dev
```

`infrapi-cli dev contexts` saved the `dev-*` contexts in `~/.config/infrapi/config`, or
in `INFRAPI_CONTEXT_FILE`, beside your other contexts. The first line
removes only those three.

## Change Kayra's configuration

What `dev.yaml` does not cover, the reconcile pipeline say, is in the
template `infrapi-cli dev render` renders Kayra's configuration from,
[`internal/dev/templates/kayra.yaml.tmpl`](https://github.com/infrapi/cli/blob/main/internal/dev/templates/kayra.yaml.tmpl)
in infrapi-cli: a Go template with `[[ ]]` delimiters, so Kayra's own
`{{ .Subscription... }}` stay as they are. Change it there, then
`infrapi-cli dev up` with that `infrapi-cli`: `.infrapi-dev/kayra.yaml` is rendered
again with the same keys, and both Kayra services recreated.
