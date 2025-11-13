# Databricks Xray 代理一键部署方案

这是一个在 Databricks 集群上快速部署 Xray 代理服务的完整解决方案，通过 Cloudflare Tunnel 将代理服务安全地暴露到公网。

## 🎯 Databricks专用：单文件部署（推荐）

**对于Databricks用户，我们提供了一个all-in-one部署脚本，只需一个文件即可完成所有配置！**

```python
# 在Databricks Notebook中，只需3步：

# 1. 上传脚本到DBFS
script = open('databricks-xray-allinone.sh').read()
dbutils.fs.put("/databricks/init-scripts/xray.sh", script, True)

# 2. 配置集群环境变量（可选）
# Cluster → Advanced Options → Environment Variables
# CF_TOKEN=your_token  # Cloudflare Token（可选）
# TUNNEL_DOMAIN=proxy.yourdomain.com  # 域名（可选）

# 3. 添加Init Script
# Cluster → Advanced Options → Init Scripts
# Path: dbfs:/databricks/init-scripts/xray.sh
```

**就这么简单！** 详细说明请查看 [DATABRICKS_DEPLOYMENT.md](DATABRICKS_DEPLOYMENT.md)

---

## 📋 目录

- [架构图](#架构图)
- [特性](#特性)
- [前置要求](#前置要求)
- [快速开始](#快速开始)
- [部署方式](#部署方式)
- [配置说明](#配置说明)
- [客户端配置](#客户端配置)
- [故障排查](#故障排查)
- [安全建议](#安全建议)

## 🏗️ 架构图

```
┌─────────────────┐
│   你的设备      │
│  (Clash/V2Ray)  │
└────────┬────────┘
         │
         │ HTTPS/TLS
         ▼
┌─────────────────────────┐
│  Cloudflare CDN         │
│  (全球边缘节点)         │
└────────┬────────────────┘
         │
         │ Cloudflare Tunnel
         │ (加密连接)
         ▼
┌─────────────────────────┐
│  Databricks 集群        │
│  ┌──────────────────┐   │
│  │  cloudflared     │   │
│  └────────┬─────────┘   │
│           │              │
│           ▼              │
│  ┌──────────────────┐   │
│  │  Xray (VMess)    │   │
│  │  端口: 10809     │   │
│  └────────┬─────────┘   │
│           │              │
└───────────┼──────────────┘
            │
            ▼
       互联网访问
```

## ✨ 特性

- ✅ **一键部署**：自动化安装 Xray 和 Cloudflare Tunnel
- ✅ **零配置端口**：使用 Cloudflare Tunnel，无需开放公网端口
- ✅ **高性能**：基于 Xray-core，支持 VMess/VLESS 协议
- ✅ **安全可靠**：通过 Cloudflare 加密传输，内置广告拦截
- ✅ **自动重启**：systemd 服务管理，异常自动恢复
- ✅ **详细日志**：完整的访问和错误日志记录
- ✅ **灵活配置**：支持环境变量自定义所有参数

## 📦 前置要求

### 系统要求

- **操作系统**：Ubuntu 18.04+, Debian 10+, CentOS 7+
- **架构**：x86_64 或 ARM64
- **权限**：Root 或 sudo 权限
- **内存**：至少 512MB RAM
- **网络**：能够访问 GitHub 和 Cloudflare

### Cloudflare 要求

1. **Cloudflare 账户**（免费版即可）
2. **已托管的域名**（必须在 Cloudflare 上）
3. **API Token**：
   - 访问 https://dash.cloudflare.com/profile/api-tokens
   - 点击 "Create Token"
   - 选择 "Edit Cloudflare Tunnel" 模板
   - 或自定义权限：
     - `Account.Cloudflare Tunnel: Edit`
     - `Zone.DNS: Edit`

### Databricks 配置

- **集群类型**：Standard 或 High Concurrency
- **Runtime**：任意版本
- **Init Scripts**：需要权限添加初始化脚本（可选）

## 🚀 快速开始

### 方式一：手动部署（推荐新手）

1. **克隆或下载项目**

```bash
git clone https://github.com/yourusername/databricks-xray-proxy.git
cd databricks-xray-proxy
```

2. **配置环境变量**

```bash
# 复制环境变量模板
cp .env.example .env

# 编辑配置文件
nano .env

# 必须配置的变量：
# - CF_TOKEN: 您的 Cloudflare API Token
```

3. **安装 Xray**

```bash
# 赋予执行权限
chmod +x install-xray-proxy.sh

# 运行安装脚本
sudo ./install-xray-proxy.sh
```

4. **配置 Cloudflare Tunnel**

```bash
# 赋予执行权限
chmod +x setup-cloudflared.sh

# 运行配置脚本
sudo ./setup-cloudflared.sh

# 按提示输入您的域名（如: proxy.yourdomain.com）
```

5. **验证服务**

```bash
# 查看 Xray 状态
sudo systemctl status xray

# 查看 Cloudflare Tunnel 状态
sudo systemctl status cloudflared

# 查看连接信息
cat /etc/cloudflared/connection-info.txt
```

### 方式二：Databricks Init Script（推荐生产环境）

1. **上传脚本到 DBFS**

```bash
# 在 Databricks Notebook 中执行
dbutils.fs.put("/databricks/init-scripts/install-xray-proxy.sh",
               open("install-xray-proxy.sh").read(),
               overwrite=True)

dbutils.fs.put("/databricks/init-scripts/setup-cloudflared.sh",
               open("setup-cloudflared.sh").read(),
               overwrite=True)
```

2. **配置环境变量**

在 Databricks 集群配置中添加环境变量：

```
Advanced Options > Environment Variables

CF_TOKEN=your_cloudflare_token_here
TUNNEL_NAME=databricks-xray-proxy
```

3. **配置 Init Script**

在集群配置中添加：

```
Advanced Options > Init Scripts

Type: DBFS
Path: dbfs:/databricks/init-scripts/install-xray-proxy.sh
```

4. **启动集群**

重启集群后脚本会自动执行。

### 方式三：一键脚本（最简单）

```bash
# 下载并执行一键安装脚本
curl -fsSL https://raw.githubusercontent.com/yourusername/databricks-xray-proxy/main/install-xray-proxy.sh | sudo bash

# 配置 Cloudflare（需要先设置 CF_TOKEN 环境变量）
export CF_TOKEN="your_token_here"
curl -fsSL https://raw.githubusercontent.com/yourusername/databricks-xray-proxy/main/setup-cloudflared.sh | sudo bash
```

## ⚙️ 配置说明

### 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `XRAY_VERSION` | `latest` | Xray 版本 |
| `XRAY_PORT` | `10809` | VMess 监听端口 |
| `XRAY_SOCKS_PORT` | `1080` | SOCKS5 监听端口 |
| `XRAY_UUID` | 自动生成 | VMess UUID |
| `CF_TOKEN` | - | Cloudflare API Token（必需） |
| `TUNNEL_NAME` | `databricks-xray-proxy` | 隧道名称 |
| `LOG_LEVEL` | `warning` | 日志级别 |

### 自定义配置

如需高级配置，可以直接编辑配置文件：

```bash
# 编辑 Xray 配置
sudo nano /etc/xray/config.json

# 编辑 Cloudflared 配置
sudo nano /etc/cloudflared/config.yml

# 重启服务使配置生效
sudo systemctl restart xray
sudo systemctl restart cloudflared
```

## 📱 客户端配置

### 获取连接信息

```bash
# 查看完整连接信息
cat /etc/cloudflared/connection-info.txt
```

### Clash 配置

```yaml
proxies:
  - name: "Databricks-Proxy"
    type: vmess
    server: proxy.yourdomain.com  # 您的域名
    port: 443
    uuid: your-uuid-here           # 从 connection-info.txt 获取
    alterId: 0
    cipher: auto
    tls: true
    skip-cert-verify: false
    network: tcp
```

### V2RayN / V2RayNG 配置

1. 添加 VMess 服务器
2. 填入以下信息：
   - **地址**：proxy.yourdomain.com
   - **端口**：443
   - **用户ID**：从 connection-info.txt 获取
   - **额外ID**：0
   - **加密方式**：auto
   - **传输协议**：tcp
   - **TLS**：启用

### Shadowrocket 配置

```
vmess://base64编码的配置
```

使用以下格式生成：

```json
{
  "v": "2",
  "ps": "Databricks-Proxy",
  "add": "proxy.yourdomain.com",
  "port": "443",
  "id": "your-uuid-here",
  "aid": "0",
  "net": "tcp",
  "type": "none",
  "tls": "tls"
}
```

### 测试连接

```bash
# 使用 curl 测试
curl -x socks5://127.0.0.1:1080 https://www.google.com

# 或通过客户端测试
# 在代理软件中启用代理后，访问 https://www.google.com
```

## 🔧 管理命令

### Xray 服务管理

```bash
# 启动服务
sudo systemctl start xray

# 停止服务
sudo systemctl stop xray

# 重启服务
sudo systemctl restart xray

# 查看状态
sudo systemctl status xray

# 查看日志
sudo journalctl -u xray -f

# 查看访问日志
sudo tail -f /var/log/xray/access.log

# 查看错误日志
sudo tail -f /var/log/xray/error.log
```

### Cloudflare Tunnel 管理

```bash
# 启动服务
sudo systemctl start cloudflared

# 停止服务
sudo systemctl stop cloudflared

# 重启服务
sudo systemctl restart cloudflared

# 查看状态
sudo systemctl status cloudflared

# 查看日志
sudo journalctl -u cloudflared -f

# 列出所有隧道
cloudflared tunnel list

# 查看隧道详情
cloudflared tunnel info databricks-xray-proxy

# 删除隧道
cloudflared tunnel delete databricks-xray-proxy
```

## 🐛 故障排查

### 问题：Xray 服务无法启动

```bash
# 检查配置文件语法
xray -test -config /etc/xray/config.json

# 查看详细错误
sudo journalctl -u xray -n 50 --no-pager

# 检查端口占用
sudo netstat -tlnp | grep -E '10809|1080'
```

### 问题：Cloudflare Tunnel 连接失败

```bash
# 验证认证
cloudflared tunnel login

# 测试隧道连接
cloudflared tunnel --config /etc/cloudflared/config.yml run

# 检查 DNS 配置
nslookup proxy.yourdomain.com
```

### 问题：客户端无法连接

1. **检查 UUID 是否正确**

```bash
grep -oP '"id":\s*"\K[^"]+' /etc/xray/config.json
```

2. **检查域名 DNS 解析**

```bash
nslookup proxy.yourdomain.com
```

3. **测试本地代理**

```bash
curl -x socks5://127.0.0.1:1080 https://www.google.com -v
```

4. **查看实时日志**

```bash
sudo tail -f /var/log/xray/access.log
```

### 问题：Databricks 集群重启后服务未启动

确保使用了 systemd 服务并设置了自动启动：

```bash
sudo systemctl enable xray
sudo systemctl enable cloudflared
```

## 🔒 安全建议

1. **定期更新 UUID**

```bash
# 生成新 UUID
NEW_UUID=$(cat /proc/sys/kernel/random/uuid)

# 更新配置
sudo sed -i "s/\"id\": \".*\"/\"id\": \"$NEW_UUID\"/" /etc/xray/config.json

# 重启服务
sudo systemctl restart xray
```

2. **启用日志轮转**

```bash
# 创建日志轮转配置
cat << EOF | sudo tee /etc/logrotate.d/xray
/var/log/xray/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0600 root root
    postrotate
        systemctl reload xray > /dev/null 2>&1 || true
    endscript
}
EOF
```

3. **限制访问来源**（可选）

编辑 `/etc/xray/config.json`，添加 IP 白名单：

```json
{
  "inbounds": [{
    "settings": {
      "clients": [{
        "id": "your-uuid",
        "alterId": 0,
        "email": "user@example.com"
      }],
      "allowedIPs": ["允许的IP地址"]
    }
  }]
}
```

4. **使用防火墙**

```bash
# 只允许本地访问 Xray 端口
sudo ufw allow from 127.0.0.1 to any port 10809
sudo ufw allow from 127.0.0.1 to any port 1080
```

5. **监控异常流量**

```bash
# 定期检查访问日志
sudo grep "rejected" /var/log/xray/error.log

# 监控连接数
sudo netstat -an | grep :10809 | wc -l
```

## 📊 性能优化

### 1. 调整系统参数

```bash
# 编辑系统限制
sudo nano /etc/sysctl.conf

# 添加以下内容：
net.ipv4.tcp_fastopen = 3
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728

# 应用配置
sudo sysctl -p
```

### 2. 优化 Xray 配置

编辑 `/etc/xray/config.json`：

```json
{
  "policy": {
    "levels": {
      "0": {
        "handshake": 4,
        "connIdle": 300,
        "uplinkOnly": 2,
        "downlinkOnly": 5
      }
    }
  }
}
```

### 3. Cloudflare Tunnel 优化

编辑 `/etc/cloudflared/config.yml`：

```yaml
originRequest:
  connectTimeout: 30s
  noTLSVerify: false
  keepAliveConnections: 100
  keepAliveTimeout: 90s
```

## 📝 许可证

MIT License

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📞 支持

如有问题，请：

1. 查看 [故障排查](#故障排查) 章节
2. 查看项目 [Issues](https://github.com/yourusername/databricks-xray-proxy/issues)
3. 提交新的 Issue

## 🔗 相关链接

- [Xray 官方文档](https://xtls.github.io/)
- [Cloudflare Tunnel 文档](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps)
- [Databricks 文档](https://docs.databricks.com/)

---

**⚠️ 免责声明**：本项目仅供学习和研究使用，请遵守当地法律法规。使用本项目所产生的任何后果由使用者自行承担。
