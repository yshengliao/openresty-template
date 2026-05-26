# openresty-template

> [Traditional Chinese](README_ZH.md)

> **This is a project template.** Do not develop directly in this repository.
> Use `create-project.sh` to scaffold a new project, then work in the copy.

A minimal, Docker-first OpenResty + Lua API gateway template. Pre-configured with OpenTelemetry tracing support, a fluent request validation library, a unified JSON response layer, and a collection of general-purpose service libraries.

## Features

- **Modular VHost design** — each service gets its own `.vhost` file, auto-included by Nginx.
- **Multi-subdomain / multi-tenant ready** — sample vhosts for per-subdomain services, wildcard tenant dispatch, and shared `conf/snippets/` for DRY config. See [docs/routing.md](docs/routing.md).
- **File-based Lua routing** — requests are mapped to `script/api/v1/{path}/{METHOD}.lua` automatically.
- **Method override with allowlist** — `X-Http-Method` / `X-Http-Method-Override` headers are supported, validated against `GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS` to prevent path traversal.
- **OpenTelemetry tracing** — `server_tracing.lua` integrates with Jaeger via OTLP; enable/disable per vhost with a single comment toggle.
- **Fluent request validation** — `shared/httparg.lua` provides type coercion, assertions, and multipart parsing out of the box.
- **General-purpose service libraries** — JWT, HMAC, OTP (TOTP/HOTP), MessagePack, Tarantool client, Base64URL, and more bundled in `script/resty/`.
- **Docker-first workflow** — volumes are mapped in `docker-compose.yml`; edit Lua files locally, then `docker compose restart` to apply.

## Project Structure

```
openresty-template/
├── conf/                 # Nginx configuration
│   ├── nginx.conf        # Main entry point
│   ├── nginx.vhost.inc   # Auto-includes vhost/*.vhost
│   └── local/            # Environment-specific overrides (gitignored)
│       └── nginx.http.resolver.inc.sample  # K8s DNS resolver example
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
3. Set `SERVICE_NAME` in `.env.sample`.
4. Rename `default.vhost` to `{project_name}.vhost`.
5. Initialise a fresh Git repository with an initial commit.

### Step 2 — First-time setup

```bash
cd /path/to/my-gateway
cp .env.sample .env        # copy environment config
# edit .env — set SERVICE_NAME, JaegerCollector_Host, etc.
docker compose up -d
bash test.sh               # verify everything works
```

### Step 3 — Customise (checklist)

After scaffolding, make sure you have done the following before committing real business logic:

- [ ] **`.env`** — set `SERVICE_NAME` to your project name
- [ ] **`vhost/{name}.vhost`** — update `listen` port if needed (default 8080)
- [ ] **`docker-compose.yml`** — verify `image` and `container_name` are correct
- [ ] **`CLAUDE.md`** — update the title line (`# CLAUDE.md — openresty-template Agent Guide`) to reflect your project
- [ ] **`README.md`** — replace this file with your project's own documentation
- [ ] **`script/api/v1/example/`** — delete the example endpoints (they are for reference only)

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

## Included Libraries

| Library | Purpose |
|---|---|
| `shared/api/response.lua` | Unified JSON/text/HTML/redirect response |
| `shared/api/webapi-client.lua` | HTTP client with OTel context propagation |
| `shared/api/tracing-helper.lua` | OTel span event helper |
| `shared/httparg.lua` | Fluent request body/query/multipart validation |
| `shared/http/client.lua` | Low-level HTTP client with retry backoff |
| `shared/object/mapper.lua` | Declarative object mapping/projection |
| `shared/json.lua` | JSON encoder/decoder with deep mapper support |
| `shared/base64url.lua` | Base64URL encode/decode |
| `resty/jwt.lua` | JWT encode/decode/verify |
| `resty/hmac.lua` | HMAC-SHA256 signing |
| `resty/otp.lua` | TOTP / HOTP one-time password |
| `resty/msgpack.lua` | MessagePack encode/decode |
| `resty/tarantool.lua` | Tarantool database client |
| `resty/lib/opentelemetry/` | Full OpenTelemetry Lua SDK |

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
| Trace data | Full request headers and body are included in OTel spans by design (B2B internal use). Restrict Jaeger access accordingly. |

## Documentation

| Document | Description |
|---|---|
| [API Development Guide](docs/api-development.md) | Endpoints, response, httparg validation, HTTP client, object mapper |
| [Routing and VHost](docs/routing.md) | File-based routing, VHost structure, custom routes, proxy pass |
| [Kubernetes Deployment](docs/kubernetes-deployment.md) | Env vars, Deployment/Service/ConfigMap manifests, health checks |
| [Plugin Development](docs/plugin-development.md) | Adding Lua libraries, FFI modules, shared dict |
| [Lua Development Guide](docs/lua-development.md) | OpenResty phases, cosocket rules, ngx.ctx, LuaJIT limits, pitfalls |

## Licence

MIT
