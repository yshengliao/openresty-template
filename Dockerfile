# OpenResty Gateway Dockerfile
FROM openresty/openresty:1.27.1.2-alpine

# COPY instead of ADD — avoids implicit tar-extraction and URL-fetch side effects
COPY ./conf   /app/conf
COPY ./script /app/script
COPY ./vhost  /app/vhost

RUN mkdir -p /app/logs \
 && ln -sf /dev/stdout /app/logs/access.log \
 && ln -sf /dev/stderr /app/logs/error.log \
 && chown -R nobody /app

USER nobody

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
  CMD wget --spider -q http://127.0.0.1:8080/healthcheck || exit 1

CMD ["/usr/local/openresty/bin/openresty", "-p", "/app", "-g", "daemon off;"]

# Use SIGQUIT instead of default SIGTERM to cleanly drain requests
# See https://github.com/openresty/docker-openresty/blob/master/README.md#tips--pitfalls
STOPSIGNAL SIGQUIT
