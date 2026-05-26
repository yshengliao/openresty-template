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
