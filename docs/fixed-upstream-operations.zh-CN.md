# Emby 固定上游高速入口运维方案

这份文档记录当前 VPS 上实际采用的方案，方便以后新开对话时直接读取仓库后继续添加新的 Emby 反代地址。

## 当前线上约定

- 公网反代域名：`emby.ffhmfdgroup.uk`
- Go 动态反代服务：`emby-proxy`，只监听 `127.0.0.1:8080`
- Nginx 负责 HTTPS、证书、WebSocket、长连接和固定上游入口
- 根路径 `/` 返回 `404`，不绑定任何默认 Emby 上游
- 通用动态入口仍然保留：

```text
https://emby.ffhmfdgroup.uk/https/上游域名/443/
https://emby.ffhmfdgroup.uk/http/上游域名/8096/
```

- 当前固定高速入口：

```text
https://emby.ffhmfdgroup.uk/kkp/
```

对应上游：

```text
https://kkp.zhezhi.art
```

## 什么时候用哪种入口

临时测试、偶尔使用、或者还不确定上游是否可用时，直接用动态入口：

```text
https://emby.ffhmfdgroup.uk/https/movie.example.com/443/
```

长期使用、视频流速度不稳、或者同一个上游经常观看时，建议加固定入口：

```text
https://emby.ffhmfdgroup.uk/movie/
```

固定入口由 Nginx 直接反代到上游，减少动态路径解析和 Go 代理层对大视频流的影响。当前 `/kkp/` 就是按这个方式添加的。

## 添加新的固定入口

下面假设要把上游：

```text
https://movie.example.com
```

添加为：

```text
https://emby.ffhmfdgroup.uk/movie/
```

在 VPS 上操作：

```bash
cp -a /etc/nginx/sites-available/emby-proxy.conf \
  /root/emby-proxy-nginx-backup-$(date -u +%Y%m%dT%H%M%SZ).conf

nano /etc/nginx/sites-available/emby-proxy.conf
```

把固定入口配置放进 `listen 443 ssl` 的 HTTPS `server` 块里，并且必须放在通用的 `location /` 前面。

可以复制仓库里的模板：

```text
examples/nginx-fixed-emby-upstream.conf
```

复制后需要替换：

- `/movie/`：你想暴露给客户端的入口名
- `movie.example.com`：真实上游域名
- `https://movie.example.com`：真实上游地址；如果有端口，写成 `https://movie.example.com:8920`
- `https://emby.ffhmfdgroup.uk/movie`：公网固定入口前缀

修改完成后检查并重载：

```bash
nginx -t
systemctl reload nginx
```

测试：

```bash
curl -i https://emby.ffhmfdgroup.uk/movie/emby/System/Info/Public
```

如果客户端可能拼出双斜杠，也可以额外测：

```bash
curl -i https://emby.ffhmfdgroup.uk/movie//emby/System/Info/Public
```

## HTTPS 上游带端口

上游如果是：

```text
https://movie.example.com:8920
```

需要这样改：

```nginx
proxy_pass https://movie.example.com:8920;
proxy_ssl_name movie.example.com;
proxy_set_header Host movie.example.com;
proxy_redirect https://movie.example.com:8920/ /movie/;
sub_filter 'https://movie.example.com:8920' 'https://emby.ffhmfdgroup.uk/movie';
```

SNI 用域名，不带端口。`Host` 默认建议只写域名；如果某个上游强依赖端口 Host，再改成 `movie.example.com:8920`。

## HTTP 上游

上游如果是：

```text
http://movie.example.com:8096
```

需要这样改：

```nginx
proxy_pass http://movie.example.com:8096;
proxy_set_header Host movie.example.com;
```

并删除 HTTPS 专用配置：

```nginx
proxy_ssl_server_name on;
proxy_ssl_name movie.example.com;
```

`proxy_redirect` 和 `sub_filter` 里的源地址也要改成 `http://movie.example.com:8096`。

## 动态入口稳定性设置

当前 VPS 上给 `emby-proxy.service` 设置了：

```ini
Environment=GODEBUG=http2client=0
```

这会让 Go 访问上游时使用 HTTP/1.1，避开部分 CDN 或 Emby 上游在 HTTP/2 流式传输中出现的 `PROTOCOL_ERROR`、断流、`broken pipe` 等问题。

确认方式：

```bash
systemctl show emby-proxy -p Environment
```

更新 service 文件后需要：

```bash
systemctl daemon-reload
systemctl restart emby-proxy
```

## 证书续期

证书由 Certbot 管理。确认自动续期：

```bash
systemctl status certbot.timer
certbot certificates
```

续期后 Nginx reload hook 位于：

```text
/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

## 排查速度问题

先分清是哪一段慢：

- VPS 到上游慢：在 VPS 上测试上游视频 Range 下载
- 客户端到 VPS 慢：从本机直连物理网卡测试 `emby.ffhmfdgroup.uk`
- 动态入口慢、固定入口快：优先给该上游加固定入口
- 动态入口日志出现 HTTP/2 `PROTOCOL_ERROR`：确认 `GODEBUG=http2client=0` 已生效

常用检查：

```bash
systemctl is-active emby-proxy
systemctl is-active nginx
curl -i http://127.0.0.1:8080/health
curl -i https://emby.ffhmfdgroup.uk/health
journalctl -u emby-proxy -f
tail -f /var/log/nginx/access.log /var/log/nginx/error.log
```

## 安全注意

- 不要把 VPS 密码、Emby Token、播放链接里的 `api_key`、Cookie 写进仓库
- 固定入口只配置公网 Emby 上游，不要反代内网 IP 或本机地址
- 保留 `BLOCK_PRIVATE_TARGETS=true`
- 临时分享过 root 密码后，部署完成建议改密码或切换 SSH 密钥登录
