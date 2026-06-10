-- GET /api/v1/example
--
-- Example endpoint demonstrating:
--   - Query string validation with httparg
--   - Type coercion and assertions
--   - Standard success/failure response
--
-- Try:
--   curl 'http://localhost:8080/api/v1/example?page=1&limit=10&status=active'
--   curl 'http://localhost:8080/api/v1/example?limit=999'   -- → 200, limit capped to 100
--   curl 'http://localhost:8080/api/v1/example?status=unknown' -- → 400 INVALID_ARGUMENT
--   curl 'http://localhost:8080/api/v1/example'             -- → 200 with defaults

local response  = require("shared.api.response")
local httparg   = require("shared.api.httparg")
local assertion = httparg.assertion

-- ── Input validation ──────────────────────────────────────────────────────────
local tag   = httparg.tag()
local query = tag.query

-- Optional number; defaults applied below after reading
local page  = query.page("number")
local limit = query.limit("number", assertion.max(100))  -- capped to 100, not an error

-- Optional enum; assertion validates allowed values
local status = query.status("string",
    assertion.string_should_in("active", "inactive", "pending"))

-- Apply defaults
page  = page  or 1
limit = limit or 20

-- ── Business logic ────────────────────────────────────────────────────────────
-- (Replace with real data-fetch logic in your project)
local items = {}
for i = 1, 3 do
    items[i] = {
        id     = (page - 1) * limit + i,
        status = status or "active",
        name   = "item_" .. i,
    }
end

-- ── Response ──────────────────────────────────────────────────────────────────
response.success({
    items  = items,
    page   = page,
    limit  = limit,
    total  = 3,
})
