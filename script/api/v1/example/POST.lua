-- POST /api/v1/example
--
-- Example endpoint demonstrating:
--   - JSON body validation with httparg
--   - Multiple assertion types
--   - Upstream HTTP call via webapi-client
--   - Error propagation with response.error()
--   - on_exit cleanup hook
--
-- Try:
--   curl -X POST http://localhost:8080/api/v1/example \
--     -H 'Content-Type: application/json' \
--     -d '{"name":"demo","amount":50,"tags":["a","b"]}'
--
--   # Missing required field → 400
--   curl -X POST http://localhost:8080/api/v1/example \
--     -H 'Content-Type: application/json' \
--     -d '{"amount":50}'
--
--   # Negative amount → 400
--   curl -X POST http://localhost:8080/api/v1/example \
--     -H 'Content-Type: application/json' \
--     -d '{"name":"demo","amount":-1}'

local response  = require("shared.api.response")
local httparg   = require("shared.api.httparg")
local def       = require("shared.api.def")
local assertion = httparg.assertion
-- local webapi = require("shared.api.webapi-client")  -- uncomment when calling upstream

-- ── Input validation ──────────────────────────────────────────────────────────
local tag  = httparg.tag()
local json = tag.json

local name   = json.name("required", "string", assertion.non_empty_string())
local amount = json.amount("required", "number",
    assertion.non_negative_number(),
    assertion.non_nan_nor_inf())
local tags   = json.tags("array")       -- optional array
local note   = json.note("string")      -- optional string

-- ── Optional: call upstream service ──────────────────────────────────────────
--
-- Pattern: create client, call do_request, check resolve_response for errors.
-- The client automatically injects OTel traceparent headers when tracing is on.
--
-- local client = webapi.new({ host = "http://backend:8080", timeout = 5000 })
--
-- local resp = client:do_request({
--     method  = "POST",
--     path    = "/internal/process",
--     body    = { name = name, amount = amount },
-- })
--
-- local result, err = webapi.resolve_response(resp)
-- if err then
--     return response.error(err)
-- end

-- ── Optional: register cleanup hook ──────────────────────────────────────────
--
-- on_exit runs after the response is sent (e.g. release a DB connection).
-- Hooks run in LIFO order.
--
-- response.on_exit(function()
--     db_conn:close()
-- end)

-- ── Business logic ────────────────────────────────────────────────────────────
-- Guard against business-level invalidity (distinct from input type errors)
if amount > 10000 then
    return response.failure(def.ERROR_CODE.INVALID_ARGUMENT,
        "amount exceeds maximum allowed value of 10000")
end

local record = {
    name   = name,
    amount = amount,
    tags   = tags or {},
    note   = note,
}

-- ── Response ──────────────────────────────────────────────────────────────────
response.success({
    created = record,
})
