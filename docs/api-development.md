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
-- 自動加入 timestamp（毫秒）與 trace_id（追蹤啟用時）欄位
```

> **注意**：當傳入字串而非 table 時，`response.success("plain text")` 回傳 `text/plain`，**不會**自動附加 `timestamp`。

### 錯誤回應

```lua
local response = require("shared.api.response")
local def      = require("shared.api.def")

-- 使用預定義錯誤碼
response.failure(def.ERROR_CODE.INVALID_ARGUMENT, "user_id is required")
-- HTTP 400, Content-Type: application/json

-- 或用 response.error() 自動判斷錯誤格式
response.error("PERMISSION_DENIED")                                      -- 全大寫字串 → 用作 error code
response.error("something went wrong")                                   -- 其他字串 → 包在 FAILURE code 下
response.error({ code = "TOKEN_EXPIRED", message = "token has expired" }) -- 正規 table 形式（推薦）
-- response.error({ message = "TOKEN_EXPIRED", description = "..." })    -- 舊版 upstream table 形式（仍支援）
```

### 純文字 / HTML / 導向

```lua
response.print("ok")                    -- text/plain
response.html("<h1>Hello</h1>")         -- text/html
response.redirect("https://example.com") -- 302 redirect
```

### 預定義錯誤碼

`shared/api/def.lua` 定義的完整錯誤碼（共 15 個），詳細說明見 [CLAUDE.md 錯誤碼表](../CLAUDE.md)：

| 錯誤碼 | 典型用途 |
|---|---|
| `OK` | 內部正向哨兵（端點很少直接回傳） |
| `NOP` | 無操作確認 |
| `UNSUPPORTED` | 功能或方法不支援 |
| `NO_CONTENT` | 資源存在但為空 |
| `INVALID_OPERATION` | 當前狀態下操作不允許 |
| `UNKNOWN_FAILURE` | 通用意外錯誤 |
| `INVALID_ARGUMENT` | 參數格式或值不合法 |
| `PERMISSION_DENIED` | 無存取權限 |
| `UPSTREAM_ERROR` | 上游回傳 non-2xx 且無法分類 |
| `INVALID_TOKEN` | Token 無效 |
| `TOKEN_EXPIRED` | Token 已過期 |
| `MISSING_PRINCIPAL` | 缺少身分資訊 |
| `INVALID_PRINCIPAL` | 身分資訊格式錯誤 |
| `INVALID_SIGNATURE` | HMAC / JWT 簽名不符 |
| `DUPLICATE_OPERATION` | 冪等 / 重放偵測 |

需要新錯誤碼？先加到 `script/shared/api/def.lua`，絕不直接傳入自訂字串。

---

## 請求驗證 (httparg)

`shared.api.httparg`（端點入口包裝器）提供流暢式（fluent）的請求驗證。此包裝器自動以 `response.failure` 作為 error handler，驗證失敗時直接回傳 HTTP 400 並終止請求。請勿直接 require `shared.httparg`（raw engine），否則驗證失敗會被靜默忽略。

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
| `"boolean"` | `false` ⟺ 字串 `"false"`/`"no"`/`"off"`（不分大小寫）或數字 `0`；其他非 nil 值 → `true`；注意：字串 `"0"` → `true`；nil → `false`（布林欄位永不為「缺失」） |
| `"date"` | 解析 `YYYY-M-D`（月/日允許 1-2 位）→ Unix timestamp（以伺服器本地時區計算） |
| `"datetime"` | 解析 `YYYY-M-D H:MM:SS` → Unix timestamp（以伺服器本地時區計算） |
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

-- do_request 回傳 resp，或 nil, err（transport 失敗）
local resp, err = client:do_request({
    method  = "POST",
    path    = "/internal/users",
    body    = { name = "demo" },        -- auto-JSON-encoded
    headers = { ["X-Request-Id"] = ngx.var.request_id },
})
if not resp then
    return response.error(err)
end

-- resolve_response：任何 2xx → result；所有 non-2xx → nil, {status,code,message,body}
local result, rerr = webapi.resolve_response(resp)
if rerr then
    return response.error(rerr)
end

response.success(result)
```

**`resolve_response` 選項（第二個參數 `opts`）：**
- `opts.passthrough = true` — 把上游 status/headers/body 原封不動地代理給 client（opt-in 舊行為）
- `opts.raw` — 回傳未解碼的 body 字串而非 table
- `opts.error_response_handler` — `fn(resp)` 在 non-2xx 時被呼叫，取代 `nil, err` 的回傳

OTel 追蹤 header 只有在 `ngx.ctx.span` 存在時（即追蹤已啟用）才會注入。

### 低階 HTTP Client（含 timeout-only 單次重試）

```lua
local httpclient = require("shared.http.client")

local resp, err = httpclient.new()
    :uri("http://example.com/api/data")
    :headers({ ["Authorization"] = "Bearer xxx" })
    :query({ page = 1 })
    :send("GET", 5000)   -- 5000ms = per-attempt socket timeout

if err then
    ngx.log(ngx.ERR, "request failed: ", err)
end
```

`timeout` 是每次嘗試的 socket timeout（毫秒），預設 5000。僅在 socket timeout（不含其他錯誤）時重試一次，退避時間採指數退避（500ms 起，上限 30s）。最多共 2 次嘗試。

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

**啟用 start（追蹤開始）**：追蹤啟動的開關在 `conf/snippets/access-method-allowlist.inc`，解除最後一行的註解：

```nginx
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
    -- require("server_tracing").start()  ← 解除這行的註解
}
```

因為這個 snippet 被每個 location 共用，啟用後會對所有 include 此 snippet 的 location 生效。

**啟用 flush（追蹤結束寫入）**：在每個 vhost 的 `content_by_lua_file` 下方解除 `body_filter_by_lua_block` 的註解（例如 `vhost/default.vhost` 約第 33 行）：

```nginx
body_filter_by_lua_block {
    require("server_tracing").flush()
}
```

需要在 `.env` 中設定（值為純 hostname/IP，不含 scheme；exporter 會自動補 `http://`）：

```
JaegerCollector_Host=127.0.0.1
JaegerCollector_OTLPHttpPort=4318
```

> **PII 注意**：span 的 `request` 屬性會記錄完整的 request line、所有 headers 與 body。`Authorization`、`Cookie`、`Set-Cookie`、`Proxy-Authorization` 的 header **值**會被自動遮蔽為 `[REDACTED]`，其餘 header 值與完整 body 均以明文記錄。B2B 內部除錯用途。請確保 Jaeger 存取受到妥善控管。
