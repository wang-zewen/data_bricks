#!/bin/bash
#
# Databricks Xray Proxy 一键部署脚本
# 用途：在Databricks集群上自动安装和配置Xray代理服务
# 使用方式：可作为Databricks Cluster Init Script或手动执行
#

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 配置变量（可通过环境变量覆盖）
XRAY_VERSION="${XRAY_VERSION:-latest}"
XRAY_INSTALL_DIR="${XRAY_INSTALL_DIR:-/usr/local/bin}"
XRAY_CONFIG_DIR="${XRAY_CONFIG_DIR:-/etc/xray}"
XRAY_LOG_DIR="${XRAY_LOG_DIR:-/var/log/xray}"
XRAY_PORT="${XRAY_PORT:-10809}"
XRAY_SOCKS_PORT="${XRAY_SOCKS_PORT:-1080}"
XRAY_UUID="${XRAY_UUID:-$(cat /proc/sys/kernel/random/uuid)}"

# 检测系统架构
detect_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "linux-64"
            ;;
        aarch64|arm64)
            echo "linux-arm64-v8a"
            ;;
        *)
            log_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
}

# 安装依赖
install_dependencies() {
    log_info "安装系统依赖..."

    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq curl wget unzip jq systemctl 2>/dev/null || true
    elif command -v yum &> /dev/null; then
        yum install -y -q curl wget unzip jq systemd
    else
        log_error "不支持的包管理器"
        exit 1
    fi
}

# 下载并安装 Xray
install_xray() {
    log_info "开始安装 Xray..."

    # 获取最新版本
    if [ "$XRAY_VERSION" = "latest" ]; then
        XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name | sed 's/v//')
        log_info "检测到最新版本: $XRAY_VERSION"
    fi

    local arch=$(detect_architecture)
    local download_url="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-${arch}.zip"

    log_info "下载地址: $download_url"

    # 创建临时目录
    local tmp_dir=$(mktemp -d)
    cd "$tmp_dir"

    # 下载 Xray
    log_info "正在下载 Xray..."
    if ! wget -q --show-progress "$download_url" -O xray.zip; then
        log_error "下载失败"
        rm -rf "$tmp_dir"
        exit 1
    fi

    # 解压
    log_info "解压文件..."
    unzip -q xray.zip

    # 安装二进制文件
    mkdir -p "$XRAY_INSTALL_DIR"
    install -m 755 xray "$XRAY_INSTALL_DIR/xray"

    # 清理
    cd - > /dev/null
    rm -rf "$tmp_dir"

    log_info "Xray 安装完成: $(xray version | head -n 1)"
}

# 生成配置文件
generate_config() {
    log_info "生成 Xray 配置文件..."

    mkdir -p "$XRAY_CONFIG_DIR"
    mkdir -p "$XRAY_LOG_DIR"

    cat > "$XRAY_CONFIG_DIR/config.json" <<EOF
{
  "log": {
    "access": "$XRAY_LOG_DIR/access.log",
    "error": "$XRAY_LOG_DIR/error.log",
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
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

    log_info "配置文件已生成: $XRAY_CONFIG_DIR/config.json"
    log_info "VMess UUID: $XRAY_UUID"
    log_info "HTTP 端口: $XRAY_PORT"
    log_info "SOCKS5 端口: $XRAY_SOCKS_PORT"
}

# 创建 systemd 服务
create_systemd_service() {
    log_info "创建 systemd 服务..."

    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls/xray-core
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$XRAY_INSTALL_DIR/xray run -config $XRAY_CONFIG_DIR/config.json
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    # 重载 systemd 并启动服务
    systemctl daemon-reload
    systemctl enable xray
    systemctl start xray

    # 检查服务状态
    if systemctl is-active --quiet xray; then
        log_info "Xray 服务已成功启动"
    else
        log_error "Xray 服务启动失败"
        systemctl status xray
        exit 1
    fi
}

# 保存配置信息
save_config_info() {
    local info_file="$XRAY_CONFIG_DIR/connection-info.txt"

    cat > "$info_file" <<EOF
================================
Xray 代理服务配置信息
================================

安装时间: $(date)
版本: $XRAY_VERSION

连接信息:
- VMess UUID: $XRAY_UUID
- HTTP 端口: $XRAY_PORT
- SOCKS5 端口: $XRAY_SOCKS_PORT

本地测试:
curl --proxy socks5://127.0.0.1:$XRAY_SOCKS_PORT https://www.google.com

服务管理:
- 启动: systemctl start xray
- 停止: systemctl stop xray
- 重启: systemctl restart xray
- 状态: systemctl status xray
- 日志: journalctl -u xray -f

配置文件位置:
- 主配置: $XRAY_CONFIG_DIR/config.json
- 访问日志: $XRAY_LOG_DIR/access.log
- 错误日志: $XRAY_LOG_DIR/error.log

下一步:
1. 使用 Cloudflare Tunnel 暴露服务到公网
2. 配置客户端连接
3. 测试代理功能

================================
EOF

    cat "$info_file"
    log_info "配置信息已保存至: $info_file"
}

# 测试代理
test_proxy() {
    log_info "测试代理服务..."

    sleep 2  # 等待服务完全启动

    # 测试 SOCKS5 端口
    if nc -z 127.0.0.1 $XRAY_SOCKS_PORT 2>/dev/null; then
        log_info "SOCKS5 端口 $XRAY_SOCKS_PORT 可访问"
    else
        log_warn "SOCKS5 端口 $XRAY_SOCKS_PORT 无法访问"
    fi

    # 测试 HTTP 端口
    if nc -z 127.0.0.1 $XRAY_PORT 2>/dev/null; then
        log_info "VMess 端口 $XRAY_PORT 可访问"
    else
        log_warn "VMess 端口 $XRAY_PORT 无法访问"
    fi
}

# 主函数
main() {
    log_info "================================"
    log_info "Databricks Xray 代理部署脚本"
    log_info "================================"

    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi

    install_dependencies
    install_xray
    generate_config
    create_systemd_service
    test_proxy
    save_config_info

    log_info "================================"
    log_info "安装完成！"
    log_info "================================"
    log_info ""
    log_info "下一步："
    log_info "1. 运行 ./setup-cloudflared.sh 配置 Cloudflare Tunnel"
    log_info "2. 或查看 $XRAY_CONFIG_DIR/connection-info.txt 获取更多信息"
}

# 执行主函数
main "$@"
