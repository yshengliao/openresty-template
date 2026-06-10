-- Standalone dev test for script/shared/json.lua.
-- Run from repo root: resty tests/json.test.lua
-- NOT loaded by the gateway (lives outside lua_package_path).

package.path = "./script/?.lua;" .. package.path

local input = [[[
  "luffy",
  19231403472593275092374593252,
  {
    "bar": "baz\bax",
    "foo": null
  }
] ]]

local json  = require("shared.json")
local cjson = require("cjson")

do
  local opt = {
    use_json_number = true,
  }
  local res, err = json.decode(input, opt)
  assert(err == nil, string.format("err should be nil, but got '%s'", tostring(err)))

  print("shared.json decode bar: " .. tostring(res[3].bar))
  print("cjson.encode of shared.json result: " .. cjson.encode(res))
  print("json.encode of shared.json result: "  .. json.encode(res))
end

do
  local res = cjson.decode(input)
  assert(res ~= nil, string.format("res should not be nil"))

  print("cjson decode bar: " .. tostring(res[3].bar))
  print("cjson.encode of cjson result: " .. cjson.encode(res))
  print("json.encode of cjson result: "  .. json.encode(res))
end
