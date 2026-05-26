# API 開發指南

本文件說明如何在此 OpenResty Gateway 模板上開發 API 端點，著重 `response` / `httparg` / `webapi-client` / `mapper` 模組的實際用法。

> 路由規則本身（file-based mapping、VHost 結構、多 subdomain）請見 [`docs/routing.md`](routing.md)。

---

## 建立新端點

### 步驟一：建立 Lua 檔案

在 `script/api/v1/` 下依路徑建立目錄，檔名為 **大寫的 HTTP Method**：

```
script/api/v1/
├── hello/
│   └── GET.lua          # GET /api/v1/hello
├── user/
│   ├── GET.lua          # GET /api/v1/user
│   └── POST.lua         # POST /api/v1/user
└── user/profile/
    └── GET.lua          # GET /api/v1/user/profile
```

### 步驟二：撰寫端點邏輯

最基本的端點：

```lua
local response = require("shared.api.response")

response.success({
    message = "Hello, World!"
})
```

### 步驟三：套用變更

```bash
docker compose restart
```

Volume 掛載方式不需要重新 build image。

---

## Response 模組

`shared/api/response.lua` 提供統一的回應介面：

### JSON 成功回應

```lua
local response = require("shared.api.response")

response.success({
    user_id = 123,
    name    = "demo"
})
-- HTTP 200, Content-Type: application/json
-- 自動加入 timestamp 欄位
```

### 錯誤回應

```lua
local response = require("shared.api.response")
local def      = require("shared.api.def")

-- 使用預定義錯誤碼
response.failure(def.ERROR_CODE.INVALID_ARGUMENT, "user_id is required")
-- HTTP 400, Content-Type: application/json

-- 或用 response.error() 自動判斷錯誤格式
response.error("PERMISSION_DENIED")
response.error({ message = "TOKEN_EXPIRED", description = "token has expired" })
```

### 純文字 / HTML / 導向

```lua
response.print("ok")                    -- text/plain
response.html("<h1>Hello</h1>")         -- text/html
response.redirect("https://example.com") -- 302 redirect
```

### 預定義錯誤碼

`shared/api/def.lua` 列出常用錯誤碼：

| 錯誤碼 | 用途 |
|---|---|
| `INVALID_ARGUMENT` | 參數格式或值不合法 |
| `PERMISSION_DENIED` | 無存取權限 |
| `INVALID_TOKEN` | Token 無效 |
| `TOKEN_EXPIRED` | Token 已過期 |
| `MISSING_PRINCIPAL` | 缺少身分資訊 |
| `DUPLICATE_OPERATION` | 重複操作 |

---

## 請求驗證 (httparg)

`shared/api/httparg.lua` 提供流暢式（fluent）的請求驗證：

### 基本用法

```lua
local httparg  = require("shared.api.httparg")
local response = require("shared.api.response")

local tag = httparg.tag()

-- 讀取 JSON body 欄位
local json = tag.json
local name = json.name("required", "string")
local age  = json.age("number")

-- 讀取 query string
local page = tag.query.page("number")

-- 讀取 header
local token = tag.header.authorization("required", "string")
```

### 型別處理器 (handlers)

以字串形式傳入，支援鏈式組合：

| Handler | 說明 |
|---|---|
| `"required"` | 必填，nil 時報錯 |
| `"string"` | 轉為字串 |
| `"number"` | 轉為數值 |
| `"boolean"` | 轉為布林值（支援 "true"/"false"/"yes"/"no"） |
| `"date"` | 解析 `YYYY-MM-DD` 格式 |
| `"datetime"` | 解析 `YYYY-MM-DD HH:MM:SS` 格式 |
| `"json"` | 解析 JSON 字串 |
| `"array"` | 驗證為陣列 |
| `"map"` | 驗證為 map（非陣列的 table） |
| `"any"` | 不做型別轉換，僅確認非 nil |

### 斷言 (assertions)

用於額外的值約束驗證：

```lua
local assertion = httparg.assertion

-- 字串必須是指定值之一
local status = json.status("required", "string",
    assertion.string_should_in("active", "inactive", "pending"))

-- 數值限制最大值
local limit = tag.query.limit("number", assertion.max(100))

-- 非空字串
local name = json.name("required", "string", assertion.non_empty_string())

-- 非負數
local amount = json.amount("number", assertion.non_negative_number())

-- 非 NaN / Infinity
local score = json.score("number", assertion.non_nan_nor_inf())
```

### 多來源讀取

```lua
local tag = httparg.tag()

-- JSON body
local json = tag.json
local data = json.field_name("required", "string")

-- Query string
local query = tag.query
local page  = query.page("number")

-- Form POST (application/x-www-form-urlencoded)
local form = tag.form
local name = form.username("required", "string")

-- Multipart form-data
local part = tag.part
local file = part.avatar("required")

-- Request header
local header = tag.header
local auth   = header.authorization("required", "string")

-- Raw body text
local body = tag.text
local raw  = body("required", "string")
```

---

## HTTP Client

### WebAPI Client（含 OTel propagation）

```lua
local webapi   = require("shared.api.webapi-client")
local response = require("shared.api.response")

local client = webapi.new({
    host    = "http://backend-service:3000",
    timeout = 5000,
})

local resp = client:do_request({
    method  = "POST",
    path    = "/internal/users",
    body    = { name = "demo" },
    headers = { ["X-Request-Id"] = ngx.var.request_id },
})

local result, err = webapi.resolve_response(resp)
if err then
    return response.error(err)
end

response.success(result)
```

### 低階 HTTP Client（含 retry backoff）

```lua
local httpclient = require("shared.http.client")

local resp, err = httpclient.new()
    :uri("http://example.com/api/data")
    :headers({ ["Authorization"] = "Bearer xxx" })
    :query({ page = 1 })
    :send("GET", 5000)

if err then
    ngx.log(ngx.ERR, "request failed: ", err)
end
```

---

## Object Mapper

`shared/object/mapper.lua` 提供宣告式的物件欄位映射，適合將後端回應轉換為 API 輸出格式：

```lua
local mapper = require("shared.object.mapper")

local user_map = {
    id       = "user_id",
    username = "name",
    email    = mapper.path("contact", "email"),
    role     = mapper.StringMapper("role_code"),
}

local source = {
    user_id  = 123,
    name     = "demo",
    contact  = { email = "demo@example.com" },
    role_code = 1,
}

local result = mapper.map(source, user_map)
-- { id = 123, username = "demo", email = "demo@example.com", role = "1" }
```

---

## OpenTelemetry 追蹤

啟用方式：在 `vhost/default.vhost` 的 `access_by_lua_block` 內，解除追蹤那行的註解：

```nginx
access_by_lua_block {
    local allowed = {GET=1,POST=1,PUT=1,PATCH=1,DELETE=1,HEAD=1,OPTIONS=1}
    if not allowed[ngx.var.method] then
        ngx.status = 405
        ngx.header.content_type = 'application/json; charset=utf-8'
        ngx.print('{"message":"UNSUPPORTED","description":"Method not allowed"}')
        return ngx.exit(ngx.OK)
    end
    require("server_tracing").start()  -- ← 解除這行的註解
}
```

同時解除 `content_by_lua_file` 下方的 `body_filter_by_lua_block` 區塊：

```nginx
body_filter_by_lua_block {
    require("server_tracing").flush()
}
```

需要在 `.env` 中設定：

```
JaegerCollector_Host=http://your-jaeger-host
JaegerCollector_OTLPHttpPort=4318
```

> **注意**：追蹤 span 會記錄完整的 request header（含 `Authorization`）與 body，設計上用於 B2B 內部除錯。請確保 Jaeger 存取受到妥善控管，避免外部存取。
