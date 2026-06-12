# openresty-template

> [English](README.md)

> **這是一個專案模板，請勿直接在此 repository 進行開發。**
> 請先使用 `create-project.sh` 建立新專案，再在複製後的目錄進行開發。

一個極簡、以 Docker 為核心的 OpenResty + Lua API 閘道模板。內建 OpenTelemetry 追蹤支援、流暢的請求驗證函式庫、統一的 JSON 回應層，以及多種通用服務函式庫。

## 快速導覽

| 我想要... | 看這裡 |
|---|---|
| 建立新專案 | [第一步 — 建立新專案](#第一步--建立新專案) |
| 新增 API 端點 | [新增 API 端點](#新增-api-端點) |
| 依 subdomain 或多租戶派發路由 | [docs/routing.md](docs/routing.md) |
| 把 gRPC proxy 到上游服務 | [docs/grpc.md](docs/grpc.md) |
| 提供 / 轉發 WebSocket | [docs/websocket.md](docs/websocket.md) |
| 使用 `response`、`httparg`、`mapper` 模組 | [docs/api-development.md](docs/api-development.md) |
| 新增 Lua 函式庫 / FFI / shared dict | [docs/plugin-development.md](docs/plugin-development.md) |
| 理解 OpenResty 階段、cosocket、LuaJIT 限制 | [docs/lua-development.md](docs/lua-development.md) |
| 部署到 Kubernetes | [docs/kubernetes-deployment.md](docs/kubernetes-deployment.md) |
| 本機 / K8s 設定覆寫 | `conf/local/*.sample` |
| AI agent 撰寫慣例 | [CLAUDE.md](CLAUDE.md) / [AGENTS.md](AGENTS.md) |

## 特色

- **模組化 VHost 設計** — 每個服務擁有獨立的 `.vhost` 檔案，Nginx 自動載入。
- **多 Subdomain / 多租戶就緒** — 內附 sample vhost 示範 per-subdomain 服務、wildcard 租戶派發，以及 `conf/snippets/` 共用區塊。詳見 [docs/routing.md](docs/routing.md)。
- **檔案式 Lua 路由** — 請求會自動對應到 `script/api/v1/{路徑}/{HTTP方法}.lua`。
- **Method override 安全白名單** — 支援 `X-Http-Method` / `X-Http-Method-Override`，僅允許 `GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS`，防止路徑穿越攻擊。
- **OpenTelemetry 追蹤** — `server_tracing.lua` 透過 OTLP 整合 Jaeger；只要在 vhost 裡切換一行註解就能啟用或停用。
- **流暢的請求驗證** — `shared.api.httparg` 提供型別轉換、斷言驗證與 multipart 解析；自動接線 `response.failure`，驗證失敗直接回傳 HTTP 400。
- **通用服務函式庫** — JWT、HMAC、OTP（TOTP/HOTP）、MessagePack、Tarantool client、Base64URL 等，內建於 `script/resty/`。
- **Docker 優先的開發流程** — `docker-compose.yml` 已掛載所有 Volume，在本機編輯 Lua 後只要 `docker compose restart` 就能套用。

## 專案結構

```
openresty-template/
├── conf/                 # Nginx 設定檔
│   ├── nginx.conf        # 主進入點
│   ├── nginx.vhost.inc   # 自動載入 vhost/*.vhost
│   └── local/            # 環境專屬覆寫設定（已 gitignore）
│       ├── nginx.http.cache.inc.sample     # lua_code_cache off（開發用）
│       └── nginx.http.resolver.inc.sample  # K8s CoreDNS resolver 範例
├── docs/                  # 開發文件
│   ├── api-development.md     # API 開發指南
│   ├── routing.md             # 路由與 VHost 設定
│   └── kubernetes-deployment.md # K8s 部署參考
├── script/               # Lua 腳本
│   ├── api/v1/           # API 端點（每個路由一個資料夾）
│   ├── resty/            # 第三方函式庫（JWT、HMAC、OTel、OTP、MsgPack 等）
│   ├── shared/           # 共用模組（JSON、HTTP client、response、驗證）
│   ├── config.lua        # 環境變數載入器
│   └── server_tracing.lua
├── vhost/                # Virtual Host 設定（.vhost）
│   └── default.vhost     # 範例 vhost（含路由規則）
├── Dockerfile
├── docker-compose.yml
├── test.sh               # 整合測試腳本
└── create-project.sh     # 從此模板建立新專案的腳本
```

## 使用此模板

### 第一步 — 建立新專案

```bash
./create-project.sh MyGateway /path/to/my-gateway
```

這個腳本會自動：
1. 將模板複製到目標路徑（排除 `.git` 與 `create-project.sh`）。
2. 替換 `docker-compose.yml` 的 `image` 與 `container_name`。
3. 在 `.env.sample` 設定 `SERVICE_NAME`，並自動複製為 `.env`。
4. 更新 `CLAUDE.md` 與 `AGENTS.md` 第一行標題以反映專案名稱。
5. 將 `default.vhost` 重新命名為 `{專案名稱}.vhost`。
6. 初始化全新的 Git 儲存庫並建立初始 commit（若 git 身分未設定則警告而非中止）。

### 第二步 — 初始設定

**使用 `create-project.sh` 建立的專案**（建議方式）：`.env` 已自動建立。只需：
```bash
cd /path/to/my-gateway
# 如需調整，編輯 .env（SERVICE_NAME 已預設，確認 JaegerCollector_Host 等）
docker compose up --build -d
bash test.sh               # 確認一切正常
```

**直接 clone 模板**（未使用 `create-project.sh`）：
```bash
cd /path/to/my-gateway
cp .env.sample .env        # 手動複製環境設定
# 編輯 .env，設定 SERVICE_NAME、JaegerCollector_Host 等
docker compose up --build -d
bash test.sh               # 確認一切正常
```

> 即使沒有 `.env` 也能正常啟動 — `docker-compose.yml` 設定了 `env_file.required: false`，且 `config.lua` 對所有變數都有預設值。

### 第三步 — 客製化確認清單

建立專案後，在寫入業務邏輯前請確認以下項目：

- [ ] **`.env`** — 將 `SERVICE_NAME` 改為你的專案名稱
- [ ] **`vhost/{name}.vhost`** — 確認 `listen` 埠號正確（預設 8080）
- [ ] **`docker-compose.yml`** — 確認 `image` 與 `container_name` 已更新
- [ ] **`CLAUDE.md`** — 更新標題行，改為你的專案名稱
- [ ] **`README.md`** — 以你的專案文件取代此檔案
- [ ] **`script/api/v1/example/`** — 刪除範例端點（僅供參考用）。**例外**：若啟用 `vhost/websocket.vhost.sample`，請保留 `websocket-echo.lua`。

### 開發流程

所有設定檔和 Lua 腳本都透過 Volume 掛載進容器。修改後只需：

```bash
# 在本機編輯任何 .lua / .vhost / .conf 檔案，然後：
docker compose restart
```

不需要重新打包 Image。

### 新增 API 端點

以新增 `GET /api/v1/hello` 為例：

1. 建立 `script/api/v1/hello/GET.lua`：
   ```lua
   local response = require("shared.api.response")

   response.success({
       message = "Hello, World!"
   })
   ```
2. 確認你的 `.vhost` 已包含通用的 Lua location 規則（預設已有）：
   ```nginx
   location ~ ^/api/v1/([_\-a-zA-Z0-9/]+)$ {
       content_by_lua_file "$SCRIPT_DIR/api/v1/$1/${method}.lua";
   }
   ```
3. 執行 `docker compose restart` 後即可測試。

更多 API 開發細節請參閱 [API 開發指南](docs/api-development.md)。

### 健康檢查

`/healthcheck` 回傳 `200 ok`（純文字）。  
`/ping` 回傳 `200 pong`。

兩者皆已關閉 access log，適合用於 Load Balancer 或 Docker 的 Health Check。

### 整合測試

```bash
bash test.sh                              # 預設：http://localhost:8080
bash test.sh http://staging.example.com
```

`test.sh` 分為兩個區段：**模板煙霧測試**（健康檢查、method 白名單、安全 Headers — 永遠執行）與 **example 端點測試**（偵測到 `script/api/v1/example/` 已刪除時自動跳過）。

## 內建函式庫

| 函式庫 | 用途 |
|---|---|
| `shared/api/response.lua` | 統一的 JSON / 純文字 / HTML / 導向回應 |
| `shared/api/webapi-client.lua` | HTTP Client，帶 OTel context propagation |
| `shared/api/tracing-helper.lua` | OTel span event 輔助工具 |
| `shared/api/httparg.lua` | 流暢的請求驗證入口（自動接線 `response.failure`；`shared/httparg.lua` 為 raw engine，請勿直接 require） |
| `shared/http/client.lua` | 底層 HTTP Client builder（`:uri():headers():query():body():send()`）；單次 timeout-only 重試含指數退避 |
| `shared/object/mapper.lua` | 宣告式物件映射 / 投影 |
| `shared/json.lua` | JSON encoder / decoder，支援 deep mapper |
| `shared/base64url.lua` | Base64URL 編解碼 |
| `resty/jwt.lua` | JWT 編碼 / 解碼 / 驗證 |
| `resty/hmac.lua` | HMAC-SHA256 簽名 |
| `resty/otp.lua` | TOTP / HOTP 一次性密碼 |
| `resty/msgpack.lua` | MessagePack 編解碼 |
| `resty/tarantool.lua` | Tarantool 資料庫 client |
| `resty/lib/opentelemetry/` | 完整的 OpenTelemetry Lua SDK |
| `resty.websocket`（內建） | WebSocket server 與 client — 來自 OpenResty 基礎映像，無需另行安裝 |

## 設定

環境變數在 `script/script.env.conf` 中宣告，並由 `script/config.lua` 讀取。

| 變數 | 預設值 | 說明 |
|---|---|---|
| `SERVICE_NAME` | `GatewayTemplate` | 服務名稱，用於 OTel trace resource |
| `BUILD_COMMIT_TAG` | — | 建置時注入的 Git tag |
| `BUILD_COMMIT_SHA` | — | 建置時注入的 Git SHA |
| `JaegerCollector_Host` | `127.0.0.1` | Jaeger OTLP collector 主機 |
| `JaegerCollector_OTLPHttpPort` | `4318` | Jaeger OTLP HTTP 埠號 |

## 安全說明

| 主題 | 行為 |
|---|---|
| Method override | `X-Http-Method` / `X-Http-Method-Override` 會過白名單驗證，非法值回傳 405。 |
| DNS resolver | 預設使用 `127.0.0.11`（Docker 內建 DNS）。K8s 環境請複製 `conf/local/nginx.http.resolver.inc.sample` 並設定 cluster DNS。 |
| 容器使用者 | 以 `nobody`（非 root）執行。Port 8080 不需要特權。 |
| Server header | 所有回應皆透過 `more_clear_headers Server` 移除。 |
| Trace 資料 | OTel span 記錄完整 request line、所有 header 與 body。`Authorization`、`Cookie`、`Set-Cookie`、`Proxy-Authorization` 的 header 值自動遮蔽為 `[REDACTED]`，其餘值與完整 body 以明文儲存（B2B 內部除錯用途）。請確保 Jaeger 存取受到妥善管控。 |

## 文件

| 文件 | 說明 |
|---|---|
| [API 開發指南](docs/api-development.md) | 端點建立、Response、httparg 驗證、HTTP Client、Object Mapper |
| [路由與 VHost 設定](docs/routing.md) | File-based routing、VHost 結構、自定義路由、Proxy Pass |
| [gRPC Gateway](docs/grpc.md) | HTTP/2、`grpc_pass`、TLS、Lua 認證 |
| [WebSocket](docs/websocket.md) | Lua WS server + proxy 模式、frame 類型、常見坑 |
| [Kubernetes 部署參考](docs/kubernetes-deployment.md) | 環境變數、Deployment/Service/ConfigMap manifest、健康檢查 |
| [插件與函式庫新增](docs/plugin-development.md) | 新增 Lua 函式庫、FFI 模組、共用記憶體 |
| [Lua 開發指南](docs/lua-development.md) | OpenResty 執行階段、cosocket 規則、ngx.ctx、LuaJIT 限制、常見陷阱 |

## 授權條款

MIT
