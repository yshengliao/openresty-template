

local input  = [[[
  "luffy",
  19231403472593275092374593252,
  {
    "bar": "baz\bax",
    "foo": null
  }
] ]]

local json = require("json")

local cjson = require("cjson")

do
  local opt = {
    use_json_number = true,
  }
  local res, err = json.decode(input, opt)
  assert(err == nil, string.format("err should be nil, but got '%s'", err))

  -- export
  print(res[3].bar)
  print(cjson.encode(res))
  print(json.encode(res))
  print(arg[1])
end

do
  local res = cjson.decode(input)
  assert(res ~= nil, string.format("res should not be nil"))

  -- export
  print(res[3].bar)
  print(cjson.encode(res))
  print(json.encode(res))
  print(arg[1])
end


