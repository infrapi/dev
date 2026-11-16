# {{ .Project }}

An InfraPI dev stack, scaffolded by `infrapi-cli dev init`: Kayra
(authentication, RBAC, catalog, reconciler), etcd and APISIX as the gateway,
on podman or docker, and an example API to start yours from. Domain
`{{ .Scaffold.domain }}`, platform `{{ .Scaffold.platform }}`, region
`{{ .Scaffold.region }}`, Kayra `{{ .Scaffold.image }}`.

Everything is configured by `dev.yaml`: edit it, then `infrapi-cli dev up`.

```bash
infrapi-cli dev doctor      # checks podman or docker, its compose, go
infrapi-cli dev up          # render .infrapi-dev/ from dev.yaml, start the stack (--engine docker to force docker)
infrapi-cli dev contexts    # tokens for admin, jdoe and nobody, as infrapi-cli contexts
infrapi-cli dev kickstart   # optional: dev.yaml's APIs and tenants
infrapi-cli auth whoami
```

Needs podman 4.7 or later or docker, with compose, Go 1.27.3 or later for
the example API, and [infrapi-cli](https://infrapi.github.io/cli/getting-started/#1-install). `infrapi-cli dev --help` lists every command. The
docs are at https://github.com/infrapi/dev: [getting started](https://github.com/infrapi/dev/blob/main/docs/getting-started.md),
[the dev stack](https://github.com/infrapi/dev/blob/main/docs/dev-stack.md)
and [create an API](https://github.com/infrapi/dev/blob/main/docs/create-an-api.md).
