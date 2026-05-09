local httpclient     = require "shared.http.client"
local contenthelper  = require "shared.http-content-helper"
local json           = require("shared.json")
local cjson          = require("cjson.safe")
      cjson.encode_max_depth(32)
      cjson.decode_max_depth(32)

local _M = { _VERSION = "0.1" }

do
  local M_mt = { __index = _M }

  local function _fill_response_header(headers)
    if type(headers) == 'table' then
      for k, v in pairs(headers) do
        if string.lower(k) == 'content-type' then
          ngx.header[k] = v
        end
      end
    end
  end


  --[[
    opts {
      error_response_handler
      raw
    }
  ]]
  local function _resolve_response(resp, opts)
    opts = opts or {}

    if resp.status ~= 200 then
      if resp.status == 400 then
        if contenthelper.match_content_type(resp, 'application/json')  then
          local content = contenthelper.decode(resp.headers, resp.body)
          local err     = cjson.decode(content)
          return nil, err
        end
      end

      if type(opts.error_response_handler) == "function" then
        opts.error_response_handler(resp)
        return
      end

      ngx.status = resp.status
      _fill_response_header(resp.headers)
      ngx.say(resp.body)
      ngx.exit(ngx.OK)
    end

    local content = contenthelper.decode(resp.headers, resp.body)
    if opts.raw then
      return content
    end
    return cjson.decode(content)
  end


  local function _do_request(host, method, path, headers, query, body, timeout, error_handler)
    timeout = tonumber(timeout) or 5000

    if type(body)=="table" then
      body = json.encode(body)
    end

    local resp, err = httpclient.new()
      :uri(host..path)
      :headers(headers or {})
      :query(query)
      :body(body)
      :send(method, timeout, nil)

    if err or (not resp) then

      if type(error_handler) ~= "function" then
        ngx.status = 500
        ngx.say(err)
        ngx.exit(ngx.OK)
      end

      if err then
        error_handler(err, resp)
      else
        error_handler("no content", resp)
      end
      return nil
    end

    return resp
  end


  function _M.new(opt)
    return setmetatable({
      host          = opt.host,
      timeout       = tonumber(opt.timeout),
      error_handler = opt.error_handler,
    }, M_mt)
  end


  function _M.do_request(self, request, error_handler)
    local span = ngx.ctx.span
    if span then
      request.headers = request.headers or {}

      local trace_context_propagator = require("opentelemetry.trace.propagation.text_map.trace_context_propagator").new()
      local propagator               = require("opentelemetry.trace.propagation.text_map.composite_propagator").new({ trace_context_propagator })
      local context                  = require("opentelemetry.context").current()

      local headers_carrier = {
        headers = request.headers,
        set_header = function(name, val)
          request.headers[name] = val
        end
      }

      propagator:inject(context, headers_carrier)
    end

    return _do_request(
      self.host,
      request.method,
      request.path,
      request.headers,
      request.query,
      request.body,
      request.timeout or self.timeout,
      error_handler or self.error_handler)
  end

  _M.resolve_response = _resolve_response
end

return _M
