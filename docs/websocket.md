# WebSocket 設定指南

本文件示範兩種在 OpenResty 中使用 WebSocket 的模式：**OpenResty 作 WebSocket server**（Lua 處理 frames）與 **OpenResty 作 proxy**（轉發到上游）。所有語法引用自官方文件，避免猜測。

> **權威來源：**
> - `lua-resty-websocket`：[github.com/openresty/lua-resty-websocket](https://github.com/openresty/lua-resty-websocket)
> - Nginx WebSocket proxy：[nginx.org/en/docs/http/websocket.html](https://nginx.org/en/docs/http/websocket.html)

---

## 兩種模式比較

| 模式 | 適用 | OpenResty 角色 |
|---|---|---|
| **A. Lua server** | 簡單即時功能（聊天、通知 push、echo、命令派發） | 直接接受連線、解 / 送 frames |
| **B. Proxy** | 既有 WS 後端（Node.js、Go、Erlang）放在 OpenResty 後面，做認證 / 限流 / TLS | 轉發 frames，不解內容 |

兩種模式可同時存在於同一個 vhost 的不同 `location`。

---

## Pattern A：OpenResty 作 WS Server

### Nginx 設定

```nginx
location = /ws/echo {
    lua_check_client_abort  on;     # client 斷線時觸發 abort handler，避免 zombie loop
    lua_socket_log_errors   off;    # 抑制預期的 closed / timeout 噪音（開發期建議 on）
    content_by_lua_file     "$SCRIPT_DIR/api/v1/example/websocket-echo.lua";
}
```

### Lua Echo Server

```lua
local server = require("resty.websocket.server")

local wb, err = server:new({
    timeout         = 60000,     -- 60s read timeout
    max_payload_len = 65535,     -- 64KB
})
if not wb then
    ngx.log(ngx.ERR, "ws: new failed: ", err)
    return ngx.exit(444)
end

while true do
    local data, typ, recv_err = wb:recv_frame()
    if wb.fatal then
        ngx.log(ngx.ERR, "ws: fatal: ", recv_err)
        return ngx.exit(444)
    end
    if not data then
        -- 沒資料但非 fatal：通常是 read timeout，主動 ping
        wb:send_ping()
    elseif typ == "close" then
        break
    elseif typ == "ping" then
        wb:send_pong(data)
    elseif typ == "text" then
        wb:send_text(data)
    elseif typ == "binary" then
        wb:send_binary(data)
    end
end
wb:send_close()
```

完整可運行版本：[`script/api/v1/example/websocket-echo.lua`](../script/api/v1/example/websocket-echo.lua)

### Frame Types

`wb:recv_frame()` 回傳 `(data, typ, err)`，`typ` 可能是：

| typ | 說明 |
|---|---|
| `"text"` | UTF-8 文字 frame |
| `"binary"` | 二進位 frame |
| `"ping"` | client 的 ping（應該 `send_pong(data)` 回應） |
| `"pong"` | client 對先前 ping 的回應；通常忽略 |
| `"close"` | client 主動關閉；應 break loop |
| `"continuation"` | 多 frame 訊息的中段；通常 lua-resty-websocket 已組合好 |

### 發送 API

| 方法 | 說明 |
|---|---|
| `wb:send_text(s)` | 送文字 frame |
| `wb:send_binary(b)` | 送二進位 frame |
| `wb:send_ping([data])` | 主動 ping |
| `wb:send_pong(data)` | 回應 client ping |
| `wb:send_close([code], [msg])` | 主動關閉；常用 code 1000（normal）、1011（server error） |

---

## Pattern B：Proxy WebSocket 到上游

### `map` directive

WebSocket Upgrade 需要把 HTTP `Upgrade` header 對映成 nginx `Connection` header：

```nginx
# 必須在 http {} scope；server {} 上方或包進獨立的 .conf 都行
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
```

### Location 設定

```nginx
location = /ws/proxy {
    proxy_pass          http://backend:9000;
    proxy_http_version  1.1;                          # WS handshake 必須 HTTP/1.1
    proxy_set_header    Upgrade    $http_upgrade;
    proxy_set_header    Connection $connection_upgrade;
    proxy_set_header    Host       $host;
    proxy_read_timeout  3600s;                         # 避免閒置 60s 後被關掉
}
```

`proxy_read_timeout` 預設 60s，long-lived WS 很容易被切掉，依需求拉長（或在 client/server 兩端送 ping）。

---

## 常見坑（GitHub Issues 整理）

| 問題 | 解法 |
|---|---|
| log 一直噴 `closed`、`timeout` | location 加 `lua_socket_log_errors off;`（**只在已 verified 的 production**） |
| Client 中斷沒被偵測 → 卡 loop | 加 `lua_check_client_abort on;` |
| `recv_frame()` 偶爾沒資料 | 檢查 `wb.fatal`；非 fatal 通常是 timeout，可送 ping 保活 |
| 60 秒後連線自動斷 | Pattern B：`proxy_read_timeout` 拉長；Pattern A：`timeout` 拉長 + 定期 ping |
| 在 `ngx.timer` 內想 send frame | **不行**。`wb` 物件綁定在 `content_by_lua_file` context；timer 內要用 client 模式或共享 dict 中轉 |

---

## 安全注意事項

- WS 沒有 SOP（Same-Origin Policy）的瀏覽器自動保護；要在 `access_by_lua_block` 驗證 `ngx.var.http_origin` 或自訂 token
- 模板的 `snippets/access-method-allowlist.inc` **不適用** WS endpoint：WS 用 GET + Upgrade，會被 method allowlist 通過，但你可能想要更嚴格的 origin / auth 檢查
- `max_payload_len` 上限要明確設定，避免被巨大 frame 拖垮記憶體

---

## WebSocket Client（Outbound）

OpenResty 也可以**主動發起** WebSocket 連線（例如轉發到外部 WS API）：

```lua
local client = require("resty.websocket.client")
local wb = client:new()
local ok, err = wb:connect("ws://upstream:9000/path")
if not ok then
    ngx.log(ngx.ERR, "ws connect failed: ", err)
    return
end
wb:send_text("hello")
local data, typ = wb:recv_frame()
wb:close()
```

詳見 [lua-resty-websocket client docs](https://github.com/openresty/lua-resty-websocket#restywebsocketclient)。

---

## 啟用範例

範例設定：[`vhost/websocket.vhost.sample`](../vhost/websocket.vhost.sample)
範例 Lua endpoint：[`script/api/v1/example/websocket-echo.lua`](../script/api/v1/example/websocket-echo.lua)

> **注意**：`websocket-echo.lua` 是 file-based routing 的**例外**。它不是 `METHOD.lua` 格式的檔案，而是由 `vhost/websocket.vhost.sample` 的 `content_by_lua_file` 明確指向它。如果你啟用了此 vhost sample，清理專案時請保留此檔案（不要在「刪除 example 端點」步驟時一起刪掉）。
>
> `resty.websocket.server` 與 `resty.websocket.client` 來自 OpenResty 基礎映像，已內建，無需另外安裝。

```bash
mv vhost/websocket.vhost.sample vhost/websocket.vhost
docker compose restart

# 用 curl 驗證 Upgrade（看到 101 即成功）
curl -sv -H "Host: ws.example.com" \
     -H "Upgrade: websocket" -H "Connection: Upgrade" \
     -H "Sec-WebSocket-Version: 13" \
     -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
     http://localhost:8080/ws/echo

# 或 websocat 雙向測試
websocat ws://ws.example.com:8080/ws/echo   # 需 /etc/hosts 對映
```
