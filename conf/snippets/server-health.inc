# 共用 health check 端點與預設 404
# 使用方式：在 server { ... } block 內 `include 'snippets/server-health.inc';`

location / {
    return 404;
}

# LB / Docker Health Check
location = /healthcheck {
    access_log   off;
    default_type 'text/plain';
    return 200 'ok';
}

location = /ping {
    access_log   off;
    default_type 'text/plain';
    return 200 'pong';
}
