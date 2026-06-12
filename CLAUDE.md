# CLAUDE.md — openresty-template Agent Guide

This file is read by Claude Code (and other AI agents) at session start.
Follow all instructions here exactly — they override default behaviour.

---

## ⚠️ Template State Check (run at session start)

**This repository is a template.** Before doing any work, determine whether you are in:

- **The template itself** (`openresty-template`) — for maintenance only; do not add business logic
- **A derived project** — normal development applies

### How to detect

Check these three signals:

| Signal | Template (unchanged) | Derived project |
|---|---|---|
| `SERVICE_NAME` in `.env` or `.env.sample` | `GatewayTemplate` | your project name |
| `container_name` in `docker-compose.yml` | `openresty-template` | your project name |
| This file's title line (line 1) | `openresty-template Agent Guide` | your project name |

### If still showing template defaults → remind the user

If any signal above shows template defaults, say this at the start of your response:

> ⚠️ **專案名稱尚未設定。** 請確認是否已透過 `create-project.sh` 建立衍生專案，
> 或手動更新 `SERVICE_NAME`（`.env`）、`container_name`（`docker-compose.yml`）、
> 以及 `CLAUDE.md` 第一行的標題。

Then continue with the user's actual request. Do not block on this.

### After confirming it is a derived project

Update the title of this file (`CLAUDE.md` line 1) to reflect the actual project name, e.g.:

```
# CLAUDE.md — MyGateway Agent Guide
```

---

## Project Overview

An OpenResty + Lua API gateway template. Key facts:

- **Runtime**: OpenResty 1.27.1.2 (Nginx + LuaJIT)
- **Entry point**: `vhost/default.vhost` → `content_by_lua_file` per route
- **Routing**: file-based — `GET /api/v1/foo/bar` maps to `script/api/v1/foo/bar/GET.lua`
- **Method override**: `X-Http-Method` / `X-Http-Method-Override` headers, allowlisted to `GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS`
- **Dev workflow**: edit files locally → `docker compose restart` (volumes are mounted; no rebuild needed)

---

## Key Commands

```bash
# Start (builds image if not present)
docker compose up --build -d

# Apply Lua/config changes (no rebuild)
docker compose restart

# Tail logs
docker compose logs -f gateway

# Run integration tests
bash test.sh

# Scaffold a new project from this template
./create-project.sh MyProject /path/to/target
```

---

## Architecture

```
Request
  └─ Nginx (vhost/default.vhost)
       └─ access_by_lua_block     ← method allowlist; tracing start (opt)
       └─ content_by_lua_file     ← script/api/v1/{path}/{METHOD}.lua
       └─ body_filter_by_lua_block ← tracing flush (opt)
```

All shared code lives in `script/shared/`. All third-party libs live in `script/resty/`.
The `script/config.lua` module loads environment variables once at startup.

---

## Endpoint Conventions

### 1. File placement

```
GET  /api/v1/user/profile  →  script/api/v1/user/profile/GET.lua
POST /api/v1/order         →  script/api/v1/order/POST.lua
```

File name = uppercase HTTP method. No sub-routing inside a single Lua file.

### 2. Minimal endpoint

```lua
local response = require("shared.api.response")

response.success({
    message = "ok"
})
```

`response.success()` sets HTTP 200, `Content-Type: application/json`, auto-appends `timestamp`.
**Always call `response.*` exactly once per code path** — it calls `ngx.exit()` internally.

### 3. Full endpoint with validation

See `script/api/v1/example/GET.lua` and `script/api/v1/example/POST.lua` for canonical examples.
These files are **reference only** — delete them before shipping business logic.
**Exception**: if you activate the WebSocket vhost sample, keep `script/api/v1/example/websocket-echo.lua` — it is explicitly wired by `vhost/websocket.vhost.sample` and is NOT discovered by file-based routing.

The general shape:

```lua
local response = require("shared.api.response")
local httparg  = require("shared.api.httparg")
local def      = require("shared.api.def")

-- 1. Parse inputs (auto-calls response.failure on validation error)
local tag   = httparg.tag()
local query = tag.query
local page  = query.page("number")
local limit = query.limit("number", httparg.assertion.max(100))

-- 2. Business logic
-- ...

-- 3. Respond
response.success({ items = results, page = page })
```

### 4. Error flow rules

| Situation | Call |
|---|---|
| Bad input (wrong type, missing required field) | `response.failure(def.ERROR_CODE.INVALID_ARGUMENT, "detail")` |
| Auth failure | `response.failure(def.ERROR_CODE.PERMISSION_DENIED)` |
| Upstream call failed | `response.error(err)` — err may be string or `{code, message}` table (canonical); legacy `{message=<code>, description=<text>}` also accepted |
| Route redirect needed | `response.redirect("/target/path")` — url must be hardcoded, never user-controlled |

`response.error(err)` auto-classifies: if `err` is an all-caps string matching `^[A-Z0-9_]+$`,
it becomes the error code; otherwise it wraps in `FAILURE`.

---

## Module Reference

> Canonical libraries list (with descriptions) is in [README.md → Included Libraries](README.md#included-libraries). The table below is the working reference Claude needs while writing endpoints — require paths + the most common entry points.

| Module | Require path | Common usage |
|---|---|---|
| Response | `shared.api.response` | `success`, `failure`, `error`, `print`, `html`, `redirect`, `redirect_error`, `on_exit` |
| Validation | `shared.api.httparg` | `tag()` → `tag.json/query/form/header/part/text`; `assertion.*` — **always use this wrapper** (wires `response.failure` as error handler); `shared.httparg` is the raw engine — do not require it directly |
| Error codes | `shared.api.def` | `def.ERROR_CODE.*` constants (see list below) |
| Utilities | `shared.api.util` | `coalesce`, `deep_clone`, `dump_table` |
| Tracing helper | `shared.api.tracing-helper` | `tracing.event.new(span)` → `ev:add_event(name, attrs)` |
| WebAPI client | `shared.api.webapi-client` | `new({host, timeout})` + `do_request` + `resolve_response` (injects OTel headers when tracing active) |
| Low-level HTTP | `shared.http.client` | builder: `:uri():headers():query():body():send(method, timeout)` — single timeout-only retry with exponential backoff |
| Object mapper | `shared.object.mapper` | `map`, `path`, `StringMapper`, `ScalarMapper`, `ObjectMapper`, `ListMapper` |
| JSON | `shared.json` | `encode`, `decode` (deep mapper aware) |
| Base64URL | `shared.base64url` | `encode(s)`, `decode(s)` |
| Config | `config` | `config.ENV.*` (env vars declared in `script/script.env.conf`) |
| Third-party (resty/) | `resty.jwt`, `resty.hmac`, `resty.otp`, `resty.msgpack`, `resty.tarantool` | See README for descriptions |

### `response.*` return shapes

| Function | Status | Content-Type | Note |
|---|---|---|---|
| `response.success(tbl)` | 200 | `application/json` | Auto-appends `timestamp` + `trace_id` (when tracing active) |
| `response.success(str)` | 200 | `text/plain` | String arg: raw body, NO `timestamp` appended |
| `response.failure(code, msg)` | 400 | `application/json` | Body: `{code, message, trace_id, timestamp}`; `code` from `def.ERROR_CODE.*` |
| `response.error(err)` | 400 | `application/json` | String matching `^[A-Z0-9_]+$` → used as code; other string → `FAILURE` with string as message; table `{code, message}` or legacy `{message=<code>, description=<text>}` |
| `response.print(s)` | 200 | `text/plain` | Raw text body |
| `response.html(s)` | 200 | `text/html` | Raw HTML body |
| `response.redirect(url)` | 302 | — | `url` must be hardcoded |
| `response.redirect_error(url, err)` | 302 | — | `url` asserted non-empty; err appended as query |
| `response.on_exit(fn)` | — | — | LIFO cleanup hooks; run after the response |

**Response body shapes:**
```json
// success
{ "data": ..., "timestamp": 1718000000000, "trace_id": "abc..." }

// failure / error
{ "code": "INVALID_ARGUMENT", "message": "detail text", "trace_id": "abc...", "timestamp": 1718000000000 }
// trace_id is omitted when tracing is not active
```

### Error codes (from `script/shared/api/def.lua`)

`def.ERROR_CODE.*` — use these constants in `response.failure(code, msg)`:

| Code | Typical use |
|---|---|
| `OK` | Internal positive sentinel (rarely returned from endpoint) |
| `NOP` | No-op acknowledgement |
| `UNSUPPORTED` | Feature / method not supported |
| `NO_CONTENT` | Resource exists but empty |
| `INVALID_OPERATION` | Operation not allowed in current state |
| `UNKNOWN_FAILURE` | Generic unexpected failure |
| `INVALID_ARGUMENT` | Bad input value or type |
| `PERMISSION_DENIED` | Auth/authz failed |
| `UPSTREAM_ERROR` | Upstream returned non-2xx that couldn't be classified |
| `INVALID_TOKEN` | Token malformed / signature mismatch |
| `TOKEN_EXPIRED` | Token past TTL |
| `MISSING_PRINCIPAL` | Subject identifier absent |
| `INVALID_PRINCIPAL` | Subject identifier malformed |
| `INVALID_SIGNATURE` | HMAC / JWT signature mismatch |
| `DUPLICATE_OPERATION` | Idempotency / replay detected |

Need a new code? Add to `script/shared/api/def.lua` first; never invent freeform error strings.

### httparg input sources

```lua
local tag = httparg.tag()

tag.json.field_name(...)     -- JSON body
tag.query.field_name(...)    -- query string
tag.form.field_name(...)     -- application/x-www-form-urlencoded
tag.header.field_name(...)   -- HTTP headers
tag.part.field_name(...)     -- multipart/form-data part
tag.text(...)                -- raw body text
```

### httparg type handlers (pass as strings)

| Handler | Effect |
|---|---|
| `"required"` | Fail if nil |
| `"string"` | Coerce to string |
| `"number"` | Coerce to number |
| `"boolean"` | `false` ⟺ string `"false"`/`"no"`/`"off"` (any case) or number `0`; any other non-nil → `true`; note: string `"0"` → `true`; nil → `false` |
| `"date"` | Parse `YYYY-M-D` (1–2 digit month/day accepted) → Unix timestamp in server's local timezone |
| `"datetime"` | Parse `YYYY-M-D H:MM:SS` → Unix timestamp in server's local timezone |
| `"json"` | Decode JSON string |
| `"array"` | Validate as array table |
| `"map"` | Validate as non-array table |
| `"any"` | Accept any non-nil value |

### httparg assertions

```lua
local assertion = httparg.assertion

assertion.max(100)                        -- CAP to 100 (math.min), does NOT error
assertion.non_negative_number()           -- ERROR (400) if value < 0
assertion.non_nan_nor_inf()               -- ERROR (400) if NaN or Infinity
assertion.non_empty_string()             -- ERROR (400) if empty string ""
assertion.string_should_in("a","b","c")  -- ERROR (400) if value not in set
assertion.non_empty_array()              -- ERROR (400) if array is empty
```

### webapi-client pattern

```lua
local webapi   = require("shared.api.webapi-client")
local response = require("shared.api.response")

local client = webapi.new({ host = "http://upstream:8080", timeout = 5000 })

-- do_request returns resp or nil, err on transport failure
local resp, err = client:do_request({
    method  = "POST",
    path    = "/v1/resource",
    body    = { key = "value" },    -- auto-JSON-encoded
    headers = { ["X-Internal"] = "1" },
})
if not resp then return response.error(err) end

-- resolve_response: any 2xx → result; any non-2xx → nil, {status,code,message,body}
local result, rerr = webapi.resolve_response(resp)
if rerr then return response.error(rerr) end

response.success(result)
```

`opts` table (second arg to `resolve_response`):
- `opts.passthrough = true` — proxy upstream status/headers/body verbatim (legacy opt-in)
- `opts.raw` — return undecoded body string instead of decoded table
- `opts.error_response_handler` — `fn(resp)` called on non-2xx instead of returning `nil, err`

OTel headers are injected only when `ngx.ctx.span` is set (i.e., tracing is active).

### object mapper pattern

```lua
local mapper = require("shared.object.mapper")

local struct = {
    id      = "user_id",                              -- field rename
    email   = mapper.path("contact", "email"),        -- nested field
    name    = mapper.StringMapper("raw_name"),         -- force string
    contact = mapper.ObjectMapper("raw_contact", {    -- nested object
        email = "email_addr",
    }),
    items   = mapper.ListMapper("rows", {             -- list projection
        sku   = "product_code",
        price = "unit_price",
    }),
}

local out = mapper.map(source_table, struct)
```

---

## Style Rules

1. **One `response.*` call per code path** — `response.*` calls `ngx.exit()`. Code after it does not run.
2. **`local` everything at the top of the file** — no globals.
3. **`require` at the top of the file** — not inside functions, unless lazy-loading is intentional.
4. **Error codes from `def.ERROR_CODE`** — do not invent freeform error strings; add to `shared/api/def.lua` if a new code is needed.
5. **No `print()` or `io.write()`** — use `ngx.log(ngx.ERR, msg)` for logging.
6. **No `os.exit()`** — use `ngx.exit(ngx.HTTP_*)` or let `response.*` handle it.
7. **Module pattern** — every new shared module must follow:
   ```lua
   local _M = {}
   do
     -- implementation
   end
   return _M
   ```
8. **Comments in English** inside Lua files. Nginx config comments in Chinese are fine.
9. **Validate all external input** via `httparg` before using values in business logic.
10. **`redirect_error(url, err)`** — `url` must be a hardcoded trusted path; never pass user input.

---

## DO / DON'T

### DO
- Create one Lua file per route × method (`GET.lua`, `POST.lua`, …)
- Use `httparg.tag()` for every parameter that comes from the request
- Check `err` after every `webapi:do_request()` and `webapi.resolve_response()`
- Add new error codes to `shared/api/def.lua`
- Run `bash test.sh` after any change

### DON'T
- Don't add routes to `nginx.conf` or `vhost/*.vhost` — file-based routing handles it
- Don't use `ngx.var.http_*` directly for user input — use `tag.header.*`
- Don't call `response.*` more than once per request
- Don't hardcode secrets or config — use `.env` and `config.ENV.*`
- Don't mutate the `result` table passed to `response.success()` after the call
- Don't use `io`, `os.execute`, `dofile`, or `loadfile` — they are unsafe in LuaJIT/OpenResty context
- Don't restart the container on every test — copy `conf/local/nginx.http.cache.inc.sample` → `conf/local/nginx.http.cache.inc` (comment out `lua_code_cache on` in `conf/nginx.conf` line 37 first to avoid duplicate-directive error)

---

## Adding a New Shared Module

1. Create `script/shared/my-module.lua` following the `local _M = {} / do / end / return _M` pattern.
2. Require as `require("shared.my-module")` (dots map to directory separators).
3. If it wraps an external call, add timeout handling.
4. Document its public API in this file under **Module Reference**.

---

## Enabling OpenTelemetry Tracing

The tracing start toggle lives in `conf/snippets/access-method-allowlist.inc` — uncomment the last line:

```nginx
access_by_lua_block {
    local allowed = {GET=1,POST=1,PUT=1,PATCH=1,DELETE=1,HEAD=1,OPTIONS=1}
    local m = string.upper(ngx.var.method or "")
    if not allowed[m] then ...
    end
    ngx.var.method = m
    -- require("server_tracing").start()  ← uncomment this line
}
```

Because every location that includes this snippet shares the toggle, enabling it enables tracing for ALL locations that include `snippets/access-method-allowlist.inc`.

For the flush (response recording), uncomment the `body_filter_by_lua_block` block in each vhost file (e.g., `vhost/default.vhost` ~line 33).

Set `JaegerCollector_Host` and `JaegerCollector_OTLPHttpPort` in `.env`.

> **PII note**: `server_tracing` captures the full request line, all headers, and body into the span `request` attribute. `Authorization`, `Cookie`, `Set-Cookie`, and `Proxy-Authorization` header **values** are redacted to `[REDACTED]` before recording. All other header values and the full body are captured verbatim — ensure Jaeger access is restricted accordingly.

---

## Environment Variables

Full list with defaults: [README.md → Configuration](README.md#configuration).

Rule: always read via `require("config").ENV.*` — never call `os.getenv()` directly in endpoint files.
To add a new variable: declare in `script/script.env.conf` (`env VAR_NAME;`) and expose in `script/config.lua`.

---

## DNS Resolver

Default: `127.0.0.11` (Docker built-in), set in `conf/nginx.conf` line 33.
For Kubernetes: copy `conf/local/nginx.http.resolver.inc.sample` → `conf/local/nginx.http.resolver.inc` and set cluster DNS. **Important**: first comment out the default `resolver` line in `conf/nginx.conf` (line 33) — nginx rejects duplicate `resolver` directives in the same `http {}` context.

---

## Integration Tests

```bash
bash test.sh              # runs against http://localhost:8080
bash test.sh http://host  # custom base URL
```

`test.sh` is split into two sections:
1. **Template smoke tests** — health checks, method allowlist, security headers. These always run and must not be broken.
2. **Example-endpoint tests** — tests for `script/api/v1/example/`. These auto-skip when the example directory has been deleted (detected by a 404 probe).

When adding a new endpoint, add a corresponding test case in `test.sh` using the real helpers:

```bash
check_status "GET /api/v1/foo → 200" "200" "$BASE_URL/api/v1/foo"
check_body   "foo contains items"    "items" "$BASE_URL/api/v1/foo"
```

Available helpers: `check_status`, `check_body`, `check_no_header`, `check_header`.

---

## Documentation Index

| Document | Content |
|---|---|
| [`docs/api-development.md`](docs/api-development.md) | Endpoints, response module, httparg, HTTP client, object mapper |
| [`docs/routing.md`](docs/routing.md) | File-based routing, VHost structure, custom routes, proxy pass |
| [`docs/grpc.md`](docs/grpc.md) | gRPC gateway: HTTP/2, `grpc_pass`, TLS, Lua auth |
| [`docs/websocket.md`](docs/websocket.md) | WebSocket: Lua server + proxy patterns, frame types |
| [`docs/kubernetes-deployment.md`](docs/kubernetes-deployment.md) | Env vars, Deployment/Service/ConfigMap manifests, health checks |
| [`docs/plugin-development.md`](docs/plugin-development.md) | Adding Lua libraries, FFI modules, lua_shared_dict |
| [`docs/lua-development.md`](docs/lua-development.md) | OpenResty phases, cosocket rules, ngx.ctx, LuaJIT limits, pitfalls |
| [`AGENTS.md`](AGENTS.md) | General-purpose agent guide (non-Claude-specific) |
