---
title: Getting started
description: Step by step, from nothing to a running local InfraPI - install infrapi-cli, check the prerequisites, scaffold the stack, start it, log in, and make a first call.
weight: 15
---

# Getting started

From nothing to a running local InfraPI, in seven steps. At the end, Kayra,
its reconciler, etcd and APISIX run in containers on your machine, and
you are logged in as their administrator.

1. [Install infrapi-cli](#1-install-infrapi-cli)
2. [Check the prerequisites](#2-check-the-prerequisites)
3. [Scaffold the stack](#3-scaffold-the-stack)
4. [Start it](#4-start-it)
5. [Log in](#5-log-in)
6. [Make a first call](#6-make-a-first-call)
7. [Next](#7-next)

## 1. Install infrapi-cli

`infrapi-cli` is InfraPI's command line. It creates the stack, runs it,
and is the client you call Kayra with: nothing else to install to drive the
stack, no `make`.

```bash
go install github.com/infrapi/cli/cmd/infrapi-cli@latest
infrapi-cli --version
```

Or take a release archive: see
[installing infrapi-cli](https://infrapi.github.io/cli/getting-started/#1-install).

## 2. Check the prerequisites

| What | Why | Check with |
|---|---|---|
| podman 4.7+ **or** docker, with compose | runs the stack's containers | `podman compose version`, or `docker compose version` |
| Go 1.27.3+ | only to run the example API (`infrapi-cli dev example`) | `go version` |
| `curl` | only for the `curl` examples of these docs | `curl --version` |

podman is used when it is installed, docker otherwise. To use docker
although podman is installed, add `--engine docker`, or set `ENGINE=docker`
(step 4). With podman, `podman compose` needs a compose provider:
`podman-compose`, or `docker-compose`.

Once the stack is scaffolded, `infrapi-cli dev doctor` checks all of this for you.

## 3. Scaffold the stack

```bash
infrapi-cli dev init mystack
```

It asks four questions. Enter keeps the default:

| Question | Default | What it sets |
|---|---|---|
| Domain | `infrapi.io` | Kayra's API domain. Its own groups are `system.<domain>`, `catalog.<domain>` and `authorization.<domain>`, and every API is `<name>.<domain>` |
| Platform | `sandbox` | Kayra's platform: `sandbox`, `preprod` or `prod` |
| Region | `eu-west-1` | Kayra's region |
| Kayra image | `ghcr.io/infrapi/kayra:latest` | the Kayra release the stack runs |

`--no-prompt` takes every default, and `--set domain=example.org` answers
one question, for a script say. It creates `./mystack`:

```text
mystack/
  dev.yaml             the stack's settings, your answers in it: edit it, then infrapi-cli dev up
  compose.yaml         the containers: etcd, kayra, reconciler, apisix, gateway-init, httpbin
  compose.docker.yaml  docker only: gives the gateway the host's address
  apisix/              the gateway's configuration
  kayra/Dockerfile     only to build Kayra from a checkout (kayra.src in dev.yaml)
  examples/compute/    an example API, to start yours from
```

`dev.yaml` is the only file you edit. Besides your answers, it holds the
ports, the users of the stack (`admin`, `jdoe`, `nobody`), and the APIs and
tenants `infrapi-cli dev kickstart` creates. [The dev stack](dev-stack.md#devyaml) has
every setting.

## 4. Start it

```bash
cd mystack
infrapi-cli dev doctor
infrapi-cli dev up
infrapi-cli dev health
# {"status":"ok"}  kayra
# {"status":"ok"}  gateway
```

`infrapi-cli dev doctor` prints `ok` or `MISSING` for each prerequisite, and how to
install what is missing. `infrapi-cli dev up` renders Kayra's configuration from
`dev.yaml` into `.infrapi-dev/`, signing keys included, pulls the images and
starts the containers. The first start takes a minute, for the pulls.

| Service | On your machine | |
|---|---|---|
| Kayra | `http://localhost:8081` | authentication, RBAC, the API catalog |
| the gateway | `http://localhost:9080` | APISIX, in front of Kayra and your APIs: what you call |
| APISIX's Admin API | `http://localhost:9180` | its routes, and a UI at `/ui/` |

With docker while podman is installed: `infrapi-cli dev up --engine docker`,
or `export ENGINE=docker` once. `infrapi-cli dev --help` lists every command,
and each prints the commands it runs, `+ podman compose ... up -d` say.
They work from any directory of the stack.

## 5. Log in

On a real Kayra you log in with `infrapi-cli login --server <url>`: your
browser goes through the server's identity provider. The dev stack has no
identity provider, so Kayra signs the tokens itself. `infrapi-cli dev contexts` asks it
for three, and saves each as an `infrapi-cli` context:

```bash
infrapi-cli dev contexts
infrapi-cli context list
# CURRENT  NAME        PROVIDER  SERVER                 EXPIRY
# *        dev-admin             http://localhost:9080  -
#          dev-jdoe              http://localhost:9080  -
#          dev-nobody            http://localhost:9080  -
```

| Context | Who | Can |
|---|---|---|
| `dev-admin` (current) | a sysadmin, group `sandbox-core-sysadmin` | everything: namespaces, API registrations, RBAC |
| `dev-jdoe` | the user `jdoe`, group `sandbox-thetenant-admins` | what the RBAC you create grants that group |
| `dev-nobody` | the user `nobody`, no group | nothing: authenticated, authorized for nothing |

**infrapi-cli**

```bash
infrapi-cli auth whoami
infrapi-cli auth whoami --context dev-jdoe
infrapi-cli context use dev-jdoe     # make it the current one; context use dev-admin to go back
```

**curl**

```bash
ADMIN=$(infrapi-cli context token dev-admin)
curl -s -X POST http://localhost:9080/oauth2/userinfo -H "Authorization: Bearer $ADMIN"
```

The tokens last 8 hours: run `infrapi-cli dev contexts` again when they expire.

## 6. Make a first call

`infrapi-cli dev kickstart` creates the APIs and tenants of `dev.yaml` in Kayra, as
`dev-admin`. By default these are five APIs (`dev`, `compute`, `puppet`,
`objectstorage`, `telemetry`) and two tenants, `core` and `sre`, each
subscribed to every API.

```bash
infrapi-cli dev kickstart
```

**infrapi-cli**

```bash
infrapi-cli apis                                     # every API group and its resources
infrapi-cli get catalog apiregistrations             # the registered APIs
infrapi-cli get catalog -n core subscriptions        # core's subscriptions, synced by the reconciler
```

**curl**

```bash
GW=http://localhost:9080
curl -s $GW/apis -H "Authorization: Bearer $ADMIN"
curl -s $GW/apis/catalog.infrapi.io/v1/apiregistrations -H "Authorization: Bearer $ADMIN"
curl -s $GW/apis/catalog.infrapi.io/v1/namespaces/core/subscriptions -H "Authorization: Bearer $ADMIN"
```

The kickstart's APIs have no code behind them: the gateway answers for them
with a stub spec, one resource, `widgets`. Writing a real one is the next
step.

## 7. Next

| Next | Go to |
|---|---|
| Write an API, route it, onboard a tenant, call it as one of its users | [Create an API](create-an-api.md) |
| Change the domain, ports, users, APIs or tenants | [The dev stack: dev.yaml](dev-stack.md#devyaml) |
| Stop the stack, wipe it, start over | `infrapi-cli dev down` keeps the data; [Reset](dev-stack.md#reset) |
