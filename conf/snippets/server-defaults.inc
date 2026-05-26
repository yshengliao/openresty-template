# 共用 server 預設值：請求限制與安全 Headers
# 使用方式：在 server { ... } block 內 `include 'snippets/server-defaults.inc';`

client_max_body_size    4m;
client_body_buffer_size 1m;

add_header X-Content-Type-Options  nosniff                          always;
add_header X-Frame-Options         DENY                             always;
add_header Referrer-Policy         strict-origin-when-cross-origin  always;
add_header Content-Security-Policy "default-src 'none'"             always;
more_clear_headers                 Server;
