#!/bin/sh
# Routes an API through APISIX to where it runs, for Kayra's reconciler and
# for its clients:
#
#   /apis/<api>/-/openapi.json  ->  <upstream>/-/openapi.json   the spec Kayra reads
#   /apis/<api>/*               ->  <upstream>/apis/<api>/*     the API itself
#
#   add-api.sh <api> <host:port>
#   add-api.sh compute.infrapi.io host.containers.internal:8080
#   add-api.sh -d compute.infrapi.io                              removes them
#
# host.containers.internal is the host, as podman resolves it in a container.
set -eu

ADMIN=${APISIX_ADMIN_URL:-http://localhost:9180}/apisix/admin
KEY=${APISIX_ADMIN_KEY:-podman-admin-api-key}
usage() { echo "usage: add-api.sh <api> <host:port> | add-api.sh -d <api>" >&2; exit 2; }

call() { # <method> <id> [json]
  if [ $# -eq 3 ]; then
    printf '%s' "$3" | curl -fsS -o /dev/null -X "$1" "$ADMIN/routes/$2" \
      -H "X-API-KEY: $KEY" -H "Content-Type: application/json" --data-binary @-
  else
    curl -fsS -o /dev/null -X "$1" "$ADMIN/routes/$2" -H "X-API-KEY: $KEY"
  fi
}

if [ "${1:-}" = "-d" ]; then
  [ $# -eq 2 ] || usage
  call DELETE "$2-openapi" && call DELETE "$2"
  echo "add-api: $2 removed"
  exit 0
fi
[ $# -eq 2 ] || usage
api=$1 upstream=$2
printf '%s' "$api" | grep -Eq '^[a-z0-9-]+(\.[a-z0-9-]+)+$' || { echo "add-api: $api: an api group, like compute.infrapi.io" >&2; exit 2; }

up=$(jq -cn --arg node "$upstream" '{type: "roundrobin", nodes: {($node): 1}}')
call PUT "$api-openapi" "$(jq -cn --arg api "$api" --argjson up "$up" '{
  uri: ("/apis/" + $api + "/-/openapi.json"), methods: ["GET"],
  plugins: {"proxy-rewrite": {uri: "/-/openapi.json"}}, upstream: $up
}')"
call PUT "$api" "$(jq -cn --arg api "$api" --argjson up "$up" '{uri: ("/apis/" + $api + "/*"), upstream: $up}')"
echo "add-api: /apis/$api/* -> $upstream"
