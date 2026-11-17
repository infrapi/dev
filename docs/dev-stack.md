---
title: The dev stack
description: How a dev stack works once it runs - what is in it, the everyday commands, dev.yaml, users and tokens, the gateway, how to start over, and how to go further.
weight: 30
---

# The dev stack

How the stack you created in [Getting started](getting-started.md) works,
and how to change it. Read [Create an API](create-an-api.md) first: this
page explains what you used there. The commands use
[infrapi-cli](https://infrapi.github.io/cli/getting-started/#1-install) and
run from the stack's directory, or any directory below it.

## The big picture

```text
infrapi-cli, curl
       │
       ▼
gateway (APISIX) :9080 ────────────────────► Kayra :8081 ──► etcd :2379
       │                                       ▲     ▲
       ▼                                       │     └── reconciler
your API, on your machine :8080 ───────────────┘
                     asks Kayra who calls, and what they may do
```

- You call **the gateway**, at `http://localhost:9080`, for everything:
  Kayra's API and yours.
- **Kayra** says who the caller is and what they may do. Your API asks it on
  every request.
- **The reconciler**, Kayra's other half, syncs each tenant subscribed to
  your API. It reads your API's spec through the gateway.
- **etcd** stores Kayra's objects and the gateway's routes.

Everything comes from one file, `dev.yaml`. `infrapi-cli dev up` turns it
into the files the containers run with, in `.infrapi-dev/`, then starts
them.

## What runs

| Container | What it is | On your machine |
|---|---|---|
| `kayra` | Kayra's API: identity, namespaces, RBAC, API catalog | `127.0.0.1:8081` |
| `reconciler` | Kayra's reconciler, same image and configuration | - |
| `apisix` | the gateway | `127.0.0.1:9080`; its Admin API and UI `127.0.0.1:9180` |
| `etcd` | the store of Kayra (`/kayra`) and of the gateway (`/apisix`) | `127.0.0.1:2379` |
| `gateway-init` | loads the gateway's routes at start, then exits | - |
| `httpbin` | an upstream to try gateway routes on | through the gateway, `/httpbin/*` |

Every port is bound to `127.0.0.1` only: the stack's keys are known, nothing
should reach it from outside. The ports are `dev.yaml`'s, these are the
defaults.

## Everyday commands

| I want to... | Run |
|---|---|
| check what is needed is installed | `infrapi-cli dev doctor` |
| start the stack | `infrapi-cli dev up` |
| see what a change to `dev.yaml` does, then apply it | `infrapi-cli dev render`, then `infrapi-cli dev up --force` |
| see if it answers | `infrapi-cli dev health` |
| see the containers, follow their logs | `infrapi-cli dev ps`, `infrapi-cli dev logs [kayra]` |
| restart a container | `infrapi-cli dev restart kayra` |
| get tokens, as `infrapi-cli` contexts | `infrapi-cli dev contexts` |
| print one user's token | `infrapi-cli dev token --subject jdoe` |
| run the example API | `infrapi-cli dev example` |
| route my API through the gateway, or stop | `infrapi-cli dev api add`, `infrapi-cli dev api rm` |
| stop the stack, keeping its data | `infrapi-cli dev down` |
| start over | see [Start over](#start-over) |

`infrapi-cli dev --help` lists them all, and
[infrapi-cli's dev](https://infrapi.github.io/cli/dev/) details each one.
Every command prints what it runs, `+ podman compose ... up -d` say.

## Change the stack: dev.yaml

`dev.yaml` is the only file you edit. Change it, then:

1. `infrapi-cli dev render` shows what the change does to the files the
   stack runs with, as a diff, and writes nothing;
2. `infrapi-cli dev up --force` writes them, and restarts what needs it.

`infrapi-cli dev up` alone never changes those files: when they differ
from what `dev.yaml` renders, it shows the diff and stops.

| Setting | What it is | Default |
|---|---|---|
| `domain` | Kayra's API domain: its own groups are `system.<domain>`, `catalog.<domain>` and `authorization.<domain>`, and the example API is `compute.<domain>` | `infrapi.io` |
| `platform`, `region`, `location` | where Kayra and the example API say they run; `platform` is `sandbox`, `preprod` or `prod` | `sandbox`, `eu-west-1`, `dc1` |
| `kayra.image` | the Kayra release the stack runs | `ghcr.io/infrapi/kayra:latest` |
| `kayra.src` | a Kayra checkout to run instead of the image, see [Going further](#run-kayra-from-a-checkout) | unset |
| `ports` | where the stack listens | `8081`, `9080`, `9180`... |
| `sysadmin_groups` | the groups Kayra's cluster endpoints require: namespaces, API registrations, cluster RBAC | `sandbox-core-sysadmin` |
| `users` | the users you can be, see [Users and tokens](#users-and-tokens) | `admin`, `jdoe`, `nobody` |
| `example` | the example API: its name and the port it listens on, on your machine | `compute`, `8080` |

A mistake is caught before anything starts: an unknown key, a malformed
name, a platform infrapi/lib does not take, a port used twice.

What `dev up` writes into `.infrapi-dev/` (gitignored), from `dev.yaml`:

| File | |
|---|---|
| `kayra.yaml`, `users.yaml` | Kayra's configuration and its users, read by both Kayra containers |
| `keys/*.pem` | the keys Kayra signs tokens with: created once, then kept |
| `routes/*.json` | the gateway's own routes |
| `env` | the domain, image and ports, for compose |
| `example.env` | the example API's settings |

Don't edit them: they are rendered from `dev.yaml`, and an edit made by
hand is lost at the next `--force`. A render that would change one, from
your edit or from `dev.yaml`, is canceled: it prints the diff, says which
setting of `dev.yaml` the file comes from, and writes nothing. `--force`
writes it.

```bash
infrapi-cli dev up
# --- a/kayra.yaml
# +++ b/kayra.yaml
# -  max_concurrent_reconciles: 50
# +  max_concurrent_reconciles: 5
#
# render canceled: nothing written to …/compute/.infrapi-dev: it differs from what dev.yaml renders, the diff above.
#
#   The files in .infrapi-dev are rendered from dev.yaml: change dev.yaml, not them. Each file, from dev.yaml's:
#     kayra.yaml   domain, platform, region, location, sysadmin_groups, ports.kayra, users; anything else: kayra.config
#
#   To keep what .infrapi-dev has, an edit made by hand say, add this to dev.yaml:
#
#     kayra:
#       config:
#         reconciler:
#           max_concurrent_reconciles: 50
#
#   Then, or to write dev.yaml's change as it is:
#     infrapi-cli dev up --force   (or infrapi-cli dev render --force)
```

Whatever you would edit there goes in `dev.yaml` instead: see
[Override anything](#override-anything). `dev init` renders the files
once, so the first `infrapi-cli dev up` has nothing to ask. The other commands (`ps`, `logs`, `down`, `contexts`...)
run on the files as they are, with a warning when they differ from
`dev.yaml`.

### Override anything

Every file in `.infrapi-dev/` takes overrides from `dev.yaml`, merged the
same way: a map key by key, a list or a value replaced as a whole, `null`
removing the key.

| File | Override in `dev.yaml` |
|---|---|
| `kayra.yaml` | `kayra.config`, merged into Kayra's configuration; the template's comments stay |
| `routes/*.json` | `gateway.routes.<id>`, merged into the route `<id>` as APISIX's Admin API takes it; a new id is a new route, `null` removes one |
| `example.env` | `example.env`, variables replaced or added |
| `env` | `compose.env`, variables replaced or added, for `compose.yaml` to read (`${MY_VAR}`) |
| `keys/*.pem` | `kayra.keys.self`, `kayra.keys.local`: key files of your own, relative to `dev.yaml` |
| `users.yaml` | `users` |

```yaml
kayra:
  config:
    reconciler:
      max_concurrent_reconciles: 50
gateway:
  routes:
    hooks:                      # the reconcile hooks answer "failed"
      plugins:
        mocking:
          response_example: '{"status":"failed"}'
    mine:                       # a route of your own
      uri: /mine/*
      upstream: {type: roundrobin, nodes: {"host.containers.internal:9000": 1}}
    httpbin: null               # removed, from the gateway too
example:
  api: compute
  port: 8080
  env:
    INFRAPI_APP_LOG_LEVEL: debug
compose:
  env:
    MY_VAR: value
```

Then `infrapi-cli dev render` shows the diff, and `infrapi-cli dev up
--force` applies it. A route set to `null` is deleted from the gateway
too, when `gateway-init` runs, or by `infrapi-cli dev routes`. A route
only taken out of `dev.yaml` stays in the gateway until
`infrapi-cli dev clean`: set it to `null` instead.

The files beside `dev.yaml` are yours, not rendered: edit `compose.yaml`,
`apisix/config.yaml` or `apisix/routes.sh` as you need. A
`compose.override.yaml` beside `compose.yaml` is read too, a service of
your own say: infrapi-cli adds it to compose's files.

## Users and tokens

The stack has no identity provider: Kayra signs its tokens itself, with the
keys in `.infrapi-dev/keys/`. There is no password and no
`infrapi-cli login` here, the tokens come from Kayra directly.

The users are `dev.yaml`'s, a stand-in for a company directory: Kayra
reads a token's groups from there.

| User | Groups | Who it plays |
|---|---|---|
| `admin` | `sandbox-core-sysadmin` | the platform's administrator |
| `jdoe` | `sandbox-thetenant-admins` | a tenant's user: allowed what the tenant's RBAC grants that group |
| `nobody` | none | someone authenticated, authorized for nothing |

`infrapi-cli dev contexts` gets a token for each, valid 8 hours, and saves
it as an infrapi-cli context on the gateway: `dev-jdoe`, `dev-nobody`, and
`dev-admin`, a sysadmin, which becomes the current one. Run it again when
the tokens expire. Use one context for a single command with
`--context`:

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
JDOE=$(infrapi-cli context token dev-jdoe)
curl -s -X POST http://localhost:9080/oauth2/userinfo -H "Authorization: Bearer $JDOE"
# {"authorization":"users","email":"jdoe@example.com","groups":["sandbox-thetenant-admins"],"name":"John Doe","provider":"local","sub":"jdoe"}
```

To add a user or change their groups, edit `users` in `dev.yaml`, run
`infrapi-cli dev up --force`, then `infrapi-cli dev contexts`. The contexts live in
`~/.config/infrapi/config`, beside your others (`INFRAPI_CONTEXT_FILE` to
keep them apart).

## The gateway

Every call goes through the gateway, APISIX. Its routes decide where a
request goes. The stack loads its own at start:

| Route | Matches | Goes to |
|---|---|---|
| `kayra` | `/apis`, `/oauth2/*`, `/.well-known/kayra.json` and `api.json`, `/apis/{system,catalog,authorization}.<domain>/*` | Kayra |
| `openapi-stub` | an API's spec, `GET /apis/<api>/<version>/-/openapi.json`, for an API with no route yet | a stand-in spec, one resource, `widgets` |
| `hooks` | `/hooks/*` | always `{"status":"done"}`: what the reconciler calls to sync a tenant |
| `healthz` | `GET /healthz` | `{"status":"ok"}` |
| `httpbin` | `/httpbin/*` | the `httpbin` container |

Your API gets a route of its own with `infrapi-cli dev api add`:
`/apis/<api>/*` to your API on your machine, its spec included. The
containers reach your machine as `host.containers.internal` (podman) or
`host.docker.internal` (docker). So your API must listen on `0.0.0.0`, not
`127.0.0.1`. `infrapi-cli dev api add <api> <host:port>` routes another
API, and `infrapi-cli dev api rm` removes the route.

To look at the routes, open the Admin API's UI at
<http://localhost:9180/ui/>, or:

```bash
curl -s http://localhost:9180/apisix/admin/routes -H "X-API-KEY: podman-admin-api-key" | jq '.list[].value | {id, uri, uris}'
```

The routes are kept in etcd. `infrapi-cli dev routes` puts the stack's own
back as they were.

## Start over

| I want to | Run | What is kept |
|---|---|---|
| remove what I created in Kayra: namespaces, API registrations, subscriptions, RBAC | `infrapi-cli dev reset-kayra` | the routes, the keys, your contexts |
| wipe all the stack's data | `infrapi-cli dev clean`, then `infrapi-cli dev up` | the keys and your contexts; run `infrapi-cli dev api add` again for your API's route |
| make every token invalid, new keys | `infrapi-cli dev clean`, `infrapi-cli dev up --new-keys --force`, then `infrapi-cli dev contexts` | nothing of the tokens: every earlier one gets a 401 |
| remove the stack from my machine | see below | your other contexts |

`reset-kayra` and `clean` also invalidate personal access tokens: their key
is stored in etcd. The tokens from `infrapi-cli dev contexts` keep working.

To remove everything the stack left on your machine:

```bash
for c in dev-admin dev-jdoe dev-nobody; do infrapi-cli context delete $c; done
infrapi-cli dev clean
podman rmi kayra-dev:local      # only if you ran Kayra from a checkout; docker rmi with docker
cd .. && rm -rf compute
```

## Going further

### Docker, podman, or another engine

The stack runs on podman when it is installed, docker otherwise. To pick
one, add `--engine docker` to a command, or `export ENGINE=docker` for good.

| | podman | docker |
|---|---|---|
| compose | `podman compose`, with `podman-compose` or `docker-compose` installed | the compose plugin, `docker compose` |
| your machine, seen from the containers | `host.containers.internal` | `host.docker.internal`, added by the stack's `compose.docker.yaml` on Linux |

For another engine, replace the commands themselves. Every `infrapi-cli dev`
command takes these flags, or their environment variables:

| Flag | Variable | Replaces | Default |
|---|---|---|---|
| `--engine` | `ENGINE` | the engine | podman when installed, docker otherwise |
| `--compose` | `COMPOSE` | the compose command; the stack's `--env-file` and `-f` files are added to it | `<engine> compose` |
| `--build-command` | `BUILD` | the image build command | `podman build --format docker`, or `docker build` |
| `--host-alias` | `HOST_ALIAS` | your machine's name in the containers | `host.containers.internal`, or `host.docker.internal` |
| `--config` | `DEV_CONFIG` | the stack's `dev.yaml` | `dev.yaml` here or in a parent directory |

For example, `infrapi-cli dev up --compose "nerdctl compose" --host-alias host.lima.internal`.

### Run Kayra from a checkout

Set `kayra.src` in `dev.yaml` to a Kayra checkout, `../kayra` say, relative
to the stack. `infrapi-cli dev up --force` then builds the image `kayra-dev:local`
from it (`infrapi-cli dev build` builds it alone), and runs it instead of
`kayra.image`.

### Kayra's configuration

`.infrapi-dev/kayra.yaml` is rendered from `dev.yaml` and a template
embedded in infrapi-cli,
[`internal/dev/templates/kayra.yaml.tmpl`](https://github.com/infrapi/cli/blob/main/internal/dev/templates/kayra.yaml.tmpl),
then `kayra.config` is merged in: see [Override anything](#override-anything).
The reconcile pipeline, say, is `kayra.config.reconciler.mode.dev`.
`infrapi-cli dev up --force` renders it again, with the same keys, and
restarts both Kayra containers.

Kayra has two token providers, both signing with the stack's keys:

| Provider | Groups come from | Mint by hand, in the `kayra` container |
|---|---|---|
| `self` | the token itself | `kayra token mint --provider self --group <group>` |
| `local` | `dev.yaml`'s `users` | `kayra token mint --provider local --subject <id>` |

### The reconcile pipeline

When a tenant subscribes to an API, or the API's registration changes, the
reconciler fetches the API's spec through the gateway, then runs the `dev`
pipeline of Kayra's configuration:

1. `POST http://apisix:9080/hooks/<api>/namespaces/<namespace>/sync`, with
   `{"sync_id": "<expected sync id>"}`;
2. `GET http://apisix:9080/hooks/<api>/namespaces/<namespace>/sync/<sync id>`,
   until `.status` is `done`, or `failed`/`canceled`.

The `hooks` route answers `done` to both. To see a failed sync, make it
answer `failed`, then trigger a sync. `infrapi-cli dev routes` puts it back
afterwards:

```bash
curl -s -X PATCH http://localhost:9180/apisix/admin/routes/hooks -H "X-API-KEY: podman-admin-api-key" \
  -d '{"plugins": {"mocking": {"response_status": 200, "content_type": "application/json", "response_example": "{\"status\":\"failed\"}"}}}'
```
