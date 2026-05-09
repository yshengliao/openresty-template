local _M = { _VERSION = "0.1" }

local response  = require("shared.api.response")
local httparg   = require("shared.httparg")


local def        = require("shared.api.def")
local ERROR_CODE = def.ERROR_CODE




-- _M
do
  function _M.tag(opt)
    opt = opt or {}
    opt.error_handler = opt.error_handler  or  response.failure

    return httparg.tag(opt)
  end
end

_M.assertion = httparg.assertion
return _M
