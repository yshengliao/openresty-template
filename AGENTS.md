# AGENTS.md — openresty-template

Generic agent quick-reference for any AI assistant working on this project.

> Using Claude Code? Read [`CLAUDE.md`](CLAUDE.md) first — it has the working conventions, DO/DON'T, and style rules. This file is the lightweight orientation that points everywhere else.

---

## What this project is

A **copy-once OpenResty + Lua API gateway template**. Do not develop business logic in this repo. New projects are scaffolded via:

```bash
./create-project.sh MyGateway /path/to/new-project
```

---

## Where to look

| I want to... | Read this |
|---|---|
| Get oriented (file layout, commands, env vars) | [README.md](README.md) |
| Add an endpoint, use `response` / `httparg` / `mapper` | [docs/api-development.md](docs/api-development.md) |
| Route by subdomain or multi-tenant; add a vhost | [docs/routing.md](docs/routing.md) |
| Proxy gRPC to an upstream service | [docs/grpc.md](docs/grpc.md) |
| Run or proxy WebSocket | [docs/websocket.md](docs/websocket.md) |
| Add a Lua library or FFI module | [docs/plugin-development.md](docs/plugin-development.md) |
| Understand OpenResty phases, cosocket rules, LuaJIT limits | [docs/lua-development.md](docs/lua-development.md) |
| Deploy to Kubernetes | [docs/kubernetes-deployment.md](docs/kubernetes-deployment.md) |
| Coding conventions, error codes, response shapes | [CLAUDE.md](CLAUDE.md) |

---

## Security red lines (do not cross without explicit user approval)

| Topic | Constraint |
|---|---|
| Method allowlist | `conf/snippets/access-method-allowlist.inc` validates HTTP method (case-insensitive, normalised to uppercase) against `GET\|POST\|PUT\|PATCH\|DELETE\|HEAD\|OPTIONS`. Invalid → 405 `{"code":"UNSUPPORTED","message":"Method not allowed"}`. Do not widen. |
| TLS cert validation | `lua_ssl_trusted_certificate` is intentionally off. Traffic arrives via CDN (Cloudflare / CloudFront); enabling it creates friction without security gain. |
| OTel span body capture | Full request line, headers, and body land in spans. `Authorization`/`Cookie`/`Set-Cookie`/`Proxy-Authorization` header values are auto-redacted to `[REDACTED]`. All other values captured verbatim — B2B internal debugging. Jaeger access is restricted infra-side. Do not add further filtering unless explicitly asked. |
| `create-project.sh` input | `PROJECT_NAME` validated against `[A-Za-z0-9._-]+`. Do not relax. |

---

## Post-scaffold checklist (for derived projects, not the template itself)

After `create-project.sh`, before writing business logic:

- [ ] `.env` — already created automatically; verify `SERVICE_NAME` and set `JaegerCollector_Host` if using tracing
- [ ] `vhost/{name}.vhost` — verify `listen` port
- [ ] `docker-compose.yml` — verify `image` and `container_name` (auto-updated by script)
- [ ] `CLAUDE.md` line 1 — already updated by script; confirm it shows your project name
- [ ] `AGENTS.md` line 1 — already updated by script; confirm it shows your project name
- [ ] `README.md` — replace with project-specific docs
- [ ] `script/api/v1/example/` — delete (reference only); keep `websocket-echo.lua` if using the WebSocket vhost sample

---

## Verifying changes

```bash
docker compose restart    # apply Lua / config / vhost edits (no rebuild)
bash test.sh              # integration tests — expect all green
# test.sh smoke tests always run; example-endpoint tests auto-skip if example/ is deleted
```
