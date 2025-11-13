#!/bin/bash
#
# Databricks Cluster Init Script
# 用途：在 Databricks 集群启动时自动安装和配置 Xray 代理
#
# 使用方法：
# 1. 将此脚本上传到 DBFS:
#    dbutils.fs.put("/databricks/init-scripts/xray-proxy-init.sh", script_content, overwrite=True)
#
# 2. 在集群配置中添加 Init Script:
#    Cluster -> Edit -> Advanced Options -> Init Scripts
#    Path: dbfs:/databricks/init-scripts/xray-proxy-init.sh
#
# 3. 在集群环境变量中配置:
#    CF_TOKEN=your_cloudflare_token
#    TUNNEL_DOMAIN=proxy.yourdomain.com
#    XRAY_UUID=your_uuid (可选)
#

set -ex

# 日志函数
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "开始 Xray 代理初始化脚本"

# 从环境变量读取配置
CF_TOKEN="${CF_TOKEN:-}"
TUNNEL_DOMAIN="${TUNNEL_DOMAIN:-}"
XRAY_UUID="${XRAY_UUID:-$(cat /proc/sys/kernel/random/uuid)}"
XRAY_PORT="${XRAY_PORT:-10809}"
XRAY_SOCKS_PORT="${XRAY_SOCKS_PORT:-1080}"

# 检查必需的环境变量
if [ -z "$CF_TOKEN" ]; then
    log "警告: CF_TOKEN 未设置，Cloudflare Tunnel 将不会配置"
    SKIP_CLOUDFLARE=true
fi

# 安装依赖
log "安装系统依赖..."
apt-get update -qq
apt-get install -y -qq curl wget unzip jq systemctl >/dev/null 2>&1

# 检测架构
detect_arch() {
    case $(uname -m) in
        x86_64) echo "linux-64" ;;
        aarch64|arm64) echo "linux-arm64-v8a" ;;
        *) echo "linux-64" ;;
    esac
}

# 安装 Xray
log "安装 Xray..."
ARCH=$(detect_arch)
XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name | sed 's/v//')
DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-${ARCH}.zip"

TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
wget -q "$DOWNLOAD_URL" -O xray.zip
unzip -q xray.zip
install -m 755 xray /usr/local/bin/xray
cd - >/dev/null
rm -rf "$TMP_DIR"

log "Xray 安装完成: $(xray version | head -n 1)"

# 创建配置目录
mkdir -p /etc/xray
mkdir -p /var/log/xray

# 生成 Xray 配置
log "生成 Xray 配置..."
cat > /etc/xray/config.json <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": $XRAY_PORT,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$XRAY_UUID",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      }
    },
    {
      "port": $XRAY_SOCKS_PORT,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# 创建 systemd 服务
log "创建 Xray 服务..."
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

# 启动 Xray
systemctl daemon-reload
systemctl enable xray
systemctl start xray

log "Xray 服务已启动"

# 安装和配置 Cloudflare Tunnel
if [ "$SKIP_CLOUDFLARE" != true ]; then
    log "安装 Cloudflare Tunnel..."

    # 下载 cloudflared
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) CF_ARCH="amd64" ;;
        aarch64|arm64) CF_ARCH="arm64" ;;
        *) CF_ARCH="amd64" ;;
    esac

    wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -O /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared

    log "Cloudflared 安装完成"

    # 创建配置目录
    mkdir -p /etc/cloudflared

    # 使用环境变量中的 token 进行认证（简化版本）
    # 注意：生产环境建议使用更安全的方式存储和传递 token
    log "配置 Cloudflare Tunnel..."

    # 这里需要根据实际情况配置 tunnel
    # 由于 init script 的限制，建议预先在 Cloudflare 创建 tunnel，然后只部署配置

    log "Cloudflare Tunnel 配置跳过（建议手动配置）"
fi

# 保存配置信息到 DBFS
if [ -n "$DB_HOME" ]; then
    CONFIG_FILE="$DB_HOME/xray-config.txt"
    cat > "$CONFIG_FILE" <<EOF
Xray Proxy Configuration
========================
UUID: $XRAY_UUID
VMess Port: $XRAY_PORT
SOCKS5 Port: $XRAY_SOCKS_PORT
Installed at: $(date)

Service Status:
$(systemctl status xray --no-pager || true)
EOF
    log "配置信息已保存到: $CONFIG_FILE"
fi

# 健康检查
sleep 5
if systemctl is-active --quiet xray; then
    log "✓ Xray 服务运行正常"
else
    log "✗ Xray 服务启动失败"
    systemctl status xray --no-pager
    exit 1
fi

log "Xray 代理初始化完成"
log "UUID: $XRAY_UUID"
log "VMess 端口: $XRAY_PORT"
log "SOCKS5 端口: $XRAY_SOCKS_PORT"
