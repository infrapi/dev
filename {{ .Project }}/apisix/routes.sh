#!/bin/sh
# Loads the dev stack's own routes into APISIX through its Admin API, run by
# the gateway-init service: one JSON body per route in <dir>, rendered by
# infrapi-dev render from dev.yaml (.infrapi-dev/routes), the route's id in
# its name: 00-kayra.json is route kayra. PUT by id, so running it again puts
# them back as they were. sh and curl only.
#
#   routes.sh <dir>
#
#   kayra          /apis, /oauth2/*, /.well-known/{kayra,api}.json, Kayra's own groups  Kayra
#   openapi-stub   GET /apis/<api>/<version>/-/openapi.json   an OpenAPI document for any other api
#   hooks          /hooks/*                         the dev reconcile pipeline, always {"status":"done"}
#   healthz        GET /healthz                     {"status":"ok"}
#   httpbin        /httpbin/*                       the httpbin service
#
# An API you develop gets its own route, matched before these: infrapi-cli dev api add.
set -eu

DIR=${1:?usage: routes.sh <dir>}
ADMIN=${APISIX_ADMIN_URL:-http://localhost:9180}/apisix/admin
KEY=${APISIX_ADMIN_KEY:-podman-admin-api-key}

i=0
until curl -fsS -o /dev/null -H "X-API-KEY: $KEY" "$ADMIN/routes"; do
  i=$((i + 1))
  [ "$i" -lt 60 ] || { echo "routes: APISIX Admin API unreachable at $ADMIN" >&2; exit 1; }
  sleep 1
done

for f in "$DIR"/*.json; do
  [ -e "$f" ] || { echo "routes: no route in $DIR: infrapi-cli dev render" >&2; exit 1; }
  id=$(basename "$f" .json)
  id=${id#[0-9][0-9]-}
  curl -fsS -o /dev/null -X PUT "$ADMIN/routes/$id" \
    -H "X-API-KEY: $KEY" -H "Content-Type: application/json" --data-binary "@$f" \
    || { echo "routes: PUT $id failed" >&2; exit 1; }
  echo "routes: $id"
done
