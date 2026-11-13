# InfraPI dev stack

Everything you need to develop an InfraPI API on your machine: Kayra
(authentication, RBAC, catalog, reconciler), etcd and APISIX as the gateway,
on podman, with no external connection — tokens are self-signed, users come
from a file. And an example API, built on
[infrapi/lib](https://github.com/infrapi/lib), to start yours from.

```text
               :9080 APISIX ──┬── /apis/{system,catalog,authorization}.infrapi.io, /oauth2  →  kayra :8081
kayra-cli, curl ──────────────┤
                              └── /apis/<your api>/*  →  your API, on the host
                                        ▲
              kayra reconciler ─────────┘ reads /apis/<api>/-/openapi.json through APISIX
```

## Quick start

Podman 4.7 or later with a compose provider (`podman compose version`), Go
1.26.7 or later, and a checkout of [infrapi/kayra](https://github.com/infrapi/kayra)
next to this one (or `KAYRA_SRC=<path>`):

```bash
make up          # build Kayra's image, start the stack
make contexts    # tokens for admin, jdoe and nobody, as kayra-cli contexts
export PATH=$PWD/bin:$PATH
kayra-cli auth whoami
```

Then [create an API](docs/create-an-api.md), end to end. `make help` lists
every target.

## Docs

| Page | What it covers |
|---|---|
| [Create an API](docs/create-an-api.md) | From an empty module to a tenant calling your API, authorized by Kayra |
| [The dev stack](docs/dev-stack.md) | The services, the configuration, the users, the gateway's routes, the make targets |

## Layout

```text
Makefile                 the stack, tokens, routes, the example: make help
compose.yaml             etcd, kayra, reconciler, apisix, gateway-init, httpbin
kayra/                   Kayra's image: Dockerfile, configuration template, users
apisix/                  APISIX's configuration and routes
examples/compute/        the example API
docs/                    the docs
```
