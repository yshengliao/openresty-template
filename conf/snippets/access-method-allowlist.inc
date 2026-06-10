# Method 白名單：防止路徑穿越攻擊，限制合法 HTTP method
# 使用方式：在 location { ... } block 內 `include 'snippets/access-method-allowlist.inc';`
# 前提：呼叫端的 location 已先 `set $method $request_method;` 並處理 X-Http-Method override
# 注意：method 值會自動正規化為大寫（大小寫不敏感），並寫回 $method 供後續路由使用

access_by_lua_block {
    local allowed = {GET=1,POST=1,PUT=1,PATCH=1,DELETE=1,HEAD=1,OPTIONS=1}
    local m = string.upper(ngx.var.method or "")
    if not allowed[m] then
        ngx.status = 405
        ngx.header.content_type = 'application/json; charset=utf-8'
        ngx.print('{"code":"UNSUPPORTED","message":"Method not allowed"}')
        return ngx.exit(ngx.OK)
    end
    ngx.var.method = m
    -- 鏈路追蹤（如需啟用，解除以下註解）
    -- require("server_tracing").start()
}
