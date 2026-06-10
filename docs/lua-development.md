# Lua 開發指南

本文件說明在 OpenResty 環境下撰寫 Lua 的關鍵概念與常見陷阱，適合有基礎 Lua 或其他語言背景的開發者快速上手。

---

## OpenResty 執行階段

OpenResty 在 Nginx 的生命週期中提供多個 Lua 執行掛鉤，本模板最常用的：

| 指令 | 說明 | 常見用途 |
|---|---|---|
| `init_by_lua*` | 主處理器啟動時執行一次（master process） | 載入全域設定、預熱快取 |
| `access_by_lua*` | 請求到達 location 後、content 前 | 認證、限流、method 驗證 |
| `content_by_lua*` | 產生回應內容 | API 端點主邏輯 |
| `header_filter_by_lua*` | 修改回應 header | 動態注入 header |
| `body_filter_by_lua*` | 處理回應 body | 壓縮、tracing flush |
| `log_by_lua*` | 回應結束後、記錄前 | 非同步日誌、指標收集 |

本模板的 API 端點在 `content_by_lua_file` 中執行。Method allowlist 驗證在 `access_by_lua_block` 中執行。

---

## 請求生命週期

```
[Client]
   │
   ▼
access_by_lua_block    ← method allowlist 驗證（vhost）
   │
   ▼
content_by_lua_file    ← script/api/v1/{path}/{method}.lua
   │                     └─ httparg 驗證 → 業務邏輯 → response.success/failure
   ▼
[Response sent]
   │
   ▼
response.on_exit() hooks   ← 清理工作（關閉 DB 連線等）
   │
   ▼
body_filter / log phase
```

---

## ngx.ctx：請求生命週期共用資料

`ngx.ctx` 是 table，生命週期與當前請求一致，可跨 `access`、`content`、`log` 各階段共用：

```lua
-- 在 access_by_lua_block 設定
ngx.ctx.user_id = "abc123"

-- 在 content_by_lua_file 讀取
local user_id = ngx.ctx.user_id
```

注意：`ngx.ctx` 不可跨請求共用，不可在 `init_by_lua` 使用。

---

## 非阻塞 I/O（Cosocket）

OpenResty 的 cosocket 讓 Lua 可以用同步語法進行非阻塞網路呼叫，不需要 callback。

**規則：cosocket 只能在以下階段使用：**
- `rewrite_by_lua*`
- `access_by_lua*`
- `content_by_lua*`
- `ngx.timer.*`

不可在 `init_by_lua*` 或 `log_by_lua*` 中直接使用 cosocket（`log_by_lua` 可用 `ngx.timer` 包裝）。

本模板的 `shared/http/client.lua` 封裝了 cosocket HTTP 呼叫（builder 模式）：
```lua
local httpclient = require("shared.http.client")
local resp, err = httpclient.new()
    :uri("http://backend-service:8080/internal/status")
    :headers({ ["Authorization"] = "Bearer xxx" })
    :send("GET", 3000)
-- timeout 是每次嘗試的 socket timeout（毫秒）；逾時時最多重試一次（指數退避）
```

---

## 模組快取

`require()` 在同一 worker 中只會執行一次，結果快取在 `package.loaded`。這表示：

- **模組層級變數**（定義在函式外部）是 worker 層級的單例，不是請求層級。
- **請求相關狀態**必須放在函式內部或 `ngx.ctx` 中，不可放在模組頂層。

```lua
-- ❌ 錯誤：request_count 被所有請求共用
local request_count = 0
local _M = {}
function _M.increment()
    request_count = request_count + 1  -- 這不是請求計數，是 worker 全域計數
end

-- ✅ 正確：使用 ngx.ctx
local _M = {}
function _M.increment()
    ngx.ctx.count = (ngx.ctx.count or 0) + 1
end
```

---

## LuaJIT 限制

OpenResty 使用 LuaJIT 2.1（Lua 5.1 相容）：

- 不支援 Lua 5.2+ 的 `goto`、整數子型別（bitwise op 用 `bit` 函式庫）。
- `#` 運算子只適用連續整數鍵的 table；sparse table 請用計數器。
- `table.pack` / `table.unpack` 需用 `unpack`（Lua 5.1）或引入 `resty.core`。
- 數值預設是 double，整數運算建議顯式轉換：`math.floor(n)`。

---

## 錯誤處理

OpenResty Lua 中的錯誤處理模式：

```lua
local response = require("shared.api.response")
local def      = require("shared.api.def")

-- 使用 pcall 捕捉執行期錯誤
local ok, err = pcall(function()
    -- 可能出錯的程式碼
end)
if not ok then
    ngx.log(ngx.ERR, "unexpected error: ", err)
    return response.failure(def.ERROR_CODE.UNKNOWN_FAILURE, "服務暫時無法使用")
end
```

`response.success()` / `response.failure()` 內部呼叫 `ngx.exit()`，執行後不會繼續。避免在呼叫後放置需要執行的邏輯：

```lua
-- ❌ 錯誤：cleanup 永遠不會執行
response.success({ ok = true })
cleanup()   -- 不會到這裡

-- ✅ 正確：用 on_exit hook
response.on_exit(function()
    cleanup()
end)
response.success({ ok = true })
```

---

## ngx.log 等級

```lua
ngx.log(ngx.DEBUG,  "debug info")
ngx.log(ngx.INFO,   "normal info")
ngx.log(ngx.WARN,   "non-critical issue")
ngx.log(ngx.ERR,    "error, request continues")
ngx.log(ngx.CRIT,   "critical error")
```

預設等級為 `warn`，可在 `nginx.conf` 調整 `error_log` 等級。記錄敏感資料前請確認 log 存取權限。

---

## httparg 驗證模組

`shared.api.httparg`（端點入口，自動接線 `response.failure` 作為 error handler）提供流暢式請求驗證。請勿直接 require `shared.httparg`（raw engine），否則驗證失敗會被靜默吞掉而非回傳 HTTP 400。

```lua
local httparg   = require("shared.api.httparg")
local assertion = httparg.assertion
local tag       = httparg.tag()

-- Query string
local page  = tag.query.page("number")
local limit = tag.query.limit("number", assertion.max(100))  -- CAP 到 100，不報錯

-- JSON body
local name   = tag.json.name("required", "string", assertion.non_empty_string())
local amount = tag.json.amount("required", "number", assertion.non_negative_number())
local tags   = tag.json.tags("array")   -- optional

-- 驗證失敗時自動回傳 400 並終止請求
```

**重要：`assertion.max(n)` 是 CAP（`math.min`），不是錯誤。** 若要拒絕超出範圍的值，需自行加 guard：
```lua
if limit > 100 then
    return response.failure("INVALID_ARGUMENT", "limit 不得超過 100")
end
```

---

## response 模組

所有回應透過 `shared/api/response.lua`：

```lua
local response = require("shared.api.response")
local def      = require("shared.api.def")

response.success({ data = result })                            -- 200 JSON (table: auto-appends timestamp)
response.success("plain text")                                 -- 200 text/plain (string: no timestamp)
response.failure(def.ERROR_CODE.INVALID_ARGUMENT, "說明")      -- 400 JSON
response.error(err)                                            -- 從 upstream 錯誤直接轉發
response.print("plain text")                                   -- 200 text/plain (explicit)
response.redirect("/new-path")                                 -- 302
```

每個函式都呼叫 `ngx.exit()`，之後的程式碼不會執行。注意：`response.text()` 不存在，請用 `response.print()`。

---

## 常見陷阱

| 問題 | 原因 | 解法 |
|---|---|---|
| `attempt to yield across C-call boundary` | 在不允許的阶段使用 cosocket | 確認執行於 content/access 階段 |
| `no resolver defined` | DNS 未設定就呼叫 cosocket 連線 | 確認 `nginx.conf` 有 `resolver` 指令 |
| 模組狀態被請求共用 | 把請求狀態放在模組頂層變數 | 改用 `ngx.ctx` |
| `response.success()` 後程式繼續執行 | 誤解 `ngx.exit()` 行為 | 用 `return` 或 `on_exit` hook |
| require 改不了，cache 太舊 | `lua_code_cache on` 下模組被快取 | `docker compose restart` |
| `content_by_lua_file` 找不到檔案 | 路徑錯誤或 `$SCRIPT_DIR` 未設定 | 確認 vhost 有 `set $SCRIPT_DIR` |
