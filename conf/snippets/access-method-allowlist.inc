# Method 白名單：防止路徑穿越攻擊，限制合法 HTTP method
# 使用方式：在 location { ... } block 內 `include 'snippets/access-method-allowlist.inc';`
# 前提：呼叫端的 location 已先 `set $method $request_method;` 並處理 X-Http-Method override

access_by_lua_block {
    local allowed = {GET=1,POST=1,PUT=1,PATCH=1,DELETE=1,HEAD=1,OPTIONS=1}
    if not allowed[ngx.var.method] then
        ngx.status = 405
        ngx.header.content_type = 'application/json; charset=utf-8'
        ngx.print('{"message":"UNSUPPORTED","description":"Method not allowed"}')
        return ngx.exit(ngx.OK)
    end
    -- 鏈路追蹤（如需啟用，解除以下註解）
    -- require("server_tracing").start()
}
