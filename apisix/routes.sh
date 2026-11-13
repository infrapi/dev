#!/bin/sh
# Loads the dev stack's routes into APISIX through its Admin API, run by
# the gateway-init service. PUT by id, so running it again puts them back
# as they were.
#
#   kayra          /apis, /oauth2/*, /apis/{system,catalog,authorization}.infrapi.io/*  Kayra
#   openapi-stub   GET /apis/<api>/-/openapi.json   an OpenAPI document for any other api
#   hooks          /hooks/*                         the dev reconcile pipeline, always {"status":"done"}
#   healthz        GET /healthz                     {"status":"ok"}
#   httpbin        /httpbin/*                       the httpbin service
#
# An API you develop gets its own routes, matched before these: add-api.sh.
set -eu

ADMIN=${APISIX_ADMIN_URL:-http://localhost:9180}/apisix/admin
KEY=${APISIX_ADMIN_KEY:-podman-admin-api-key}
HERE=$(dirname "$0")

i=0
until curl -fsS -o /dev/null -H "X-API-KEY: $KEY" "$ADMIN/routes"; do
  i=$((i + 1))
  [ "$i" -lt 60 ] || { echo "routes: APISIX Admin API unreachable at $ADMIN" >&2; exit 1; }
  sleep 1
done

put() { # <id> <json>
  printf '%s' "$2" | curl -fsS -o /dev/null -X PUT "$ADMIN/routes/$1" \
    -H "X-API-KEY: $KEY" -H "Content-Type: application/json" --data-binary @- \
    || { echo "routes: PUT $1 failed" >&2; exit 1; }
  echo "routes: $1"
}

mock() { # <body>
  jq -cn --arg body "$1" '{mocking: {response_status: 200, content_type: "application/json", response_example: $body}}'
}

put kayra "$(jq -cn '{
  uris: ["/apis", "/oauth2/*", "/apis/system.infrapi.io/*", "/apis/catalog.infrapi.io/*", "/apis/authorization.infrapi.io/*"],
  upstream: {type: "roundrobin", nodes: {"kayra:8081": 1}}
}')"

put openapi-stub "$(jq -cn --rawfile fn "$HERE/openapi-stub.lua" '{
  uri: "/apis/*",
  vars: [["uri", "~~", "^/apis/[a-z0-9.-]+/-/openapi\\.json$"]],
  methods: ["GET"],
  plugins: {"serverless-pre-function": {phase: "access", functions: [$fn]}}
}')"

put hooks "$(jq -cn --argjson p "$(mock '{"status":"done"}')" '{uri: "/hooks/*", plugins: $p}')"

put healthz "$(jq -cn --argjson p "$(mock '{"status":"ok"}')" '{uri: "/healthz", methods: ["GET"], plugins: $p}')"

put httpbin "$(jq -cn '{
  uri: "/httpbin/*",
  plugins: {"proxy-rewrite": {regex_uri: ["^/httpbin/(.*)", "/$1"]}},
  upstream: {type: "roundrobin", nodes: {"httpbin:80": 1}}
}')"
