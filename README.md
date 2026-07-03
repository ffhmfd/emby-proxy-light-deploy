# Emby Proxy Light Deploy

[中文文档](README.zh-CN.md)

Lightweight deployment notes and scripts for running
[Gsy-allen/emby-reverse-proxy-go](https://github.com/Gsy-allen/emby-reverse-proxy-go)
behind Nginx with HTTPS.

This repository documents a minimal VPS deployment:

- no Docker
- no database
- no web control panel
- `emby-proxy` runs as a `systemd` service on `127.0.0.1:8080`
- Nginx terminates HTTPS and forwards requests to the local service
- Certbot obtains and renews the Let's Encrypt certificate

> Only use this for Emby servers where reverse proxying is allowed.

## What This Deploys

The deployment builds the upstream Go project from source and installs:

- `/usr/local/bin/emby-proxy`
- `/etc/systemd/system/emby-proxy.service`
- `/etc/nginx/sites-available/emby-proxy.conf`
- a Certbot deploy hook that reloads Nginx after certificate renewal

The public access format follows the upstream project:

```text
https://your-proxy-domain/https/upstream-emby-domain/443/
```

Example:

```text
https://emby.example.com/https/iris.niceduck.lol/443/
```

## Requirements

- Debian 12 VPS, or a similar systemd-based Linux server
- root access
- a domain A record pointing to the VPS
- ports `80` and `443` open
- an upstream Emby server that allows reverse proxy access

The script installs only the required packages:

- `nginx`
- `certbot`
- `ca-certificates`
- `curl`
- `tar`

It downloads the official Go Linux amd64 toolchain to build the binary.

## Quick Start

Edit the variables at the top of `scripts/deploy.sh`:

```bash
DOMAIN="emby.example.com"
UPSTREAM_SCHEME="https"
UPSTREAM_HOST="iris.niceduck.lol"
UPSTREAM_PORT="443"
```

Then run on the VPS:

```bash
bash scripts/deploy.sh
```

After deployment, open:

```text
https://emby.example.com/
```

The root path redirects to:

```text
https://emby.example.com/https/iris.niceduck.lol/443/
```

Health check:

```bash
curl -i https://emby.example.com/health
```

Expected response:

```text
HTTP/2 200

ok
```

## Files

- `scripts/deploy.sh`: one-shot deployment script for Debian-style VPS hosts
- `examples/emby-proxy.service`: systemd service template
- `examples/nginx-emby-proxy.conf`: Nginx HTTPS reverse proxy template

## Operations

Check service state:

```bash
systemctl status emby-proxy
systemctl status nginx
```

Restart the proxy service:

```bash
systemctl restart emby-proxy
```

Reload Nginx:

```bash
nginx -t && systemctl reload nginx
```

Check logs:

```bash
journalctl -u emby-proxy -f
tail -f /var/log/nginx/error.log
```

## Security Notes

- The proxy service listens on `127.0.0.1:8080`, not on a public interface.
- `BLOCK_PRIVATE_TARGETS=true` is enabled by default.
- Do not commit VPS passwords, Emby tokens, or private upstream credentials.
- Rotate root passwords or switch to SSH keys after sharing temporary access.

## Attribution

This deployment wrapper uses the upstream project
[Gsy-allen/emby-reverse-proxy-go](https://github.com/Gsy-allen/emby-reverse-proxy-go).

Author of this deployment repository: ffhmfd.
