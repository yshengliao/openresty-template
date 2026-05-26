# gRPC Gateway 設定指南

本文件說明如何用 OpenResty 作為 gRPC 反向代理。所有語法引用自 nginx 官方文件，避免猜測。

> **權威來源：** [nginx.org/en/docs/http/ngx_http_grpc_module.html](https://nginx.org/en/docs/http/ngx_http_grpc_module.html)

---

## 適用場景

OpenResty 在 gRPC 架構中通常扮演 **gateway / 反向代理**：
- 集中認證、限流、路由分派
- 統一觀測性（access log、tracing）
- 為內網 gRPC 服務做 TLS termination

**不適合做的事：**
- **在 Lua 內實作 gRPC server**：原生 OpenResty 沒有 server-side gRPC 框架；社群有 `lua-resty-grpc-gateway` 等專案但成熟度有限
- **解析 / 改寫 gRPC body**：binary length-prefixed framing，body_filter_by_lua_* 容易破壞訊息結構

---

## 啟用 HTTP/2

gRPC 強制使用 HTTP/2。Nginx 1.25+ 用獨立指令啟用：

```nginx
server {
    listen 50051;
    http2  on;        # 必要
    ...
}
```

> 舊語法 `listen 50051 http2;` 仍相容，但官方建議改用 `http2 on;`。

---

## 最小設定

```nginx
server {
    listen 50051;
    http2  on;

    location / {
        grpc_pass grpc://backend:50051;     # 上游 gRPC 服務
    }
}
```

幾個關鍵點：
- `grpc_pass` 取代 `proxy_pass`；**不要**再寫 `proxy_http_version` / `proxy_set_header`
- protocol 前綴：明文用 `grpc://`，TLS 用 `grpcs://`
- 預設會自動帶 `Content-Length`、`Content-Type: application/grpc`

---

## 延遲 DNS（推薦）

直接寫 `grpc_pass grpc://backend:50051;` 會在 nginx 啟動時做 DNS 解析；上游不存在會 fail-fast 阻止啟動。
正式環境用 K8s service / Docker DNS 時，建議用變數延遲到 request time：

```nginx
location / {
    set $grpc_upstream "backend:50051";
    grpc_pass grpc://$grpc_upstream;
}
```

此模式仰賴 `nginx.conf` 已宣告的 `resolver`（本模板預設 `127.0.0.11`，Docker 內建 DNS）。

---

## 注入 Metadata Header

gRPC metadata 是 HTTP/2 header；用 `grpc_set_header` 注入：

```nginx
location / {
    grpc_pass         grpc://$grpc_upstream;
    grpc_set_header   X-Real-IP   $remote_addr;
    grpc_set_header   X-Forwarded-Host $host;
}
```

---

## 在 gRPC 前做認證（Lua）

`access_by_lua_block` 在 `grpc_pass` 前執行，可讀 headers / metadata 並決定放行或拒絕：

```nginx
location / {
    access_by_lua_block {
        local auth = ngx.var.http_authorization
        if not auth or auth ~= "Bearer expected-token" then
            ngx.status = ngx.HTTP_UNAUTHORIZED
            return ngx.exit(ngx.HTTP_UNAUTHORIZED)
        end
    }
    grpc_pass grpc://$grpc_upstream;
}
```

注意：
- HTTP 狀態碼會被轉成相應的 gRPC status（401 → `UNAUTHENTICATED`）
- 不能在 access phase 修改 body —— gRPC 訊息還沒組好
- 想注入新 metadata 給上游，用 `grpc_set_header`，不要直接改 `ngx.req.set_header`

---

## TLS

上游使用 TLS：

```nginx
location / {
    grpc_pass                       grpcs://$grpc_upstream;
    grpc_ssl_verify                 on;
    grpc_ssl_trusted_certificate    /path/to/ca.crt;
    grpc_ssl_server_name            on;
    grpc_ssl_name                   backend.internal.example.com;
}
```

對外提供 TLS：在 `listen` 加 `ssl`：

```nginx
listen     50051 ssl;
http2      on;
ssl_certificate     /path/to/server.crt;
ssl_certificate_key /path/to/server.key;
```

---

## 逾時設定

| 指令 | 預設 | 建議 |
|---|---|---|
| `grpc_connect_timeout` | 60s | 5~10s |
| `grpc_send_timeout` | 60s | 依資料量 |
| `grpc_read_timeout` | 60s | streaming 場景拉到 300s+ |

```nginx
location / {
    grpc_pass         grpc://$grpc_upstream;
    grpc_connect_timeout 10s;
    grpc_send_timeout    60s;
    grpc_read_timeout    300s;
}
```

---

## 啟用範例

範例設定：[`vhost/grpc.vhost.sample`](../vhost/grpc.vhost.sample)

```bash
mv vhost/grpc.vhost.sample vhost/grpc.vhost
# docker-compose.yml ports 區段加上 "50051:50051"
docker compose up -d

# 用 grpcurl 測試
grpcurl -plaintext -d '{}' localhost:50051 your.package.Service/Method
```

---

## 常見錯誤

| 症狀 | 可能原因 |
|---|---|
| `nginx: [emerg] host not found in upstream` | DNS 啟動解析失敗。改用變數延遲解析（見上方） |
| `upstream rejected request with error 2` | 上游不支援 HTTP/2 或回了非 gRPC 內容 |
| `502 Bad Gateway` | 上游不可達；檢查 `resolver` 與網路連通性 |
| 連線一直 hang | 防火牆擋 HTTP/2；或上游期望 TLS，但用了 `grpc://` |
| `client sent unsupported HTTP/0.9 request` | 用 HTTP/1.1 client 打到 `http2 on;` 的 server。gRPC client 才會正確 negotiate |

---

## 限制

- gRPC streaming（client-stream / server-stream / bidi）都支援；長連線記得拉長 `grpc_read_timeout`
- 不支援 gRPC-Web；要轉接 gRPC-Web ↔ gRPC 需用 [`grpc-web`](https://github.com/grpc/grpc-web) 或 Envoy 之類專門做這件事
- Lua body_filter / header_filter 不該動 gRPC body（binary framing）；要改 payload 內容請在上游做
