# Fixed Upstream Operations

This document records the current production approach so a future Codex session can read the repository and add new Emby reverse-proxy entries without rediscovering the setup.

## Current Production Shape

- Public proxy domain: `emby.ffhmfdgroup.uk`
- `emby-proxy` listens only on `127.0.0.1:8080`
- Nginx handles HTTPS, certificates, WebSocket upgrades, long-lived connections, and fixed upstream entries
- `/` returns `404`; there is no default upstream bound to the root path
- Dynamic entries still work:

```text
https://emby.ffhmfdgroup.uk/https/upstream.example.com/443/
https://emby.ffhmfdgroup.uk/http/upstream.example.com/8096/
```

- Current fixed high-speed entry:

```text
https://emby.ffhmfdgroup.uk/kkp/
```

which proxies to:

```text
https://kkp.zhezhi.art
```

## Dynamic vs Fixed Entries

Use the dynamic entry for temporary tests or one-off upstreams:

```text
https://emby.ffhmfdgroup.uk/https/movie.example.com/443/
```

Use a fixed Nginx entry for upstreams that will be used long term, especially when video streaming is slow or unstable through the dynamic Go proxy:

```text
https://emby.ffhmfdgroup.uk/movie/
```

Fixed entries let Nginx proxy directly to the upstream and avoid the dynamic path parsing layer for large video streams.

## Add A Fixed Entry

Example target:

```text
https://movie.example.com
```

Desired public entry:

```text
https://emby.ffhmfdgroup.uk/movie/
```

On the VPS:

```bash
cp -a /etc/nginx/sites-available/emby-proxy.conf \
  /root/emby-proxy-nginx-backup-$(date -u +%Y%m%dT%H%M%SZ).conf

nano /etc/nginx/sites-available/emby-proxy.conf
```

Copy `examples/nginx-fixed-emby-upstream.conf` into the HTTPS `server` block, before the generic `location /`.

Replace:

- `/movie/` with the new public path
- `movie.example.com` with the upstream host
- `https://movie.example.com` with the upstream origin; include the port when needed, for example `https://movie.example.com:8920`
- `https://emby.example.com/movie` with the real public proxy prefix

Validate and reload:

```bash
nginx -t
systemctl reload nginx
```

Smoke test:

```bash
curl -i https://emby.ffhmfdgroup.uk/movie/emby/System/Info/Public
curl -i https://emby.ffhmfdgroup.uk/movie//emby/System/Info/Public
```

The second request checks whether accidental double slashes from clients still reach the upstream.

## HTTPS Upstream With A Port

For:

```text
https://movie.example.com:8920
```

use:

```nginx
proxy_pass https://movie.example.com:8920;
proxy_ssl_name movie.example.com;
proxy_set_header Host movie.example.com;
proxy_redirect https://movie.example.com:8920/ /movie/;
sub_filter 'https://movie.example.com:8920' 'https://emby.ffhmfdgroup.uk/movie';
```

Use the hostname without a port for SNI. Start with `Host: movie.example.com`; only include the port in `Host` if the upstream specifically requires it.

## HTTP Upstream

For:

```text
http://movie.example.com:8096
```

use:

```nginx
proxy_pass http://movie.example.com:8096;
proxy_set_header Host movie.example.com;
```

Remove the HTTPS-only lines:

```nginx
proxy_ssl_server_name on;
proxy_ssl_name movie.example.com;
```

Update `proxy_redirect` and `sub_filter` source URLs to `http://movie.example.com:8096`.

## Dynamic Proxy Stability

The deployed `emby-proxy.service` includes:

```ini
Environment=GODEBUG=http2client=0
```

This makes Go use HTTP/1.1 for upstream requests. It avoids HTTP/2 streaming failures seen with some CDN-backed Emby upstreams, including `PROTOCOL_ERROR`, resets, and `broken pipe` errors.

Check it with:

```bash
systemctl show emby-proxy -p Environment
```

After changing the service file:

```bash
systemctl daemon-reload
systemctl restart emby-proxy
```

## Certificate Renewal

Certbot manages the certificate. Check renewal with:

```bash
systemctl status certbot.timer
certbot certificates
```

The renewal hook reloads Nginx:

```text
/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

## Speed Troubleshooting

Separate the slow segment first:

- VPS to upstream: test a Range download from the VPS
- Client to VPS: test the public proxy domain from the client's physical network interface
- Dynamic entry slow but fixed entry fast: add a fixed Nginx entry for that upstream
- Dynamic entry logs show HTTP/2 `PROTOCOL_ERROR`: confirm `GODEBUG=http2client=0`

Useful checks:

```bash
systemctl is-active emby-proxy
systemctl is-active nginx
curl -i http://127.0.0.1:8080/health
curl -i https://emby.ffhmfdgroup.uk/health
journalctl -u emby-proxy -f
tail -f /var/log/nginx/access.log /var/log/nginx/error.log
```

## Safety

- Do not commit VPS passwords, Emby tokens, playback `api_key` values, cookies, or private credentials
- Only add public Emby upstreams as fixed entries
- Do not proxy private IP ranges or localhost through fixed entries
- Keep `BLOCK_PRIVATE_TARGETS=true`
- Rotate a root password or switch to SSH keys after temporary password sharing
