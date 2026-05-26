# 路由與 VHost 設定指南

本文件說明 OpenResty Gateway 模板的路由機制與 VHost 設定方式。

---

## 路由機制

### File-Based Routing

本模板使用 **檔案式路由**：所有 API 請求根據 URL 路徑與 HTTP Method 自動映射到對應的 Lua 檔案。

```
URL 路徑:   /api/v1/{path}
HTTP Method: GET / POST / PUT / PATCH / DELETE
對應檔案:    script/api/v1/{path}/{METHOD}.lua
```

此機制由 VHost 的 location 規則驅動：

```nginx
location ~ ^/api/v1/([_\-a-zA-Z0-9/]+)$ {
    set $method $request_method;
    content_by_lua_file "$SCRIPT_DIR/api/v1/$1/${method}.lua";
}
```

### URL 規則

- 路徑僅允許 `a-z A-Z 0-9 _ - /`
- Method 對應：`GET.lua`, `POST.lua`, `PUT.lua`, `PATCH.lua`, `DELETE.lua`
- 不存在的路徑或 Method 會回傳 Nginx 預設的 404/500

### 路由範例

| 請求 | 對應檔案 |
|---|---|
| `GET /api/v1/hello` | `script/api/v1/hello/GET.lua` |
| `POST /api/v1/user` | `script/api/v1/user/POST.lua` |
| `GET /api/v1/user/profile` | `script/api/v1/user/profile/GET.lua` |
| `DELETE /api/v1/order/123` | ❌ 不支援（含數字路徑需另設 location） |

### HTTP Method Override

支援透過 header 覆蓋 HTTP Method：

```
X-HTTP-Method: DELETE
X-HTTP-Method-Override: PATCH
```

---

## VHost 設定

### 結構

VHost 檔案位於 `vhost/` 目錄，副檔名 `.vhost`，Nginx 會自動載入：

```
vhost/
├── default.vhost        # 預設 VHost（模板範例）
├── api-gateway.vhost    # 可新增多個 VHost
└── admin.vhost          # 每個 VHost 可監聽不同 port
```

載入由 `conf/nginx.vhost.inc` 驅動：

```nginx
include '../vhost/*.vhost';
```

### 預設 VHost 結構

```nginx
server {
    listen       8080;
    server_name  localhost;

    # 資源限制
    client_max_body_size  4m;
    client_body_buffer_size 1m;

    # 安全 Headers
    add_header X-Content-Type-Options  nosniff  always;
    add_header X-Frame-Options         DENY     always;
    add_header Referrer-Policy         strict-origin-when-cross-origin always;
    more_clear_headers                 Server;

    root "";
    set  $SCRIPT_DIR  "${realpath_root}/script";

    # 預設 404
    location / {
        return 404;
    }

    # Health Check（不記錄 access log）
    location = /healthcheck { ... }
    location = /ping { ... }

    # API 路由
    location ~ ^/api/v1/([_\-a-zA-Z0-9/]+)$ {
        content_by_lua_file "$SCRIPT_DIR/api/v1/$1/${method}.lua";
    }
}
```

### 新增 VHost

建立新檔案如 `vhost/admin.vhost`：

```nginx
server {
    listen       9090;
    server_name  localhost;

    client_max_body_size 1m;

    add_header X-Content-Type-Options  nosniff  always;
    add_header X-Frame-Options         DENY     always;
    more_clear_headers                 Server;

    root "";
    set  $SCRIPT_DIR  "${realpath_root}/script";

    location / {
        return 404;
    }

    location ~ ^/admin/api/v1/([_\-a-zA-Z0-9/]+)$ {
        default_type 'application/json;charset=utf-8';
        set $method $request_method;
        content_by_lua_file "$SCRIPT_DIR/admin/v1/$1/${method}.lua";
    }
}
```

新增的 port 要同步加到 `docker-compose.yml` 的 `ports` 區段。

---

## 自定義路由

### 靜態路由

對於特定路徑不走 file-based routing：

```nginx
location = /api/v1/webhook/stripe {
    default_type 'application/json;charset=utf-8';
    content_by_lua_file "$SCRIPT_DIR/webhook/stripe.lua";
}
```

### 帶 ID 參數的路由

file-based routing 的正規表達式不允許純數字路徑段。如需 `/api/v1/user/{id}`：

```nginx
location ~ ^/api/v1/user/(\d+)$ {
    default_type 'application/json;charset=utf-8';
    set $user_id $1;
    set $method $request_method;
    content_by_lua_file "$SCRIPT_DIR/api/v1/user-by-id/${method}.lua";
}
```

在 Lua 裡取得參數：

```lua
local user_id = ngx.var.user_id
```

### Proxy Pass

如需反向代理到後端服務：

```nginx
location /api/backend/ {
    proxy_pass http://backend-service:3000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

---

## 多服務 / 多 Subdomain 路由

本模板透過 Nginx 原生的 `server_name` 機制支援多 subdomain / 多 domain 派發。
依據使用情境，有三種典型模式可選：

| 模式 | 適用情境 | 範例檔 |
|---|---|---|
| **A. 多 VHost，一服務一檔** | 不同 subdomain 對應完全不同的服務（admin / api / webhook 程式碼互相獨立） | `vhost/api.vhost.sample`、`vhost/admin.vhost.sample` |
| **B. 單 VHost + Wildcard subdomain** | 同一套 API，依 subdomain 切租戶（multi-tenant） | `vhost/multi-tenant.vhost.sample` |
| **C. Default server + Lua dispatch** | 多 domain 動態派發（不需 nginx reload） | 文件範例，無 sample |

### 選擇依據

```
   是否每個 subdomain 對應完全不同的程式碼？
   ├─ 是 → Pattern A（多 VHost）
   │       └─ 是否需要不同 port / 不同安全策略？
   │           ├─ 是 → 每個 vhost 用獨立 port（admin.vhost.sample 範例）
   │           └─ 否 → 共用 port 8080，靠 server_name 派發
   │
   ├─ 否，是同一套 API，但要識別租戶 → Pattern B（Wildcard subdomain）
   │
   └─ 否，要支援未來新增 domain 不 reload → Pattern C（Lua dispatch）
```

### Pattern A：多 VHost

**啟用範例：**
```bash
mv vhost/api.vhost.sample vhost/api.vhost
mkdir -p script/services/api/v1/hello
cp script/api/v1/hello/GET.lua script/services/api/v1/hello/GET.lua
docker compose restart
curl -H "Host: api.example.com" http://localhost:8080/api/v1/hello
```

關鍵設計：
- 每個 vhost 設自己的 `$SCRIPT_DIR`，指向獨立的服務目錄（如 `script/services/api`）
- 共用 port（如 8080）時，Nginx 依 `server_name` 自動派發
- 需要物理隔離時，改用獨立 port（`admin.vhost.sample` 用 9090），記得在 `docker-compose.yml` 開對應 port
- 未匹配的 Host header 會落到 `default.vhost`（list 中第一個 `listen 8080` 的 server block）

### Pattern B：Wildcard Subdomain

**啟用範例：**
```bash
mv vhost/multi-tenant.vhost.sample vhost/multi-tenant.vhost
docker compose restart
curl -H "Host: acme.api.example.com" http://localhost:8080/api/v1/hello
curl -H "Host: customer-x.api.example.com" http://localhost:8080/api/v1/hello
```

關鍵設計：
- `server_name ~^(?<tenant>[^.]+)\.api\.example\.com$;` 用命名 capture group
- Nginx 把 `tenant` capture 變成可用變數，Lua 透過 `ngx.var.tenant` 讀取
- 同一套 `script/api/v1/...` 端點，租戶區隔在 Lua 層處理

**Lua 端點範例：**
```lua
local response = require("shared.api.response")

local tenant = ngx.var.tenant
if not tenant or tenant == "" then
    return response.failure("INVALID_TENANT", "missing subdomain")
end

-- 用 tenant 查租戶設定、過濾資料、產生 audit log
response.success({ tenant = tenant, data = ... })
```

### Pattern C：Default Server + Lua Dispatch

適合 domain 數量會頻繁變動、不希望每次都 reload nginx 的場景。

**示意：**
```nginx
server {
    listen       8080 default_server;
    server_name  _;

    set $SCRIPT_DIR "${realpath_root}/script";

    location ~ ^/api/v1/([_\-a-zA-Z0-9/]+)$ {
        default_type 'application/json;charset=utf-8';
        set $method $request_method;

        access_by_lua_block {
            -- 從 ngx.shared.dict 或 config 模組查 host → 服務映射
            local host = ngx.var.host
            local service = require("shared.domain-router").resolve(host)
            if not service then
                ngx.status = 404
                return ngx.exit(ngx.OK)
            end
            ngx.var.target_service = service
        }

        content_by_lua_file "$SCRIPT_DIR/services/${target_service}/v1/$1/${method}.lua";
    }
}
```

代價：
- 每個請求多一次 Lua 查表
- domain 路由表需自己維護（環境變數、ConfigMap、Redis 等）
- 不適合純效能優先的場景

模板不附 sample；需要時可依上述骨架實作 `shared/domain-router.lua`。

---

## 共用 snippets（DRY）

多 vhost 容易在安全 headers、method 白名單、health check 上重複造輪子。
模板把這三個共用區塊抽到 `conf/snippets/`：

```
conf/snippets/
├── server-defaults.inc           # body 限制 + 安全 Headers（server scope）
├── server-health.inc             # /healthcheck、/ping、預設 404（server scope）
└── access-method-allowlist.inc   # HTTP method 白名單（location scope）
```

在 vhost 中以 `include 'snippets/xxx.inc';` 載入。路徑相對於 `conf/` 目錄（nginx 設定檔目錄）。

預設 vhost (`vhost/default.vhost`) 與三個 `.vhost.sample` 都展示了這個用法。

> 不抽出 `location ~ ^/api/v1/...` 整塊 —— 各 vhost 的 `$SCRIPT_DIR`、路徑前綴、tracing 開關常需差異化，硬抽會限制彈性。

---

## 可選的 services 目錄結構

多服務場景下，建議把端點程式碼依服務分目錄：

```
script/
├── api/v1/              # 預設（單服務專案沿用）
└── services/            # 多服務專案的選項
    ├── api/v1/
    ├── admin/v1/
    └── webhook/v1/
```

各 vhost 用不同 `$SCRIPT_DIR` 切換：
```nginx
set $SCRIPT_DIR "${realpath_root}/script/services/api";
content_by_lua_file "$SCRIPT_DIR/v1/$1/${method}.lua";
```

這是純命名慣例，不需改 Lua 程式碼，也不影響 `shared/` 與 `resty/` 的引用路徑（兩者仍透過 `lua_package_path` 全域可見）。

---

## Nginx 設定結構

```
conf/
├── nginx.conf          # 主設定（worker_processes、gzip、resolver 等）
├── nginx.main.inc      # 引入 script/script.env.conf（env 變數宣告）
├── nginx.vhost.inc     # 引入 script/script.conf 和 vhost/*.vhost
└── mime.types          # MIME 型別
```

### 重要設定項

| 設定 | 位置 | 說明 |
|---|---|---|
| `worker_processes` | nginx.conf | 預設 `auto`，自動偵測 CPU 核心數 |
| `lua_code_cache` | nginx.conf | 預設 `on`，開發時改 `off` 可免 restart |
| `lua_package_path` | script/script.conf | Lua 模組搜尋路徑 |
| `lua_shared_dict` | script/script.conf | 跨 worker 共用記憶體宣告 |
| `resolver` | nginx.conf | DNS resolver，預設 `127.0.0.11`（Docker 內建 DNS）；K8s 環境見 `conf/local/nginx.http.resolver.inc.sample` |
| `server_tokens` | nginx.conf | 預設 `off`，隱藏 Nginx 版本號 |

### 開發模式

關閉 Lua code cache 可以即時看到 Lua 修改（不需 restart），但效能會大幅下降：

```nginx
# conf/nginx.conf
lua_code_cache  off;  # 僅限開發環境
```

### 本地設定覆蓋

`conf/local/` 目錄可放置本地開發的額外設定：

```nginx
# conf/nginx.conf 的最後一行會載入
include  'local/nginx.http*.inc';
```

使用方式：建立 `conf/local/nginx.http.dev.inc`，內容例如：

```nginx
# 開發用途：額外的 upstream 或設定
upstream dev_backend {
    server host.docker.internal:3000;
}
```

此目錄已在 `.gitignore` 中排除。
