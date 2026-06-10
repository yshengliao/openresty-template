local global      = require("opentelemetry.global")
local context_new = require("opentelemetry.context").new
local span_status = require("opentelemetry.trace.span_status")
local span_kind   = require("opentelemetry.trace.span_kind")
local attr        = require("opentelemetry.attribute")
local resource    = require("opentelemetry.resource")

local trace_context_propagator = require("opentelemetry.trace.propagation.text_map.trace_context_propagator").new()
local propagator               = require("opentelemetry.trace.propagation.text_map.composite_propagator").new({ trace_context_propagator })

local _M = {}
do
  local function _init()
    local tracer_provider      = require("opentelemetry.trace.tracer_provider")
    local batch_span_processor = require("opentelemetry.trace.batch_span_processor")
    local otlp_exporter        = require("opentelemetry.trace.exporter.otlp")
    local resource             = require("opentelemetry.resource")
    local exporter_client      = require("opentelemetry.trace.exporter.http_client")
    local attr                 = require("opentelemetry.attribute")

    -- setup jaeger
    do
      local config         = require("config")
      local exporter       = otlp_exporter.new(exporter_client.new(config.ENV.JAEGER_COLLECTOR, 3))
      local span_processor = batch_span_processor.new(exporter)

      local config = require("config")
      local tp = tracer_provider.new(
        span_processor,
        {
          resource = resource.new(attr.string("service.name", config.ENV.SERVICE_NAME))
        })


      -- export to global
      global.set_tracer_provider(tp)
    end
  end

  -- Redact sensitive header values before they are recorded as a span
  -- attribute. The raw header text is captured for debugging, but credentials
  -- (Authorization / Cookie / etc.) must never reach the trace backend.
  local REDACTED_HEADERS = {
    ["authorization"]       = true,
    ["cookie"]              = true,
    ["set-cookie"]          = true,
    ["proxy-authorization"] = true,
  }
  local function _redact_raw_header(raw)
    return (string.gsub(raw, "([^\r\n]+)", function(line)
      local name, sep = string.match(line, "^([^:]+)(:)")
      if name and REDACTED_HEADERS[string.lower(name)] then
        return name .. sep .. " [REDACTED]"
      end
      return line
    end))
  end

  function _M.start()
    local tp = global.get_tracer_provider()
    if not tp then
      _init()
    end

    local tracer  = global.tracer("opentelemetry-lua")

    local context = context_new()
    do
      context = propagator:extract(context, ngx.req)
    end

    ngx.req.read_body()

    local span
    local path = string.gsub(ngx.var.request_uri, "?.*", "")
    local body = ngx.req.get_body_data()  or  ""
    context, span = tracer:start(context,
      ngx.var.method.." "..path,
      {
        kind = span_kind.server,
        attributes = {
          attr.string("request", _redact_raw_header(ngx.req.raw_header())..body)
        },
      })
    context:attach()

    ngx.ctx.span = span
  end

  function _M.flush()
    local span = ngx.ctx.span
    if span then
      local header_entries = {}
      do
        local status_reason = require("shared.http-status-reason")
        header_entries[#header_entries+1] = status_reason[ngx.status]
      end
      local dump_headers = {'Content-Type', 'traceparent', 'tracestate'}
      for _, name in ipairs(dump_headers) do
        local value = ngx.header[name]
        if value then
          header_entries[#header_entries+1] = string.format("%s: %s", name, value)
        end
      end
      if type(ngx.ctx.response_body) == "string" then
        header_entries[#header_entries+1] = ""
        header_entries[#header_entries+1] = ngx.ctx.response_body
      end
      local header_text
      header_text = table.concat(header_entries, "\n")
      span:set_attributes(
        attr.string("response", header_text)
      )
      span:finish()
    end
  end
end

return _M
