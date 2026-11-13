-- serverless-pre-function of the openapi-stub route: an OpenAPI document
-- for any api at /apis/<api>/-/openapi.json, declaring one namespaced
-- resource, "widgets". Loaded by routes.sh.
return function(conf, ctx)
  local core = require("apisix.core")
  local api = ngx.var.uri:match("^/apis/([a-z0-9.-]+)/%-/openapi%.json$")
  if not api then
    return core.response.exit(404, {status = 404, title = "Not Found"})
  end
  local op = {responses = {["200"] = {description = "ok"}}}
  local widgets = "/apis/" .. api .. "/v1/namespaces/{namespace}/widgets"
  core.response.set_header("Content-Type", "application/json")
  return core.response.exit(200, {
    openapi = "3.0.3",
    info = {title = api .. " (stub)", version = "v1"},
    paths = {
      [widgets] = {get = op, post = op},
      [widgets .. "/{name}"] = {get = op, delete = op},
    },
  })
end
