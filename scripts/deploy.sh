#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="emby.example.com"
UPSTREAM_SCHEME="https"
UPSTREAM_HOST="iris.niceduck.lol"
UPSTREAM_PORT="443"

UPSTREAM_PREFIX="/${UPSTREAM_SCHEME}/${UPSTREAM_HOST}/${UPSTREAM_PORT}/"
PROJECT_COMMIT="74297fddfe2c1cbadd82afb410e8c1de713dc1d5"
GO_VERSION="go1.26.4"
GO_ARCHIVE="go1.26.4.linux-amd64.tar.gz"
GO_SHA256="1153d3d50e0ac764b447adfe05c2bcf08e889d42a02e0fe0259bd47f6733ad7f"
BUILD_ROOT="/opt/emby-proxy-build"
GO_ROOT="${BUILD_ROOT}/${GO_VERSION}"
SRC_DIR="${BUILD_ROOT}/src-${PROJECT_COMMIT}"
WEBROOT="/var/www/letsencrypt"

log() {
  printf '\n==> %s\n' "$*"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
  fi
}

install_packages() {
  log "Installing required packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y nginx certbot ca-certificates curl tar
}

prepare_http_challenge() {
  log "Preparing HTTP challenge site"
  install -d -m 0755 "$WEBROOT"
  cat > /etc/nginx/sites-available/emby-proxy.conf <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location ^~ /.well-known/acme-challenge/ {
        root ${WEBROOT};
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        return 200 "emby proxy bootstrap\n";
        add_header Content-Type text/plain;
    }
}
NGINX

  ln -sfn /etc/nginx/sites-available/emby-proxy.conf /etc/nginx/sites-enabled/emby-proxy.conf
  nginx -t
  systemctl enable --now nginx
  systemctl reload nginx
}

request_certificate() {
  log "Requesting Let's Encrypt certificate"
  certbot certonly \
    --webroot \
    -w "$WEBROOT" \
    -d "$DOMAIN" \
    --non-interactive \
    --agree-tos \
    --register-unsafely-without-email \
    --keep-until-expiring
}

install_go_toolchain() {
  log "Installing Go toolchain for build"
  install -d -m 0755 "$BUILD_ROOT"

  if [ ! -x "${GO_ROOT}/bin/go" ]; then
    tmpdir="$(mktemp -d)"
    curl -fsSL "https://go.dev/dl/${GO_ARCHIVE}" -o "${tmpdir}/${GO_ARCHIVE}"
    printf '%s  %s\n' "$GO_SHA256" "${tmpdir}/${GO_ARCHIVE}" | sha256sum -c -
    tar -C "$tmpdir" -xzf "${tmpdir}/${GO_ARCHIVE}"
    rm -rf "$GO_ROOT"
    mv "${tmpdir}/go" "$GO_ROOT"
    rm -rf "$tmpdir"
  fi

  "${GO_ROOT}/bin/go" version
}

build_proxy() {
  log "Downloading and building emby-reverse-proxy-go"
  rm -rf "$SRC_DIR"
  install -d -m 0755 "$SRC_DIR"
  curl -fsSL "https://github.com/Gsy-allen/emby-reverse-proxy-go/archive/${PROJECT_COMMIT}.tar.gz" -o "${BUILD_ROOT}/source.tar.gz"
  tar -C "$SRC_DIR" --strip-components=1 -xzf "${BUILD_ROOT}/source.tar.gz"

  cd "$SRC_DIR"
  env \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 \
    GOCACHE="${BUILD_ROOT}/gocache" \
    GOMODCACHE="${BUILD_ROOT}/gomodcache" \
    "${GO_ROOT}/bin/go" build -trimpath -ldflags="-s -w" -o /usr/local/bin/emby-proxy .

  chmod 0755 /usr/local/bin/emby-proxy
}

install_systemd_service() {
  log "Creating system service"

  if ! id -u emby-proxy >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin emby-proxy
  fi

  cat > /etc/systemd/system/emby-proxy.service <<'SYSTEMD'
[Unit]
Description=Emby reverse proxy helper
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=emby-proxy
Group=emby-proxy
Environment=LISTEN_ADDR=127.0.0.1:8080
Environment=BLOCK_PRIVATE_TARGETS=true
Environment=GODEBUG=http2client=0
ExecStart=/usr/local/bin/emby-proxy
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
CapabilityBoundingSet=

[Install]
WantedBy=multi-user.target
SYSTEMD

  systemctl daemon-reload
  systemctl enable --now emby-proxy
}

write_nginx_config() {
  log "Writing final Nginx HTTPS proxy config"

  cat > /etc/nginx/sites-available/emby-proxy.conf <<NGINX
map \$http_upgrade \$emby_connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    location ^~ /.well-known/acme-challenge/ {
        root ${WEBROOT};
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    client_max_body_size 0;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    send_timeout 3600s;

    location = / {
        return 404;
    }

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Forwarded-Port \$server_port;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$emby_connection_upgrade;
        proxy_buffering off;
        proxy_request_buffering off;
        proxy_max_temp_file_size 0;
    }
}
NGINX

  nginx -t
  systemctl reload nginx
}

install_renewal_hook() {
  log "Installing certificate renewal reload hook"
  install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy

  cat > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'HOOK'
#!/usr/bin/env bash
systemctl reload nginx
HOOK

  chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
}

verify_deploy() {
  log "Verification"
  systemctl --no-pager --full status emby-proxy | sed -n '1,16p'
  systemctl --no-pager --full status nginx | sed -n '1,12p'
  curl -fsS http://127.0.0.1:8080/health
  printf '\n'
  curl -k -I --connect-timeout 10 --max-time 30 "https://${DOMAIN}/health" | sed -n '1,12p'
  curl -k -I --connect-timeout 10 --max-time 30 "https://${DOMAIN}/" | sed -n '1,12p'
  curl -k -I --connect-timeout 10 --max-time 30 "https://${DOMAIN}${UPSTREAM_PREFIX}" | sed -n '1,20p'
}

main() {
  require_root
  install_packages
  prepare_http_challenge
  request_certificate
  install_go_toolchain
  build_proxy
  install_systemd_service
  write_nginx_config
  install_renewal_hook
  verify_deploy
}

main "$@"
