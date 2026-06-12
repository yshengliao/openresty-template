local _M = { _VERSION = "0.1" }

local ngx = _G.ngx

local cjson = require "cjson.safe"
      cjson.encode_max_depth(32)
      cjson.decode_max_depth(32)

local ERROR_CODE = {
  FAILURE = 'FAILURE',
}

do
  local function _trigger_on_exit()
    if ngx.ctx._ngx_before_exit then
      local listeners = ngx.ctx._ngx_before_exit
      for i = #listeners, 1, -1 do
        local proc = listeners[i]
        proc()
      end
    end
  end


  function _M.on_exit(proc)
    assert(type(proc) == "function", "on_exit: proc must be a function")

    if not ngx.ctx._ngx_before_exit then
      ngx.ctx._ngx_before_exit = { proc }
    else
      -- NOTE: For readability sake the ngx.ctx._ngx_before_exit using table.insert() to add items
      --   instead of indexer operation. We expect the operation will be used in
      -- the following statement is equivalent,
      table.insert(ngx.ctx._ngx_before_exit, proc)
    end
  end


  function _M.failure(code, message)
    if message == "" then
      message = nil
    end

    local trace_id

    if ngx.ctx.span  and  ngx.ctx.span.ctx  then
      trace_id = ngx.ctx.span.ctx.trace_id
    end

    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.header.content_type = 'application/json; charset=utf-8'

    local body = cjson.encode({
      code      = code,
      message   = message,
      trace_id  = trace_id,
      timestamp = ngx.now() * 1000,
    })
    ngx.ctx.response_body = body
    ngx.print(body)

    _trigger_on_exit()
    ngx.exit(ngx.OK)
  end


  function _M.success(result)
    local body
    if 'table' == type(result) then
      -- shallow copy to avoid mutating the caller's table
      local out = {}
      for k, v in pairs(result) do out[k] = v end
      out.timestamp = ngx.now() * 1000

      if ngx.ctx.span  and  ngx.ctx.span.ctx  then
        out.trace_id = ngx.ctx.span.ctx.trace_id
      end

      ngx.header.content_type = 'application/json; charset=utf-8'
      body = cjson.encode(out)
    else
      ngx.header.content_type = 'text/plain; charset=utf-8'
      body = result
    end
    ngx.ctx.response_body = body
    ngx.print(body)

    _trigger_on_exit()
    ngx.exit(ngx.OK)
  end


  function _M.error(err)
    if "table" == type(err) then
      -- Canonical error table shape: { code, message }.
      if err.code ~= nil then
        return _M.failure(err.code, err.message)
      end
      -- Legacy fallback: older upstream gateways produced { message = <code>,
      -- description = <text> }, where the `message` field carried the error code.
      -- Only treat `message` as a code when it actually looks like one;
      -- otherwise ({ message = "connection timeout" }) it is the human text.
      if type(err.message) == "string" then
        local m, _ = ngx.re.match(err.message, "^[A-Z0-9_]+$", "oj")
        if m and next(m) then
          return _M.failure(err.message, err.description)
        end
        return _M.failure(ERROR_CODE.FAILURE, err.message)
      end
      return _M.failure(ERROR_CODE.FAILURE, err.description)
    end

    local err_code = ERROR_CODE.FAILURE
    if type(err) == "string" then
      local m, _ = ngx.re.match(err, "^[A-Z0-9_]+$", "oj")
      if m  and  next(m) then
        return _M.failure(err)
      end
    end
    return _M.failure(err_code, err)
  end


  function _M.print(result)
    local body = result

    ngx.header.content_type = 'text/plain; charset=utf-8'
    ngx.ctx.response_body = body
    ngx.print(body)

    _trigger_on_exit()
    ngx.exit(ngx.OK)
  end


  function _M.html(result)
    local body = result

    ngx.header.content_type = 'text/html; charset=utf-8'
    ngx.ctx.response_body = body
    ngx.print(body)

    _trigger_on_exit()
    ngx.exit(ngx.OK)
  end


  function _M.redirect(url)
    ngx.status = ngx.HTTP_MOVED_TEMPORARILY
    ngx.header.location = url

    _trigger_on_exit()
    ngx.exit(ngx.OK)
  end


  --[[
    url
    err {
      error
      trace_id
      lang
      return_url
    }
  ]]
  function _M.redirect_error(url, err)
    -- 呼叫端必須確保 url 為受信任的固定路徑，不得直接傳入使用者輸入。
    assert(type(url) == "string" and #url > 0,
      "redirect_error: url must be a non-empty string")

    ngx.status = ngx.HTTP_MOVED_TEMPORARILY

    if type(err)=="string" then
      err = {
        error = err
      }
    end

    do
      local query = ngx.encode_args({
        error      = err.error,
        trace_id   = err.trace_id,
        lang       = err.lang,
        return_url = err.return_url,
      })

      url = string.format("%s?%s",
              url,
              query)
    end

    ngx.header.location = url

    _trigger_on_exit()
    ngx.exit(ngx.OK)
  end

end
return _M
