local ngx  = _G.ngx


local ContentDecoders = {
  default = {
    decode = function(data)
      return data
    end
  },
  gzip = {
    decode = function(data)
      local zlib = require("zlib")
      local stream = zlib.inflate()
      local r = stream(data)
      return r  -- return inflated string; caller is responsible for JSON decoding
    end
  }
}


local _M = {}
do
  --[[
    arguments
      resp {
        status  (number) : The resonse status, e.g. 200
        headers (table)  : A Lua table with response headers.
        body    (string) : The plain response body
      }
      content_type (string)
  ]]
  function _M.match_content_type(resp, content_type)
    assert(resp)
    assert(content_type)

    local contentType = resp.headers["Content-Type"]
    if contentType then
      local match, _ = ngx.re.match(contentType, '\\s*('..content_type..')\\s*;?', 'ixjo')
      if match then
        return true
      end
    end
    return false
  end


  --[[
    arguments
      headers (table)  : A Lua table with response headers.
    return
      decoder  (ContentDecoder)
  ]]
  function _M.get_content_decoder(headers)
    local encoding = headers['Content-Encoding']
    if encoding then
      local decoder = ContentDecoders[encoding]
      return decoder
    end
    return ContentDecoders.default
  end


  function _M.decode(header, body)
    local decoder = _M.get_content_decoder(header)
    return decoder.decode(body)
  end
end
return _M