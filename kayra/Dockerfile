# syntax=docker/dockerfile:1
#
# Kayra for local development: kayra and kayra-cli, with a configuration
# that reaches nothing outside the stack's network (self-signed JWTs, a
# users file standing in for LDAP, etcd at etcd:2379, APISIX at
# apisix:9080). See docs/dev-stack.md.
#
# Built by `make build`, from a Kayra checkout given as the src build
# context:
#
#   podman build --format docker --build-context src=../kayra -t kayra-dev:local kayra
#
# --format docker keeps the HEALTHCHECK, which the OCI format drops. The
# signing keys are generated at build time: tokens minted with one image
# are refused by another build.

FROM docker.io/library/golang:1.26-alpine AS build
WORKDIR /src
COPY --from=src go.mod go.sum ./
RUN go mod download
COPY --from=src cmd ./cmd
COPY --from=src internal ./internal
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=dev" -o /out/kayra ./cmd/kayra \
 && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=dev" -o /out/kayra-cli ./cmd/cli

FROM docker.io/library/alpine:3.22 AS config
RUN apk add --no-cache openssl
COPY kayra.yaml.tmpl render-config.sh /tmp/
RUN sh /tmp/render-config.sh /tmp/kayra.yaml.tmpl /out/kayra.yaml

FROM docker.io/library/alpine:3.22
RUN apk add --no-cache ca-certificates curl jq \
 && adduser -D -H -u 10001 kayra
COPY --from=build /out/kayra /out/kayra-cli /usr/local/bin/
COPY --from=config --chown=root:kayra /out/kayra.yaml /etc/kayra/kayra.yaml
COPY users.yaml /etc/kayra/kayra-users.yaml
ENV KAYRA_CONFIG_FILE=/etc/kayra/kayra.yaml
USER kayra
EXPOSE 8081
HEALTHCHECK --interval=5s --timeout=3s --retries=12 CMD curl -fsS http://127.0.0.1:8081/-/healthz || exit 1
ENTRYPOINT ["kayra"]
CMD ["serve"]
