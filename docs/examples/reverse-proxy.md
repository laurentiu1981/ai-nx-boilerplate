# Production reverse proxy (single origin, path-routed)

Prod serves web and api from **one domain**: web at `/`, api proxied at `/api`
(+ `/graphql`, `/uploads` if used). Single origin means the auth cookie is
first-party and no CORS configuration is needed.

The proxy runs on the VPS host (outside docker) and forwards to the published
container ports (`{{prod_port_web}}` web, `{{prod_port_api}}` api). It is configured
manually on the server — not part of the repo — but document it in the README.

Rules:
- Most-specific paths first (first match wins): `/api`, `/graphql`, `/uploads` → api;
  everything else → web.
- Set `X-Forwarded-Proto: https` so the api knows it's behind TLS.
- If the api streams (SSE): disable buffering for the stream path
  (Apache `flushpackets=on`, nginx `proxy_buffering off`) and raise the proxy timeout.
- TLS via Let's Encrypt (certbot for Apache/nginx; Caddy does it automatically).
- Google OAuth: the authorized redirect URI becomes
  `https://{{domain}}/api/auth/google/callback`.

## Apache vhost

Requires `a2enmod proxy proxy_http ssl headers`.

```apache
<VirtualHost *:443>
    ServerName {{domain}}

    SSLEngine on
    SSLCertificateFile    /etc/letsencrypt/live/{{domain}}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/{{domain}}/privkey.pem

    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
    ProxyTimeout 3600

    # Most-specific first (first match wins). API + GraphQL -> api, rest -> web.
    # SSE endpoints need flushpackets so events aren't buffered:
    # ProxyPass      /api/stream http://127.0.0.1:{{prod_port_api}}/api/stream flushpackets=on
    ProxyPass        /api      http://127.0.0.1:{{prod_port_api}}/api
    ProxyPassReverse /api      http://127.0.0.1:{{prod_port_api}}/api
    ProxyPass        /graphql  http://127.0.0.1:{{prod_port_api}}/graphql
    ProxyPassReverse /graphql  http://127.0.0.1:{{prod_port_api}}/graphql
    ProxyPass        /         http://127.0.0.1:{{prod_port_web}}/
    ProxyPassReverse /         http://127.0.0.1:{{prod_port_web}}/
</VirtualHost>

# Redirect http -> https
<VirtualHost *:80>
    ServerName {{domain}}
    Redirect permanent / https://{{domain}}/
</VirtualHost>
```

## Caddy equivalent

```
{{domain}} {
  handle /api/*     { reverse_proxy localhost:{{prod_port_api}} }
  handle /graphql*  { reverse_proxy localhost:{{prod_port_api}} }
  handle            { reverse_proxy localhost:{{prod_port_web}} }
}
```
