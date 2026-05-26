-- WebSocket Echo Server 範例
--
-- Source: https://github.com/openresty/lua-resty-websocket
--
-- 用法：在 vhost 中以 `content_by_lua_file "$SCRIPT_DIR/api/v1/example/websocket-echo.lua";` 引用本檔。
-- 配合 `vhost/websocket.vhost.sample` 即可運行。
--
-- 收到 text / binary frame 後原樣 echo 回去；
-- 收到 close 結束 loop；recv timeout 時主動送 ping 維持連線。
--
-- 注意：
--   - 本檔不走 file-based routing（不在 /api/v1/... 的命名空間內）。
--     檔名取 `websocket-echo.lua` 是因為 vhost 用絕對路徑 content_by_lua_file 引用。
--   - 若 client 中斷，`wb:recv_frame()` 會回 fatal；要設定 `lua_check_client_abort on;`。

local server = require("resty.websocket.server")

local wb, err = server:new({
    timeout         = 60000,       -- 60s read timeout（recv_frame 沒資料時觸發）
    max_payload_len = 65535,        -- 單個 frame 上限 64KB；超出自動 close
})
if not wb then
    ngx.log(ngx.ERR, "ws: failed to new websocket server: ", err)
    return ngx.exit(444)
end

while true do
    local data, typ, recv_err = wb:recv_frame()

    if wb.fatal then
        ngx.log(ngx.ERR, "ws: fatal error: ", recv_err)
        return ngx.exit(444)
    end

    if not data then
        -- 非 fatal：通常是 read timeout。主動送 ping 維持連線。
        local _, ping_err = wb:send_ping()
        if ping_err then
            ngx.log(ngx.ERR, "ws: send_ping failed: ", ping_err)
            break
        end

    elseif typ == "close" then
        break

    elseif typ == "ping" then
        local _, pong_err = wb:send_pong(data)
        if pong_err then
            ngx.log(ngx.ERR, "ws: send_pong failed: ", pong_err)
            break
        end

    elseif typ == "pong" then
        -- client 對先前的 ping 回應；忽略即可

    elseif typ == "text" then
        local _, send_err = wb:send_text(data)
        if send_err then
            ngx.log(ngx.ERR, "ws: send_text failed: ", send_err)
            break
        end

    elseif typ == "binary" then
        local _, send_err = wb:send_binary(data)
        if send_err then
            ngx.log(ngx.ERR, "ws: send_binary failed: ", send_err)
            break
        end
    end
end

wb:send_close()
