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
      error_response_handler   -- optional fn(resp); when set it is invoked on any
                               --   non-2xx response and resolve_response returns nil
      raw                      -- when true, return the decoded body string as-is
      passthrough              -- when true, proxy the upstream status/headers/body
                               --   verbatim on non-2xx then ngx.exit(ngx.OK)
    }

    On a non-2xx response (and without passthrough / error_response_handler) this
    returns `nil, err` where err is a unified table:
      {
        status  = <upstream status>,
        code    = <upstream JSON .code (or legacy .message) | "UPSTREAM_ERROR">,
        message = <upstream JSON message | short generic string>,
        body    = <raw decoded body string>,
      }
    The table is shaped so `response.error(err)` (which reads only code/message)
    produces a sane client response without leaking the raw upstream body.
  ]]
  local function _resolve_response(resp, opts)
    opts = opts or {}

    -- Treat any 2xx as success.
    if resp.status < 200 or resp.status >= 300 then
      -- Opt-in legacy behavior: proxy the upstream response verbatim.
      if opts.passthrough then
        ngx.status = resp.status
        _fill_response_header(resp.headers)
        ngx.say(resp.body)
        ngx.exit(ngx.OK)
      end

      if type(opts.error_response_handler) == "function" then
        opts.error_response_handler(resp)
        return nil
      end

      -- Build a unified error table from the upstream response.
      -- `content` may be nil/empty (204, empty body, corrupted gzip).
      local content = contenthelper.decode(resp.headers, resp.body)
      local code, message
      if content and content ~= ""
         and contenthelper.match_content_type(resp, 'application/json') then
        local parsed = cjson.decode(content)
        if type(parsed) == "table" then
          -- Canonical upstream shape uses `.code`; legacy gateways put the code
          -- in `.message`. Prefer code, then fall back to the legacy field.
          code    = parsed.code or parsed.message
          message = parsed.message
        end
      end

      return nil, {
        status  = resp.status,
        code    = code or "UPSTREAM_ERROR",
        message = message or "upstream request failed",
        body    = content,
      }
    end

    local content = contenthelper.decode(resp.headers, resp.body)
    if opts.raw then
      return content
    end
    if content == nil or content == "" then
      -- Empty 2xx body (e.g. 204): nothing to decode, not an error.
      return nil
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
      -- No handler: surface the transport error to the caller instead of
      -- writing it into the response (which would leak transport details).
      if type(error_handler) ~= "function" then
        return nil, err or "no content"
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
