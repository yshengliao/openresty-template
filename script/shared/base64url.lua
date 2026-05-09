local _M = { _VERSION = "0.1" }

local decode_base64 = ngx.decode_base64
local encode_base64 = ngx.encode_base64

do
  function _M.decode( input )
    if not input then
      return nil
    end
    local value, _ = string.gsub(
      input, ".",
      function(s)
        if     s == "-" then  return "+"
        elseif s == "_" then  return "/"  end
      end)
    return decode_base64(value)
  end

  function _M.encode( input )
    if not input then
      return nil
    end
    local value = encode_base64(input, true)
    local code, _ = string.gsub(
      value, ".",
      function(s)
        if     s == "+" then  return "-"
        elseif s == "/" then  return "_"  end
      end)
    return code
  end
end
return _M
