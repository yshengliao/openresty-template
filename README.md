# openresty-template

[![OpenResty](https://img.shields.io/badge/openresty-1.27.1.2+-blue.svg)](https://openresty.org/)
![Status](https://img.shields.io/badge/status-template-green.svg)
[![License](https://img.shields.io/badge/license-MIT-brightgreen.svg)](LICENSE)
![AI Generated](https://img.shields.io/badge/AI_Generated-Claude_Code_Opus_4.7_Max-blueviolet.svg)

> [Traditional Chinese](README_ZH.md)

> **This is a project template.** Do not develop directly in this repository.
> Use `create-project.sh` to scaffold a new project, then work in the copy.

A minimal, Docker-first OpenResty + Lua API gateway template. Pre-configured with OpenTelemetry tracing support, a fluent request validation library, a unified JSON response layer, and a collection of general-purpose service libraries.

## Quick Links

| I want to... | Go here |
|---|---|
| Scaffold a new project | [Step 1 — Scaffold](#step-1--scaffold) |
| Add an API endpoint | [Adding an Endpoint](#adding-an-endpoint) |
| Route by subdomain or multi-tenant | [docs/routing.md](docs/routing.md) |
| Proxy gRPC to an upstream service | [docs/grpc.md](docs/grpc.md) |
| Run / proxy WebSocket | [docs/websocket.md](docs/websocket.md) |
| Use `response`, `httparg`, `mapper` modules | [docs/api-development.md](docs/api-development.md) |
| Add a Lua library / FFI module / shared dict | [docs/plugin-development.md](docs/plugin-development.md) |
| Understand OpenResty phases, cosocket, LuaJIT limits | [docs/lua-development.md](docs/lua-development.md) |
| Deploy to Kubernetes | [docs/kubernetes-deployment.md](docs/kubernetes-deployment.md) |
| Local / K8s config overrides | `conf/local/*.sample` |
| Coding conventions for AI agents | [CLAUDE.md](CLAUDE.md) / [AGENTS.md](AGENTS.md) |

## Features

- **Modular VHost design** — each service gets its own `.vhost` file, auto-included by Nginx.
- **Multi-subdomain / multi-tenant ready** — sample vhosts for per-subdomain services, wildcard tenant dispatch, and shared `conf/snippets/` for DRY config. See [docs/routing.md](docs/routing.md).
- **File-based Lua routing** — requests are mapped to `script/api/v1/{path}/{METHOD}.lua` automatically.
- **Method override with allowlist** — `X-Http-Method` / `X-Http-Method-Override` headers are supported, validated against `GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS` to prevent path traversal.
- **OpenTelemetry tracing** — `server_tracing.lua` integrates with Jaeger via OTLP; enable/disable per vhost with a single comment toggle.
- **Fluent request validation** — `shared.api.httparg` provides type coercion, assertions, and multipart parsing; wires `response.failure` automatically so validation errors return HTTP 400.
- **General-purpose service libraries** — JWT, HMAC, OTP (TOTP/HOTP), MessagePack, Tarantool client, Base64URL, and more bundled in `script/resty/`.
- **Docker-first workflow** — volumes are mapped in `docker-compose.yml`; edit Lua files locally, then `docker compose restart` to apply.

## Project Structure

```
openresty-template/
├── conf/                 # Nginx configuration
│   ├── nginx.conf        # Main entry point
│   ├── nginx.vhost.inc   # Auto-includes vhost/*.vhost
│   └── local/            # Environment-specific overrides (gitignored)
│       ├── nginx.http.cache.inc.sample     # lua_code_cache off (dev)
│       └── nginx.http.resolver.inc.sample  # K8s CoreDNS resolver
├── docs/                  # Documentation
│   ├── api-development.md     # API development guide
│   ├── routing.md             # Routing and VHost configuration
│   └── kubernetes-deployment.md # K8s deployment reference
├── script/               # Lua scripts
│   ├── api/v1/           # API endpoints (one dir per route)
│   ├── resty/            # Third-party libs (JWT, HMAC, OTel, OTP, MsgPack, etc.)
│   ├── shared/           # Reusable modules (JSON, HTTP client, response, validation)
│   ├── config.lua        # Environment variable loader
│   └── server_tracing.lua
├── vhost/                # Virtual host configs (.vhost)
│   └── default.vhost     # Example vhost with routing
├── Dockerfile
├── docker-compose.yml
├── test.sh               # Integration test script
└── create-project.sh     # Scaffold a new project from this template
```

## Using This Template

### Step 1 — Scaffold

```bash
./create-project.sh MyGateway /path/to/my-gateway
```

The script will:
1. Copy the template to the target directory (excludes `.git` and `create-project.sh`).
2. Replace `image` and `container_name` in `docker-compose.yml`.
3. Set `SERVICE_NAME` in `.env.sample` and copy it to `.env` automatically.
4. Rewrite line 1 of `CLAUDE.md` and `AGENTS.md` to reflect the project name.
5. Rename `default.vhost` to `{project_name}.vhost`.
6. Initialise a fresh Git repository with an initial commit (warns instead of aborting if git identity is not configured).


### Step 2 — First-time setup

**If you used `create-project.sh`** (recommended): `.env` is already created automatically. Just run:
```bash
cd /path/to/my-gateway
# edit .env if needed — SERVICE_NAME is pre-set, review JaegerCollector_Host etc.
docker compose up --build -d
bash test.sh               # verify everything works
```

**If you cloned the template directly** (without `create-project.sh`):
```bash
cd /path/to/my-gateway
cp .env.sample .env        # copy environment config manually
# edit .env — set SERVICE_NAME, JaegerCollector_Host, etc.
docker compose up --build -d
bash test.sh               # verify everything works
```

> The stack can boot without `.env` — `docker-compose.yml` sets `env_file.required: false` and `config.lua` has defaults for all variables.

### Step 3 — Customise (checklist)

After scaffolding, make sure you have done the following before committing real business logic:

- [ ] **`.env`** — set `SERVICE_NAME` to your project name
- [ ] **`vhost/{name}.vhost`** — update `listen` port if needed (default 8080)
- [ ] **`docker-compose.yml`** — verify `image` and `container_name` are correct
- [ ] **`CLAUDE.md`** — update the title line (`# CLAUDE.md — openresty-template Agent Guide`) to reflect your project
- [ ] **`README.md`** — replace this file with your project's own documentation
- [ ] **`script/api/v1/example/`** — delete the example endpoints (they are for reference only). **Exception**: keep `websocket-echo.lua` if you activate `vhost/websocket.vhost.sample`.

### Development Workflow

All configuration and Lua scripts are volume-mounted into the container. To apply changes:

```bash
# Edit any .lua / .vhost / .conf file locally, then:
docker compose restart
```

No image rebuild needed.

### Adding an Endpoint

To add `GET /api/v1/hello`:

1. Create `script/api/v1/hello/GET.lua`:
   ```lua
   local response = require("shared.api.response")

   response.success({
       message = "Hello, World!"
   })
   ```
2. Ensure your `.vhost` has the catch-all Lua location (included by default):
   ```nginx
   location ~ ^/api/v1/([_\-a-zA-Z0-9/]+)$ {
       content_by_lua_file "$SCRIPT_DIR/api/v1/$1/${method}.lua";
   }
   ```
3. `docker compose restart` and test.

See [API Development Guide](docs/api-development.md) for detailed usage of response, validation, and HTTP client modules.

### Health Check

`/healthcheck` returns `200 ok` (plain text).  
`/ping` returns `200 pong`.

Both have `access_log off` and are suitable for load balancer or Docker health checks.

### Integration Tests

```bash
bash test.sh                          # default: http://localhost:8080
bash test.sh http://staging.example.com
```

`test.sh` has two sections: **template smoke tests** (health, method allowlist, security headers — always run) and **example-endpoint tests** (auto-skip when `script/api/v1/example/` has been deleted).

## Included Libraries

| Library | Purpose |
|---|---|
| `shared/api/response.lua` | Unified JSON/text/HTML/redirect response |
| `shared/api/webapi-client.lua` | HTTP client with OTel context propagation |
| `shared/api/tracing-helper.lua` | OTel span event helper |
| `shared/api/httparg.lua` | Fluent request body/query/multipart validation entry point (wires `response.failure` automatically; `shared/httparg.lua` is the raw engine — do not require it directly) |
| `shared/http/client.lua` | Low-level HTTP client builder (`:uri():headers():query():body():send()`); single timeout-only retry with exponential backoff |
| `shared/object/mapper.lua` | Declarative object mapping/projection |
| `shared/json.lua` | JSON encoder/decoder with deep mapper support |
| `shared/base64url.lua` | Base64URL encode/decode |
| `resty/jwt.lua` | JWT encode/decode/verify |
| `resty/hmac.lua` | HMAC-SHA256 signing |
| `resty/otp.lua` | TOTP / HOTP one-time password |
| `resty/msgpack.lua` | MessagePack encode/decode |
| `resty/tarantool.lua` | Tarantool database client |
| `resty/lib/opentelemetry/` | Full OpenTelemetry Lua SDK |
| `resty.websocket` (built-in) | WebSocket server and client — ships with the OpenResty base image; no separate install needed |

## Configuration

Environment variables are declared in `script/script.env.conf` and read in `script/config.lua`.

| Variable | Default | Description |
|---|---|---|
| `SERVICE_NAME` | `GatewayTemplate` | Service name reported in OTel traces |
| `BUILD_COMMIT_TAG` | — | Git tag injected at build time |
| `BUILD_COMMIT_SHA` | — | Git SHA injected at build time |
| `JaegerCollector_Host` | `127.0.0.1` | Jaeger OTLP collector host |
| `JaegerCollector_OTLPHttpPort` | `4318` | Jaeger OTLP HTTP port |

## Security Notes

| Topic | Behaviour |
|---|---|
| Method override | `X-Http-Method` / `X-Http-Method-Override` are validated against a strict allowlist. Invalid values return 405. |
| DNS resolver | Defaults to `127.0.0.11` (Docker's built-in DNS). For K8s, copy `conf/local/nginx.http.resolver.inc.sample` and set the cluster DNS. |
| Container user | Runs as `nobody` (non-root). Port 8080 does not require root. |
| Server header | Removed from all responses via `more_clear_headers Server`. |
| Trace data | Full request line, headers, and body are captured in OTel spans. `Authorization`, `Cookie`, `Set-Cookie`, and `Proxy-Authorization` header values are automatically redacted to `[REDACTED]`. All other values and the full body are stored verbatim (B2B internal use). Restrict Jaeger access accordingly. |

## Documentation

| Document | Description |
|---|---|
| [API Development Guide](docs/api-development.md) | Endpoints, response, httparg validation, HTTP client, object mapper |
| [Routing and VHost](docs/routing.md) | File-based routing, VHost structure, custom routes, proxy pass |
| [gRPC Gateway](docs/grpc.md) | HTTP/2, `grpc_pass`, TLS, Lua auth before grpc_pass |
| [WebSocket](docs/websocket.md) | Lua WS server + proxy patterns, frame types, common pitfalls |
| [Kubernetes Deployment](docs/kubernetes-deployment.md) | Env vars, Deployment/Service/ConfigMap manifests, health checks |
| [Plugin Development](docs/plugin-development.md) | Adding Lua libraries, FFI modules, shared dict |
| [Lua Development Guide](docs/lua-development.md) | OpenResty phases, cosocket rules, ngx.ctx, LuaJIT limits, pitfalls |

## Licence

MIT
