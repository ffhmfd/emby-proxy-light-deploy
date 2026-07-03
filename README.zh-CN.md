# Emby Proxy Light Deploy

一个用于部署
[Gsy-allen/emby-reverse-proxy-go](https://github.com/Gsy-allen/emby-reverse-proxy-go)
的轻量化 VPS 部署方案。

这个仓库提供的是一套简单、直接、容易维护的部署方式：

- 不使用 Docker
- 不安装数据库
- 不依赖 Nginx Proxy Manager 或其他 Web 面板
- `emby-proxy` 作为 `systemd` 后台服务运行
- 服务只监听本机 `127.0.0.1:8080`
- Nginx 负责 HTTPS、WebSocket 和公网入口
- Certbot 负责 Let's Encrypt 证书申请和自动续期

> 请只在目标 Emby 服务器管理员允许自建反代的情况下使用。

## 部署内容

脚本会从源码编译上游 Go 项目，并安装以下内容：

- `/usr/local/bin/emby-proxy`
- `/etc/systemd/system/emby-proxy.service`
- `/etc/nginx/sites-available/emby-proxy.conf`
- Certbot 证书续期后的 Nginx 自动重载钩子

公开访问地址遵循上游项目的路径格式：

```text
https://你的反代域名/https/上游Emby域名/443/
```

示例：

```text
https://emby.example.com/https/iris.niceduck.lol/443/
```

## 环境要求

- Debian 12 VPS，或其他基于 systemd 的 Linux 服务器
- root 权限
- 一个已解析到 VPS 的域名
- 服务器开放 `80` 和 `443` 端口
- 目标 Emby 服务器允许自建反代访问

脚本只会安装必要组件：

- `nginx`
- `certbot`
- `ca-certificates`
- `curl`
- `tar`

构建时会下载官方 Go Linux amd64 工具链，用于编译 `emby-proxy` 二进制文件。

## 快速开始

先编辑 `scripts/deploy.sh` 顶部变量：

```bash
DOMAIN="emby.example.com"
UPSTREAM_SCHEME="https"
UPSTREAM_HOST="iris.niceduck.lol"
UPSTREAM_PORT="443"
```

然后在 VPS 上运行：

```bash
bash scripts/deploy.sh
```

部署完成后，打开：

```text
https://emby.example.com/
```

根路径会自动跳转到：

```text
https://emby.example.com/https/iris.niceduck.lol/443/
```

健康检查：

```bash
curl -i https://emby.example.com/health
```

预期返回：

```text
HTTP/2 200

ok
```

## 文件说明

- `scripts/deploy.sh`：Debian 风格 VPS 的一键部署脚本
- `examples/emby-proxy.service`：systemd 服务示例
- `examples/nginx-emby-proxy.conf`：Nginx HTTPS 反代示例

## 常用维护命令

查看服务状态：

```bash
systemctl status emby-proxy
systemctl status nginx
```

重启代理服务：

```bash
systemctl restart emby-proxy
```

重载 Nginx：

```bash
nginx -t && systemctl reload nginx
```

查看日志：

```bash
journalctl -u emby-proxy -f
tail -f /var/log/nginx/error.log
```

## 安全说明

- `emby-proxy` 默认只监听 `127.0.0.1:8080`，不会直接暴露到公网。
- 默认启用 `BLOCK_PRIVATE_TARGETS=true`。
- 不要把 VPS 密码、Emby Token、私有上游凭据提交到仓库。
- 如果临时分享过 root 密码，部署完成后建议立即更换密码或改用 SSH 密钥登录。

## 致谢

本部署方案基于上游项目：
[Gsy-allen/emby-reverse-proxy-go](https://github.com/Gsy-allen/emby-reverse-proxy-go)。

本部署仓库作者：ffhmfd。
