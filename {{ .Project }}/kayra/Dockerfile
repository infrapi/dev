# syntax=docker/dockerfile:1
#
# Kayra built from a checkout, for dev.yaml's kayra.src: the same layout as
# the released image (ghcr.io/infrapi/kayra), kayra on
# Alpine with curl, no configuration inside. The stack mounts the one
# rendered from dev.yaml (.infrapi-dev/kayra.yaml). Built by `make build`:
#
#   podman build --format docker --build-context src=../kayra -t kayra-dev:local kayra
#   docker build --build-context src=../kayra -t kayra-dev:local kayra   (BuildKit)

FROM docker.io/library/golang:1.26-alpine AS build
WORKDIR /src
COPY --from=src go.mod go.sum ./
RUN go mod download
COPY --from=src cmd ./cmd
COPY --from=src internal ./internal
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=dev" -o /out/kayra ./cmd/kayra

FROM docker.io/library/alpine:3.22
RUN apk add --no-cache ca-certificates curl \
 && adduser -D -H -u 10001 kayra
COPY --from=build /out/kayra /usr/local/bin/
ENV KAYRA_CONFIG_FILE=/etc/kayra/kayra.yaml
USER kayra
EXPOSE 8081
ENTRYPOINT ["kayra"]
CMD ["serve"]
