# AGENTS.md — openresty-template

> AI assistant guide for working on this project.
> For the Claude-specific guide (conventions, DO/DON'T, tool usage), see [`CLAUDE.md`](CLAUDE.md).

---

## What This Project Is

A **copy-once template**. Do not develop business logic here. New projects are created by:

```bash
./create-project.sh MyGateway /path/to/new-project
```

Changes to this repo update the template itself — routing, shared modules, Dockerfile, docs, and the example endpoints that demonstrate usage patterns.

---

## Quick Orientation

| Layer | Location | Purpose |
|---|---|---|
| Nginx config | `conf/` | Main entry, vhost auto-include, env var declarations |
| Virtual hosts | `vhost/*.vhost` | Per-service listen config, routing rules |
| API endpoints | `script/api/v1/` | One dir per route; filenames = HTTP method (`GET.lua`, `POST.lua`, …) |
| Shared modules | `script/shared/` | Reusable Lua utilities (no business logic) |
| Third-party libs | `script/resty/` | JWT, HMAC, OTP, OTel SDK, MessagePack, Tarantool client, … |
| Config loader | `script/config.lua` | Reads env vars declared in `script/script.env.conf` |
| Tracing | `script/server_tracing.lua` | OTel OTLP exporter; opt-in per vhost |

---

## Essential Commands

```bash
# Start / rebuild
docker compose up --build -d

# Apply Lua / config changes (no rebuild needed)
docker compose restart

# View logs
docker compose logs -f gateway

# Run integration tests
bash test.sh                              # default: http://localhost:8080
bash test.sh http://staging.example.com
```

---

## Routing Convention

Requests are automatically mapped by URL path and HTTP method:

```
GET  /api/v1/hello         →  script/api/v1/hello/GET.lua
POST /api/v1/user/profile  →  script/api/v1/user/profile/POST.lua
```

URL path segments must match `[_\-a-zA-Z0-9/]+`. Numeric IDs (e.g. `/user/123`) require a dedicated `location` block in the vhost.

---

## Adding an Endpoint

1. Create `script/api/v1/{path}/{METHOD}.lua`.
2. The file is automatically reachable — no routing config needed.
3. `docker compose restart`, then test.

Minimal endpoint:
```lua
local response = require("shared.api.response")
response.success({ message = "ok" })
```

See `script/api/v1/example/` for validation and HTTP client patterns.

---

## Key Rules

**Response:** Every request path must call exactly one `response.*` function (`success`, `failure`, `error`, `text`, `redirect`). These call `ngx.exit()` internally — code after them does not run. Use `response.on_exit()` for cleanup.

**Validation:** Use `shared/api/httparg.lua` for all input validation. Validation failures automatically return 400 and stop execution.

**`assertion.max(n)`** is a **cap** (`math.min`), not a rejection. To reject values over a threshold, add an explicit guard after reading the value.

**Env vars:** Declare new env vars in `script/script.env.conf` (`env VAR_NAME;`) and read them in `script/config.lua`. Without the declaration, `os.getenv()` returns nil inside OpenResty.

**Module state:** Lua modules are cached per worker. Put request-scoped state in `ngx.ctx`, not in module-level variables.

**Cosockets** (HTTP client, DB calls) are only allowed in `access_by_lua*`, `content_by_lua*`, and `ngx.timer.*`. Not in `init_by_lua*` or `log_by_lua*`.

---

## Security Constraints

| Topic | Rule |
|---|---|
| Method override | Validated against `GET\|POST\|PUT\|PATCH\|DELETE\|HEAD\|OPTIONS`. Invalid values → 405. Do not widen the allowlist. |
| TLS cert validation | `lua_ssl_trusted_certificate` is intentionally disabled. Traffic arrives via CDN (Cloudflare / CloudFront); enabling it creates friction with no security gain. |
| OTel span data | Full request headers and body are recorded by design — B2B internal debugging. Jaeger access is restricted at the infrastructure level. Do not add filtering unless explicitly requested. |
| Project name input | `create-project.sh` validates `PROJECT_NAME` against `[A-Za-z0-9._-]+`. Do not relax this check. |

---

## File Checklist (post-copy)

After `create-project.sh`, before writing business logic:

- [ ] `.env` — set `SERVICE_NAME`
- [ ] `vhost/{name}.vhost` — verify `listen` port
- [ ] `docker-compose.yml` — verify `image` and `container_name`
- [ ] `CLAUDE.md` — update title line to reflect project name
- [ ] `AGENTS.md` — update title line to reflect project name
- [ ] `README.md` — replace with project-specific docs
- [ ] `script/api/v1/example/` — delete (reference only)

---

## Documentation Index

| Document | Content |
|---|---|
| [`docs/api-development.md`](docs/api-development.md) | Endpoints, response module, httparg, HTTP client, object mapper |
| [`docs/routing.md`](docs/routing.md) | File-based routing, VHost structure, custom routes, proxy pass |
| [`docs/kubernetes-deployment.md`](docs/kubernetes-deployment.md) | Env vars, Deployment/Service/ConfigMap manifests, health checks |
| [`docs/plugin-development.md`](docs/plugin-development.md) | Adding Lua libraries, FFI modules, shared dict |
| [`docs/lua-development.md`](docs/lua-development.md) | OpenResty phases, cosocket rules, ngx.ctx, LuaJIT limits, pitfalls |
| [`CLAUDE.md`](CLAUDE.md) | Claude-specific conventions, DO/DON'T, coding style |
