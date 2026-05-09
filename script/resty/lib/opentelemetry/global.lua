local metrics_reporter = require("opentelemetry.metrics_reporter")

local _M = {
    context_storage  = nil,
    metrics_reporter = metrics_reporter,
    tracer_providers = {}
}

function _M.set_tracer_provider(tp)
    local pid = tostring(ngx.var.pid).."@"..(ngx.var.SERVICE_NAME or "")
    _M.tracer_providers[pid] = tp
end

function _M.get_tracer_provider()
    local pid = tostring(ngx.var.pid).."@"..(ngx.var.SERVICE_NAME or "")
    return _M.tracer_providers[pid]
end

function _M.set_metrics_reporter(metrics_reporter)
    _M.metrics_reporter = metrics_reporter
end

function _M.tracer(name, opts)
    return _M.get_tracer_provider():tracer(name, opts)
end

function _M.get_context_storage()
    return _M.context_storage or ngx.ctx
end

function _M.set_context_storage(context_storage)
    _M.context_storage = context_storage
end

return _M
