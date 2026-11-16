# InfraPI dev stack

Everything you need to develop an InfraPI API on your machine: Kayra
(authentication, RBAC, catalog, reconciler), etcd and APISIX as the gateway,
on podman or docker, with no external connection once the images are pulled — tokens
are self-signed, users come from a file. All of it configured by one file,
`dev.yaml`: the domain, the image, the ports, the users, the APIs and
tenants to start from. And an example API, built on
[infrapi/lib](https://github.com/infrapi/lib), to start yours from.

This repository is the stack's template, a
[scaffold](https://github.com/hay-kot/scaffold): `infrapi-cli dev init`
asks for the domain, platform, region and Kayra image, and renders the
stack into a directory of your own.

```text
               :9080 APISIX ──┬── /apis/{system,catalog,authorization}.<domain>, /oauth2  →  kayra :8081
infrapi-cli, curl ────────────┤
                              └── /apis/<your api>/*  →  your API, on the host
                                        ▲
              kayra reconciler ─────────┘ reads /apis/<api>/<version>/-/openapi.json through APISIX
```

## Quick start

Step by step: [Getting started](docs/getting-started.md). In short, with
podman 4.7+ or docker (and compose), and
[infrapi-cli installed](https://infrapi.github.io/cli/getting-started/#1-install):

```bash
infrapi-cli dev init mystack   # asks for the domain (infrapi.io), platform, region, Kayra image
cd mystack
make doctor      # checks podman or docker, compose, infrapi-cli, curl, go
make up          # render .infrapi-dev/ from dev.yaml, start the stack
make contexts    # tokens for admin, jdoe and nobody, as infrapi-cli contexts
make kickstart   # optional: dev.yaml's APIs and tenants, core and sre
infrapi-cli auth whoami
```

Then [create an API](docs/create-an-api.md), end to end. `make help` lists
every target, and [Reset](docs/dev-stack.md#reset) shows how to start over:
Kayra's objects only, the whole etcd, or new signing keys.

## Docs

| Page | What it covers |
|---|---|
| [Getting started](docs/getting-started.md) | Install infrapi-cli, the prerequisites, scaffold, start, log in, a first call |
| [Create an API](docs/create-an-api.md) | From an empty module to a tenant calling your API, authorized by Kayra |
| [The dev stack](docs/dev-stack.md) | `dev init`, `dev.yaml`, the services, Kayra's configuration and users, the kickstart, the gateway's routes, the make targets, reset |

## Layout

```text
scaffold.yaml                 the template's questions: domain, platform, region, image
{{ .Project }}/               the stack, rendered into your directory by infrapi-cli dev init
  dev.yaml                    the stack's settings, the answers in it: everything is rendered from it
  Makefile                    the stack, tokens, routes, the example: make help
  compose.yaml                etcd, kayra, reconciler, apisix, gateway-init, httpbin
  compose.docker.yaml         docker only: the host's address for the gateway
  kayra/                      Kayra's image, built from a checkout (kayra.src)
  apisix/                     APISIX's configuration, and the script loading the routes
  examples/compute/           the example API
docs/                         the docs
```

To change the template itself, render it to try it:

```bash
infrapi-cli dev init --template . --no-prompt test-stack   # gitignored
cd test-stack && make check && make up
```
