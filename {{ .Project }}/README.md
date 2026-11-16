# {{ .Project }}

An InfraPI dev stack, scaffolded by `infrapi-cli dev init`: Kayra
(authentication, RBAC, catalog, reconciler), etcd and APISIX as the gateway,
on podman, and an example API to start yours from. Domain
`{{ .Scaffold.domain }}`, platform `{{ .Scaffold.platform }}`, region
`{{ .Scaffold.region }}`, Kayra `{{ .Scaffold.image }}`.

Everything is configured by `dev.yaml`: edit it, then `make up`.

```bash
make up          # render .infrapi-dev/ from dev.yaml, start the stack
make contexts    # tokens for admin, jdoe and nobody, as infrapi-cli contexts
make kickstart   # optional: dev.yaml's APIs and tenants
infrapi-cli auth whoami
```

Needs podman 4.7 or later with a compose provider, Go 1.26.10 or later for
the example API, and `infrapi-cli`. `make help` lists every target. The
docs are at https://github.com/infrapi/dev: [the dev stack](https://github.com/infrapi/dev/blob/main/docs/dev-stack.md)
and [create an API](https://github.com/infrapi/dev/blob/main/docs/create-an-api.md).
