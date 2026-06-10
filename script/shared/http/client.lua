local http  = require "resty.http.simple"
local cjson = require "cjson.safe"
local bit   = require "bit"

local ngx_re_match = ngx.re.match
local bit_lshift   = bit.lshift
local ngx_var      = ngx.var

local _M = {}
do
  local _M_mt = { __index = _M }

  local DEFAULT_MAX_BACKOFF = 30000   --  30 seconds
  local DEFAULT_MIN_BACKOFF =   500   -- 500 milliseconds
  local DEFAULT_TIMEOUT     =  5000   -- 5 seconds (socket timeout when caller omits one)
  local MAX_RETRIES         =     1   -- 最多重試 1 次（共 2 次嘗試）

  local function _retry_backoff(retry, minBackoff, maxBackoff)
    if retry < 0 then
      retry = 0
    end

    local backoff = bit_lshift(minBackoff, retry)
    if (backoff > maxBackoff)  or  (backoff < minBackoff) then
      backoff = maxBackoff
    end

    if backoff == 0 then
      return 0
    end
    return backoff
  end


  function _M.new()
    return setmetatable({},
    _M_mt)
  end


  -- Original: https://github.com/pintsized/lua-resty-http/blob/c39cf8c48718668a52e230a2be3518a2912d203a/lib/resty/http.lua
  --[[
      usage:
        local uri = "http://example.com?query=value"
        local parsed_uri, err = _parse_uri(uri, false)
        if not parsed_uri then
          return nil, err
        end
        local scheme, host, port, path, query = unpack(parsed_uri)
  --]]
  local function _parse_uri(uri, query_in_path)
    if query_in_path == nil then query_in_path = true end

    local m, err = ngx_re_match(uri, [[^(?:(http[s]?):)?//([^:/\?]+)(?::(\d+))?([^\?]*)\??(.*)]], "jo")

    if not m then
      if err then
        return nil, "failed to match the uri: " .. uri .. ", " .. err
      end

      return nil, "bad uri: " .. uri
    else
      -- If the URI is schemaless (e.g., //example.com) try to use our current
      -- request scheme.
      if not m[1] then
        local scheme = ngx_var.scheme
        if scheme == "http" or scheme == "https" then
          m[1] = scheme
        else
          return nil, "schemaless URIs require a request context: " .. uri
        end
      end

      if m[3] then
        m[3] = tonumber(m[3])
      else
        if m[1] == "https" then
          m[3] = 443
        else
          m[3] = 80
        end
      end
      if not m[4] or "" == m[4] then m[4] = "/" end

      if query_in_path and m[5] and m[5] ~= "" then
        m[4] = m[4] .. "?" .. m[5]
        m[5] = nil
      end

      return m, nil
    end
  end


  function _M.uri(self, value)
    if value == nil then
      return self._uri
    end

    self._uri = value
    return self
  end


  function _M.headers(self, value)
    if value == nil then
      return self._headers
    end

    assert(type(value) == 'table', "headers must be of type table")
    self._headers = value
    return self
  end


  function _M.query(self, value)
    if value == nil then
      return self
    end

    if type(value) == 'table' then
      self._query = ngx.encode_args(value)
    else
      self._query = value
    end
    return self
  end

  function _M.body(self, value)
    if value == nil then
      return self
    end

    assert(type(value) == 'string', "body must be of type string")
    self._body = value
    return self
  end

  function _M.send(self, method, timeout, callback)
    if not self._uri then
      return nil, ("invalid operation: invalid uri")
    end

    -- Caller-supplied `timeout` is the per-attempt SOCKET timeout, NOT a backoff
    -- seed. Backoff between retries is derived independently from DEFAULT_MIN_BACKOFF.
    local sock_timeout = timeout or DEFAULT_TIMEOUT

    method  = string.upper(method)

    local parsed_uri, err = _parse_uri(self._uri, false)
    if err then
      return nil, err
    end

    local scheme, host, port, path, query = unpack(parsed_uri)
    local headers = self._headers

    if method == "POST" or method == "PATCH" then
      if headers == nil then
        headers = {}
      end
      if headers["Content-Type"] == nil then
        headers["Content-Type"] = "application/x-www-form-urlencoded"
      end
    end

    if self._query then
      if (string.len(self._query) > 0)  and  (string.len(query) > 0) then
        query = self._query.."&"..query
      else
        query = self._query
      end
    end

    local attempt = 0
    local res
    repeat
      res, err = http.request(
        host, port,
        {
          scheme  = scheme,
          path    = path,
          method  = method,
          headers = headers,
          query   = query,
          body    = self._body,
          timeout = sock_timeout
        }
      )
      -- check the response
      if not res then
        attempt = attempt + 1
        -- when errors occurred
        if err then
          if err ~= "timeout" then
            return nil, err
          end
        end
        -- 重試前等待退避時間（與 socket timeout 無關，採指數退避）
        if attempt <= MAX_RETRIES then
          ngx.sleep(_retry_backoff(attempt, DEFAULT_MIN_BACKOFF, DEFAULT_MAX_BACKOFF) / 1000)
        end
      else
        break
      end
    until attempt > MAX_RETRIES

    if type(callback) == 'function' then
      return callback(res)
    end
    return res
  end

end
return _M