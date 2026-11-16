---
title: Create an API
description: From a Go service built on lib to a tenant calling it through the gateway, authenticated and authorized by Kayra, its subscription reconciled.
weight: 30
---

# Create an API

This walks through `examples/compute`, an API of virtual machines, from
its code to a tenant's user creating one through the gateway:

1. [Start the stack](#1-start-the-stack)
2. [Write the API](#2-write-the-api)
3. [Run it, behind the gateway](#3-run-it-behind-the-gateway)
4. [Onboard a tenant](#4-onboard-a-tenant)
5. [Register the API, subscribe the tenant](#5-register-the-api-subscribe-the-tenant)
6. [Grant the tenant's users access](#6-grant-the-tenants-users-access)
7. [Call it](#7-call-it)
8. [Change it](#8-change-it)

Every command runs in a stack created by `infrapi-cli dev init` with its
defaults, `dev.yaml` as it is: domain `infrapi.io`, platform `sandbox`,
the gateway on `localhost:9080`. With another `domain`, every `infrapi.io` below is
yours: `compute.<domain>`, `catalog.<domain>`... `make kickstart` creates
other tenants and APIs to start from. This walkthrough onboards its own
tenant, `thetenant`, step by step.

## 1. Start the stack

```bash
infrapi-cli dev init mystack --no-prompt   # the defaults: infrapi.io, sandbox, eu-west-1
cd mystack
make up
make contexts
make health
# {"status":"ok"}  kayra
# {"status":"ok"}  gateway
```

`make contexts` saves three `infrapi-cli` contexts, all on the gateway at
`http://localhost:9080`: `dev-admin`, a sysadmin and the current one,
`dev-jdoe`, a member of the tenant's group `sandbox-thetenant-admins`, and
`dev-nobody`, who belongs to nothing (see [the stack](dev-stack.md#contexts)).
The `curl` examples read their tokens:

```bash
ADMIN=$(infrapi-cli context token dev-admin)
JDOE=$(infrapi-cli context token dev-jdoe)
NOBODY=$(infrapi-cli context token dev-nobody)
GW=http://localhost:9080
META='"metadata": {"namespace": "thetenant", "region": "eu-west-1", "platform": "sandbox"}'
```

## 2. Write the API

An InfraPI API is a Go service built on
[infrapi/lib](https://github.com/infrapi/lib): `server.NewServerGin` gives
the engine (health, metrics, OpenAPI, RFC 9457 errors), `server.APIGroup`
the URL layout every API shares,
`/apis/<group>/<version>/namespaces/<namespace>/<resource>`, and
`auth.Client` asks Kayra who the caller is and whether they may act.

The group is named in full, `compute.infrapi.io`: that is the name the API
is registered under in Kayra. Kayra's own domain is not the API's concern: the client
is given Kayra's URL and reads the rest from its
`/.well-known/kayra.json`.

`examples/compute/main.go`, the wiring:

```go
// COMPUTE_API_GROUP: compute.infrapi.io, compute.<domain> under make example
group := api.Group{Name: name, Version: "v1"}

// Kayra's URL only: its check endpoint comes from its /.well-known/kayra.json
kayra, err := auth.NewClient(auth.ClientOptions{BaseURL: authURL})
// who the caller is: Kayra's /oauth2/userinfo, on every route added after
engine, err := server.NewServerGin(app, []string{group.Root()}, server.WithAuth(kayra.Middleware()))
// /apis/compute.infrapi.io/v1/namespaces/:namespace
routes, err := server.APIGroup(engine, group)
// whether they may: Kayra's check endpoint, on every request
routes.Use(kayra.RequireAccess())
register(routes, newStore())
```

`examples/compute/vms.go`, the resource:

```go
func register(r gin.IRouter, s *store) {
	r.GET("/vms", s.list)
	r.POST("/vms", s.create)
	r.GET("/vms/:name", s.get)
	r.DELETE("/vms/:name", s.delete)
}
```

`RequireAccess` reads the request's path and method: `POST
.../namespaces/thetenant/vms` asks Kayra whether the caller may `create`
`vms` of `compute.infrapi.io` in namespace `thetenant`. The handlers never
check access themselves: they read the namespace with `server.Namespace(c)`
and answer errors with `server.AbortError(c, errors.NotFound(...))`.

The engine serves its own endpoints under the group's root, `group.Root()`:
`/apis/compute.infrapi.io/v1/-/healthz`, `-/metrics`, `-/docs`, and
`-/openapi.json`, which describes its routes. That is where Kayra learns
the API's resources, `vms` here, through the gateway, at the version the
registration names (`v1` unless set). Nothing to write for it.

> [!NOTE]
> **An API with its own contract**
>
> With `server.WithOpenAPI`, `<root>/-/openapi.json` describes only the
> engine's `-/` endpoints, the contract being under `<root>/-/openapi/`:
> Kayra would see no resource. Give the gateway a route of its own for
> `GET /apis/<api>/<version>/-/openapi.json`, rewritten to the contract,
> a JSON document of the API's `/apis/...` paths.

Settings come from a dotenv file: the `INFRAPI_APP_*` keys of `lib`,
`COMPUTE_API_GROUP`, the API's group, and `COMPUTE_AUTH_URL`, Kayra's URL,
here through the gateway. `make example` renders it from `dev.yaml`
(`.infrapi-dev/example.env`). `examples/compute/.env.example` is the same
for running it on its own. It listens on `0.0.0.0:8080` (`example.port`),
for APISIX to reach it from its container.

## 3. Run it, behind the gateway

In a second terminal:

```bash
make example
# …	info	compute	serving	{"address": "0.0.0.0:8080", "api": "/apis/compute.infrapi.io/v1", "auth": "http://localhost:9080"}
```

`make example LIB_SRC=../lib` runs it against a `lib` checkout instead
of the version its `go.mod` pins, to try a change to `lib`.

Then route it through the gateway, for Kayra's reconciler and for its
callers:

```bash
make api-add
# api: /apis/compute.infrapi.io/* -> host.containers.internal:8080
curl -s $GW/apis/compute.infrapi.io/v1/-/openapi.json | jq '.paths | keys'
# ["/apis/compute.infrapi.io/v1/-/docs", "/apis/compute.infrapi.io/v1/-/healthz", …, "/apis/compute.infrapi.io/v1/namespaces/{namespace}/vms", "/apis/compute.infrapi.io/v1/namespaces/{namespace}/vms/{name}"]
```

`make api-add API=<api> UPSTREAM=<host:port>` for another API, `make api-rm`
to remove the route.

## 4. Onboard a tenant

As `dev-admin`: a namespace, `thetenant`, and the cluster RBAC that lets
its admins manage its subscriptions and its own RBAC.

**infrapi-cli**

```bash
infrapi-cli context use dev-admin
infrapi-cli create system namespaces -d '{"name": "thetenant"}'
infrapi-cli create authorization clustergroups \
  -d "{\"name\": \"thetenant-admins\", $META, \"groups\": [\"sandbox-core-sysadmin\", \"sandbox-thetenant-admins\"]}"
infrapi-cli create authorization clusterroles \
  -d "{\"name\": \"thetenant-admin-role\", $META, \"rules\": [{\"apis\": [\"catalog.infrapi.io\", \"authorization.infrapi.io\"], \"resources\": [\"*\"], \"verbs\": [\"*\"]}]}"
infrapi-cli create authorization clusterrolebindings \
  -d "{\"name\": \"thetenant-admin-binding\", $META, \"role\": \"thetenant-admin-role\", \"groups\": [\"thetenant-admins\"]}"
```

**curl**

```bash
H=(-H "Authorization: Bearer $ADMIN" -H "Content-Type: application/json")
curl -s -X POST $GW/apis/system.infrapi.io/v1/namespaces "${H[@]}" -d '{"name": "thetenant"}'
curl -s -X POST $GW/apis/authorization.infrapi.io/v1/clustergroups "${H[@]}" \
  -d "{\"name\": \"thetenant-admins\", $META, \"groups\": [\"sandbox-core-sysadmin\", \"sandbox-thetenant-admins\"]}"
curl -s -X POST $GW/apis/authorization.infrapi.io/v1/clusterroles "${H[@]}" \
  -d "{\"name\": \"thetenant-admin-role\", $META, \"rules\": [{\"apis\": [\"catalog.infrapi.io\", \"authorization.infrapi.io\"], \"resources\": [\"*\"], \"verbs\": [\"*\"]}]}"
curl -s -X POST $GW/apis/authorization.infrapi.io/v1/clusterrolebindings "${H[@]}" \
  -d "{\"name\": \"thetenant-admin-binding\", $META, \"role\": \"thetenant-admin-role\", \"groups\": [\"thetenant-admins\"]}"
```

## 5. Register the API, subscribe the tenant

Kayra knows an API once it is registered; a tenant uses it once
subscribed. The reconciler then activates the namespace, fetches the API's
spec through the gateway, runs the `dev` pipeline
([the stack](dev-stack.md#the-reconcile-pipeline)) and activates the
subscription.

**infrapi-cli**

```bash
infrapi-cli create catalog apiregistrations \
  -d '{"name": "compute.infrapi.io", "short_name": "compute", "active": true, "owner": "sre"}'
infrapi-cli create catalog -n thetenant subscriptions -d '{"api": "compute.infrapi.io"}'

# a few seconds later
infrapi-cli get catalog -n thetenant subscriptions compute.infrapi.io -o json
# {"api": "compute.infrapi.io", "active": true, "state": "success", "synced": true, …}
infrapi-cli apis --api-group compute
# NAME  SHORTNAME  APIGROUP            NAMESPACED  VERBS
# vms   compute    compute.infrapi.io  true        create,delete,get,list
```

**curl**

```bash
curl -s -X POST $GW/apis/catalog.infrapi.io/v1/apiregistrations "${H[@]}" \
  -d '{"name": "compute.infrapi.io", "short_name": "compute", "active": true, "owner": "sre"}'
curl -s -X POST $GW/apis/catalog.infrapi.io/v1/namespaces/thetenant/subscriptions "${H[@]}" \
  -d '{"api": "compute.infrapi.io"}'

# a few seconds later
curl -s $GW/apis/catalog.infrapi.io/v1/namespaces/thetenant/subscriptions/compute.infrapi.io "${H[@]}"
# {"api":"compute.infrapi.io","active":true,"state":"success","synced":true,…}
curl -s $GW/apis "${H[@]}" | jq '.[] | select(.api == "compute.infrapi.io") | .resources'
```

`make logs SERVICE=reconciler` shows it at work:

```text
catalog: reconciler: … stored openapi spec of "compute.infrapi.io" (1 resources)
catalog: reconciler: … step 0 POST http://apisix:9080/hooks/compute.infrapi.io/namespaces/thetenant/sync -> 200 …
catalog: reconciler: … step 1 GET http://apisix:9080/hooks/compute.infrapi.io/namespaces/thetenant/sync/… -> 200 …
catalog: reconciler: … activated subscription thetenant/compute.infrapi.io
```

## 6. Grant the tenant's users access

`jdoe` is in the tenant's group, but nothing in the namespace grants it
`vms` yet: Kayra's check refuses them.

**infrapi-cli**

```bash
infrapi-cli get compute -n thetenant vms --context dev-jdoe
# Error: Forbidden (403): you are not a member of namespace "thetenant": neither your user id nor any of your groups is listed in any of its groups
```

**curl**

```bash
curl -s $GW/apis/compute.infrapi.io/v1/namespaces/thetenant/vms -H "Authorization: Bearer $JDOE"
# {"title":"Forbidden","status":403,"detail":"you are not a member of namespace \"thetenant\": …"}
```

The namespace's own RBAC grants it: a group of the namespace naming the
identity provider's group, a role on the API's resources, a binding of the
two.

**infrapi-cli**

```bash
infrapi-cli create authorization -n thetenant groups \
  -d "{\"name\": \"devs\", $META, \"groups\": [\"sandbox-thetenant-admins\"]}"
infrapi-cli create authorization -n thetenant roles \
  -d "{\"name\": \"vms-admin\", $META, \"rules\": [{\"apis\": [\"compute.infrapi.io\"], \"resources\": [\"vms\"], \"verbs\": [\"*\"]}]}"
infrapi-cli create authorization -n thetenant rolebindings \
  -d "{\"name\": \"devs-vms-admin\", $META, \"role\": \"vms-admin\", \"groups\": [\"devs\"]}"

infrapi-cli auth can-i create vms --api compute.infrapi.io --namespace thetenant --context dev-jdoe
# yes
```

**curl**

```bash
NS=$GW/apis/authorization.infrapi.io/v1/namespaces/thetenant
curl -s -X POST $NS/groups "${H[@]}" \
  -d "{\"name\": \"devs\", $META, \"groups\": [\"sandbox-thetenant-admins\"]}"
curl -s -X POST $NS/roles "${H[@]}" \
  -d "{\"name\": \"vms-admin\", $META, \"rules\": [{\"apis\": [\"compute.infrapi.io\"], \"resources\": [\"vms\"], \"verbs\": [\"*\"]}]}"
curl -s -X POST $NS/rolebindings "${H[@]}" \
  -d "{\"name\": \"devs-vms-admin\", $META, \"role\": \"vms-admin\", \"groups\": [\"devs\"]}"

curl -s -X POST $GW/apis/authorization.infrapi.io/v1/check -H "Authorization: Bearer $JDOE" -H "Content-Type: application/json" \
  -d '{"namespace": "thetenant", "api": "compute.infrapi.io", "resource": "vms", "verb": "create"}'
# {"allowed":true}
```

A role names only resources the API's spec declares: Kayra answers 404 for
any other.

## 7. Call it

As `jdoe`, through the gateway:

**infrapi-cli**

```bash
infrapi-cli create compute -n thetenant vms -d '{"name": "web-1", "cpus": 2}' --context dev-jdoe
# NAMESPACE  NAME   CREATED AT                 UPDATED AT
# thetenant  web-1  2026-11-13T14:48:24+01:00  -
infrapi-cli get compute -n thetenant vms web-1 -o json --context dev-jdoe
# {"name": "web-1", "cpus": 2, "memory_mb": 1024, "created_at": "2026-11-13T13:48:24Z"}
infrapi-cli get compute -n thetenant vms --context dev-jdoe
infrapi-cli create compute -n thetenant vms -d '{"name": "web-1"}' --context dev-jdoe
# Error: Already exists (409): vm "web-1" already exists in namespace "thetenant"
infrapi-cli get compute -n thetenant vms --context dev-nobody
# Error: Forbidden (403): you are not a member of namespace "thetenant": …
infrapi-cli delete compute -n thetenant vms web-1 --context dev-jdoe
# vms "web-1" deleted
```

**curl**

```bash
VMS=$GW/apis/compute.infrapi.io/v1/namespaces/thetenant/vms
curl -s -X POST $VMS -H "Authorization: Bearer $JDOE" -H "Content-Type: application/json" -d '{"name": "web-1", "cpus": 2}'
# {"name":"web-1","cpus":2,"memory_mb":1024,"created_at":"2026-11-13T13:48:24Z"}
curl -s $VMS/web-1 -H "Authorization: Bearer $JDOE"
curl -s $VMS -H "Authorization: Bearer $JDOE"
# [{"name":"web-1","cpus":2,"memory_mb":1024,"created_at":"2026-11-13T13:48:24Z"}]
curl -s -X POST $VMS -H "Authorization: Bearer $JDOE" -H "Content-Type: application/json" -d '{"name": "web-1"}'
# {"title":"Already exists","status":409,"detail":"vm \"web-1\" already exists in namespace \"thetenant\"",…}
curl -s $VMS -H "Authorization: Bearer $NOBODY"
# {"title":"Forbidden","status":403,…}
curl -s -X DELETE $VMS/web-1 -H "Authorization: Bearer $JDOE" -o /dev/null -w '%{http_code}\n'
# 204
```

## 8. Change it

Add a resource (a route under `register`), restart `make example`, then
have Kayra read the spec again, and grant it in a role:

**infrapi-cli**

```bash
infrapi-cli update catalog apiregistrations compute.infrapi.io/sync -d '{}'
infrapi-cli apis --api-group compute
```

**curl**

```bash
curl -s -X PUT $GW/apis/catalog.infrapi.io/v1/apiregistrations/compute.infrapi.io/sync "${H[@]}" -d '{}'
curl -s $GW/apis "${H[@]}" | jq '.[] | select(.api == "compute.infrapi.io") | .resources'
```

The example keeps its VMs in memory: they go with the process. Its
subscriptions do nothing on the API's side either, the `dev` pipeline
calling the gateway's `hooks` stub: an API that provisions something per
tenant serves its own sync endpoints, and its registration names a
reconcile mode calling them (see Kayra's
[subscriptions](https://github.com/infrapi/kayra/blob/main/docs/architecture/subscriptions.md#http-step-pipeline)).

`make api-rm` removes the API's routes, `make clean` everything.
