---
title: The dev stack
description: dev init, dev.yaml, the services, Kayra's configuration and users, the infrapi-cli contexts, the kickstart, the gateway's routes, the make targets, and how to reset.
weight: 20
---

# The dev stack

`infrapi-cli dev init <name>` creates one: it asks for the domain, the
platform, the region and Kayra's image, renders this repository's template
(`scaffold.yaml`, `{{ .Project }}/`) into `./<name>`, and writes the
answers into its `dev.yaml`. Every `make` command below runs in that
directory. See [infrapi-cli's dev](https://infrapi.github.io/cli/dev/) for
its flags (`--no-prompt`, `--set domain=...`, `--template`).

```bash
infrapi-cli dev init mystack
cd mystack
make up
```

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

## dev.yaml

`dev.yaml` is the stack's single source of truth. Every file the stack
runs with is rendered from it into `.infrapi-dev/` (gitignored):

| Setting | What it sets |
|---|---|
| `domain` | Kayra's `app.api_domain` (`infrapi.io`). Kayra's own groups are `system.<domain>`, `catalog.<domain>` and `authorization.<domain>`, and every API of `apis` without a dot is `<name>.<domain>` |
| `platform`, `region`, `location` | Kayra's and the example's (`sandbox`, `eu-west-1`, `dc1`). `platform` is `sandbox`, `preprod` or `prod`, as infrapi/lib takes it |
| `kayra.image` | the image Kayra and its reconciler run, `ghcr.io/infrapi/kayra:latest` |
| `kayra.src` | a Kayra checkout to build `kayra-dev:local` from instead (`make build`), `kayra.image` then ignored |
| `ports` | where the stack listens on `127.0.0.1` |
| `sysadmin_groups` | the groups Kayra's cluster endpoints require, `<platform>-core-sysadmin` by default. `make contexts` mints `dev-admin` with the first one |
| `users` | the users of Kayra's `local` provider, a stand-in for LDAP |
| `apis`, `tenants` | what `make kickstart` creates in Kayra |
| `example` | the example API, `compute`, and the host port it listens on, `8080` |

Edit it, then `make up`: `make` renders `.infrapi-dev/` again whenever
`dev.yaml` changes, and `make up` recreates Kayra, its reconciler and
`gateway-init` when their configuration, users or routes changed since the
last `make up`. `make render` renders it without starting anything.
`DEV_CONFIG=other.yaml make up` runs another file. An unknown key, a
malformed name, or a port used twice is refused before anything starts.

What `make render` writes, with `infrapi-cli dev render`:

| File | |
|---|---|
| `env` | the domain, image and ports, for `podman compose --env-file` and for the Makefile |
| `kayra.yaml`, `users.yaml` | Kayra's configuration and users, mounted into both Kayra services |
| `keys/*.pem` | the signing keys, generated once and kept |
| `routes/*.json` | the gateway's own routes, loaded by `gateway-init` |
| `example.env` | the example API's settings (`make example`) |

## Make targets

```text
make up           render .infrapi-dev/ from dev.yaml (build if kayra.src is set), start the stack
make render       render it alone; NEW_KEYS=1 for new signing keys
make build        build kayra-dev:local from kayra.src
make down         stop the stack, keep etcd's data
make clean        stop it and wipe etcd: Kayra's objects and APISIX's routes (see Reset)
make ps | logs    the containers; logs SERVICE=reconciler follows one
make health       Kayra and the gateway answer
make routes       load the stack's APISIX routes back as they were
make contexts     mint tokens, save them as infrapi-cli contexts on the gateway
make kickstart    create dev.yaml's APIs and tenants in Kayra, as dev-admin
make token        print a token, SUBJECT=jdoe by default
make api-add      route API (dev.yaml's example by default) to UPSTREAM through APISIX
make api-rm       remove API's route
make example      run the example API on the host (LIB_SRC=../lib: against a lib checkout)
make check        lint the scripts, build the example
```

With `kayra.src`, `make build` (and so `make up`) builds Kayra's image from
your checkout, with `podman build --build-context src=<kayra.src>`:
`podman compose` cannot pass a second build context, so the compose file
only names the image.

## Kayra's configuration

`.infrapi-dev/kayra.yaml` is a complete Kayra configuration, rendered from
`dev.yaml` and a template embedded in `infrapi-cli`. Both Kayra
services mount it at `/etc/kayra/kayra.yaml`. Nothing in it reaches
outside the stack's network: no OIDC provider, no LDAP, no proxy.

Two authentication providers, both `local`: tokens signed by keys Kayra
holds itself. The keys are generated by the first `make render`, kept in
`.infrapi-dev/keys/`, never committed, and reused by every render after:
saved contexts keep working across `make up`. `make render NEW_KEYS=1`
(or `make up NEW_KEYS=1`) generates new ones, and every token minted
before is then refused: run `make contexts` again (see [Reset](#reset)).

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
`kayra` container. Edit a user's groups in `dev.yaml`, then `make up`: the
next request sees the change once the users cache lets it go
(`kayra cache clean --scope users`).

### Contexts

`make contexts` mints three tokens and saves them as `infrapi-cli` contexts,
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

`make kickstart` creates `dev.yaml`'s `apis` and `tenants` in Kayra, as
`dev-admin` (`infrapi-cli dev apply`):

| What | |
|---|---|
| APIs | each of `apis`: `<name>.<domain>`, its `owner`, its `version` (`v1` unless set), its name's first label as short name. By default `dev`, `compute`, `puppet`, `objectstorage` (owner `sre-a`) and `telemetry` (`sre-b`) |
| Tenants | each of `tenants`: the namespace, its `admins`' cluster RBAC on `catalog.<domain>` and `authorization.<domain>`, a read-write role in the namespace. By default `core` and `sre`, run by `sandbox-core-sysadmin` |
| Subscriptions | each tenant to its `subscriptions`: `all`, or a list of APIs |
| Sync | a first sync of every API, which the reconciler carries out |

```bash
make kickstart
# apply: api dev.infrapi.io v1
# …
# apply: tenant core (dev.infrapi.io, compute.infrapi.io, puppet.infrapi.io, objectstorage.infrapi.io, telemetry.infrapi.io)
```

It reads Kayra's groups from its `/.well-known/kayra.json`, and stops if
Kayra's domain is not `dev.yaml`'s (run `make up` after changing
`domain`). You can run it again: Kayra's creates are upserts, and a
subscription that exists already is left as it is, not reset to `init`.
An API has the `openapi-stub`'s spec (one resource, `widgets`) until it
gets a route of its own with `make api-add`.

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
`make api-add` routes `dev.yaml`'s example API to the host, or
`make api-add API=<api> UPSTREAM=<host:port>` another one (`<api>` is
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

Routes live in etcd: they survive restarts, and go with `make clean`.

## The reconcile pipeline

Every API registration without a `mode` of its own runs the `dev` mode of
Kayra's configuration, after the reconciler stored the API's spec:

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

## Reset

From the lightest to the most thorough. Each one starts from a running
stack.

### Kayra's objects only

This wipes namespaces, API registrations, subscriptions, RBAC, specs,
Kayra's token caches and its personal access token key. The restart
creates a new PAT key, so earlier personal access tokens stop working,
while tokens from `make contexts` keep working. It keeps APISIX's routes
(yours from `make api-add` too), the signing keys and your contexts:

```bash
podman compose --env-file .infrapi-dev/env -f compose.yaml exec etcd etcdctl del --prefix /kayra
make restart SERVICE="kayra reconciler"
make kickstart          # optional: dev.yaml's APIs and tenants again
```

### The stack's data

`make clean` stops the stack and removes the `etcd-data` volume: Kayra's
objects and APISIX's routes, the ones `make api-add` added included.
`make up` starts it again on an empty etcd. `gateway-init` loads the
stack's own routes back, and the signing keys are the same, so your
contexts keep working. Personal access tokens do not: their key was in
etcd.

```bash
make clean
make up
make kickstart          # optional
make api-add            # your API's route, if you had added it
```

### New signing keys

Do this when the keys may have leaked, or to check that a stale token is
refused. It renders Kayra's configuration with new keys, and every token
minted before, saved contexts included, gets a 401:

```bash
make clean
make up NEW_KEYS=1
make contexts           # tokens signed with the new keys
make kickstart          # optional
```

### Everything the stack leaves on your machine

```bash
for c in dev-admin dev-jdoe dev-nobody; do infrapi-cli context delete $c; done
make clean
podman rmi kayra-dev:local      # if you built it from kayra.src
rm -rf bin .infrapi-dev
```

`make contexts` saved the `dev-*` contexts in `~/.config/infrapi/config`, or
in `INFRAPI_CONTEXT_FILE`, beside your other contexts. The first line
removes only those three.

## Change Kayra's configuration

What `dev.yaml` does not cover, the reconcile pipeline say, is in the
template `infrapi-cli dev render` renders Kayra's configuration from,
[`internal/dev/templates/kayra.yaml.tmpl`](https://github.com/infrapi/cli/blob/main/internal/dev/templates/kayra.yaml.tmpl)
in infrapi-cli: a Go template with `[[ ]]` delimiters, so Kayra's own
`{{ .Subscription... }}` stay as they are. Change it there, then
`make up` with that `infrapi-cli`: `.infrapi-dev/kayra.yaml` is rendered
again with the same keys, and both Kayra services recreated.
