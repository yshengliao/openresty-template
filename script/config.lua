local _M = {}


do
  _M.ENV = {
    BUILD_COMMIT_TAG = os.getenv("BUILD_COMMIT_TAG"),
    BUILD_COMMIT_SHA = os.getenv("BUILD_COMMIT_SHA"),

    -- 服務名稱，用於 OTel trace resource，預設 "GatewayTemplate"
    -- 衍生專案透過 .env 的 SERVICE_NAME 覆寫
    SERVICE_NAME = os.getenv("SERVICE_NAME") or "GatewayTemplate",

    JAEGER_COLLECTOR = (function()
      local host = os.getenv("JaegerCollector_Host"        ) or "127.0.0.1"
      local port = os.getenv("JaegerCollector_OTLPHttpPort") or "4318"
      return host..":"..port
    end)(),
  }

end
return _M
