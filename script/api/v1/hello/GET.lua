local response = require("shared.api.response")

local result = {
    message = "Hello from OpenResty Gateway Template!",
    timestamp = ngx.now()
}

response.success(result)
