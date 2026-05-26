# 插件與函式庫新增指南

本文件說明如何在 OpenResty Gateway 模板中新增第三方 Lua 函式庫或自訂共用模組。

---

## 模組分層

本模板的 Lua 模組依用途分三層：

| 目錄 | 用途 |
|---|---|
| `script/resty/` | 第三方函式庫（直接放入，保留原始命名） |
| `script/shared/` | 自訂共用模組（業務無關的通用工具） |
| `script/api/` | 業務端點（不應被其他模組引用） |

---

## 新增純 Lua 函式庫

1. 將函式庫檔案放入 `script/resty/`（第三方）或 `script/shared/`（自訂）。

2. 在端點中 require：
   ```lua
   local msgpack = require("resty.msgpack")
   local base64  = require("shared.base64url")
   ```

   路徑對應規則：
   - `require("resty.xxx")` → `script/resty/xxx.lua`（或 `script/resty/xxx/init.lua`）
   - `require("shared.xxx")` → `script/shared/xxx.lua`

3. 重啟容器套用：
   ```bash
   docker compose restart
   ```

---

## 新增多檔案 SDK 型函式庫

若函式庫包含多個子檔案（如 OpenTelemetry SDK）：

```
script/resty/lib/
└── opentelemetry/
    ├── init.lua
    ├── tracer.lua
    └── span.lua
```

`lua_package_path` 已設定搜尋 `script/` 下所有層級，直接 require 即可：
```lua
local tracer = require("resty.lib.opentelemetry.tracer")
```

如需新增搜尋路徑，在 `script/script.conf` 的 `lua_package_path` 加入對應路徑：
```nginx
lua_package_path "${prefix}script/?.lua;${prefix}script/?/init.lua;/usr/local/openresty/lualib/?.lua;;";
```

---

## 需要 C 函式庫的模組（FFI）

部分模組透過 LuaJIT FFI 呼叫系統共用函式庫（如 `resty.hmac` 依賴 OpenSSL）：

1. 確認 OpenResty base image 中已有對應的 `.so`。
2. 若映像中沒有，在 `Dockerfile` 加入安裝步驟：
   ```dockerfile
   RUN apk add --no-cache libsodium-dev
   ```
3. 需 rebuild：
   ```bash
   docker compose up --build -d
   ```

> Dockerfile 使用 Alpine base。安裝套件用 `apk add`，非 `apt-get`。

---

## 撰寫自訂共用模組

在 `script/shared/` 新建模組，遵循標準 Lua module 模式：

```lua
-- script/shared/my-helper.lua
local _M = {}

function _M.do_something(input)
    -- 實作
    return result
end

return _M
```

在端點中引用：
```lua
local helper = require("shared.my-helper")
local result = helper.do_something(data)
```

---

## 新增跨 Worker 共用記憶體（`lua_shared_dict`）

如需跨 worker 共用的快取或計數器，在 `script/script.conf` 宣告：

```nginx
lua_shared_dict my_cache 10m;
```

在 Lua 中使用：
```lua
local cache = ngx.shared.my_cache
cache:set("key", "value", 60)   -- TTL 60 秒
local val = cache:get("key")
```

> `lua_shared_dict` 僅限同一 Pod 內跨 worker 共用，不跨 Pod。跨 Pod 共用狀態請使用 Redis 或其他外部儲存。

---

## 模組命名慣例

- **第三方函式庫**：保留原始命名，放 `script/resty/`。
- **自訂工具模組**：`kebab-case` 檔名，放 `script/shared/`，以功能命名（如 `rate-limiter.lua`、`auth-helper.lua`）。
- 業務邏輯屬於 `api/` 端點，不放 `shared/`。

---

## 新增函式庫後

更新 `README.md` 與 `README_ZH.md` 的「Included Libraries」表格，補上函式庫路徑與用途說明，方便後續維護者查閱。
