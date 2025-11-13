#!/bin/bash
################################################################################
#
# Databricks Xray 代理一体化部署脚本
#
# 用途：在Databricks集群上一键部署Xray代理服务（可选Cloudflare Tunnel）
#
# 使用方法：
#   方式1 - 作为Databricks Init Script:
#     1. 上传到DBFS: dbutils.fs.put("/databricks/init-scripts/xray.sh", script, True)
#     2. 配置环境变量（在集群配置中）:
#        - XRAY_UUID: VMess UUID（可选，留空自动生成）
#        - CF_TOKEN: Cloudflare API Token（可选，用于Tunnel）
#        - TUNNEL_DOMAIN: 域名（可选，如proxy.example.com）
#     3. 添加Init Script: dbfs:/databricks/init-scripts/xray.sh
#
#   方式2 - 手动执行:
#     export XRAY_UUID="your-uuid"
#     export CF_TOKEN="your-cloudflare-token"
#     export TUNNEL_DOMAIN="proxy.yourdomain.com"
#     sudo ./databricks-xray-allinone.sh
#
# 环境变量:
#   XRAY_VERSION       - Xray版本 (默认: latest)
#   XRAY_UUID          - VMess UUID (留空自动生成)
#   XRAY_PORT          - VMess端口 (默认: 10809)
#   XRAY_SOCKS_PORT    - SOCKS5端口 (默认: 1080)
#   CF_TOKEN           - Cloudflare API Token (可选)
#   TUNNEL_DOMAIN      - 隧道域名 (可选)
#   TUNNEL_NAME        - 隧道名称 (默认: databricks-xray)
#   SKIP_CLOUDFLARE    - 跳过Cloudflare配置 (yes/no)
#   LOG_LEVEL          - 日志级别 (默认: warning)
#
################################################################################

set -e

################################################################################
# 全局配置
################################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 默认配置
XRAY_VERSION="${XRAY_VERSION:-latest}"
XRAY_INSTALL_DIR="${XRAY_INSTALL_DIR:-/usr/local/bin}"
XRAY_CONFIG_DIR="${XRAY_CONFIG_DIR:-/etc/xray}"
XRAY_LOG_DIR="${XRAY_LOG_DIR:-/var/log/xray}"
XRAY_PORT="${XRAY_PORT:-10809}"
XRAY_SOCKS_PORT="${XRAY_SOCKS_PORT:-1080}"
XRAY_UUID="${XRAY_UUID:-$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo '')}"
LOG_LEVEL="${LOG_LEVEL:-warning}"

# Cloudflare配置
CF_TOKEN="${CF_TOKEN:-}"
TUNNEL_DOMAIN="${TUNNEL_DOMAIN:-}"
TUNNEL_NAME="${TUNNEL_NAME:-databricks-xray}"
CLOUDFLARED_DIR="${CLOUDFLARED_DIR:-/etc/cloudflared}"
SKIP_CLOUDFLARE="${SKIP_CLOUDFLARE:-no}"

# 检测Databricks环境
IS_DATABRICKS=false
if [ -n "${DATABRICKS_RUNTIME_VERSION:-}" ] || [ -d "/databricks" ]; then
    IS_DATABRICKS=true
fi

# 日志文件
INSTALL_LOG="/tmp/xray-install-$(date +%Y%m%d-%H%M%S).log"

################################################################################
# 日志函数
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$INSTALL_LOG"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$INSTALL_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$INSTALL_LOG"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$INSTALL_LOG"
}

################################################################################
# 工具函数
################################################################################

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

# 检测cloudflared架构
detect_cf_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "amd64" ;;
    esac
}

# 检查命令是否存在
command_exists() {
    command -v "$1" &> /dev/null
}

# 生成UUID
generate_uuid() {
    if [ -f /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    elif command_exists uuidgen; then
        uuidgen
    else
        # 简单的UUID生成（作为后备）
        od -x /dev/urandom | head -1 | awk '{OFS="-"; print $2$3,$4,$5,$6,$7$8$9}'
    fi
}

################################################################################
# 环境检查
################################################################################

check_requirements() {
    log_step "检查系统要求..."

    # 检查root权限
    if [ "$EUID" -ne 0 ]; then
        log_error "需要root权限运行此脚本"
        exit 1
    fi

    # 检测操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "操作系统: $PRETTY_NAME"
    fi

    # 检测架构
    local arch=$(uname -m)
    log_info "系统架构: $arch"

    # Databricks环境检测
    if [ "$IS_DATABRICKS" = true ]; then
        log_info "检测到Databricks环境"
        log_info "Runtime版本: ${DATABRICKS_RUNTIME_VERSION:-未知}"
    fi

    # 确保UUID存在
    if [ -z "$XRAY_UUID" ]; then
        XRAY_UUID=$(generate_uuid)
        log_info "生成新UUID: $XRAY_UUID"
    fi

    log_info "配置摘要:"
    log_info "  - Xray版本: $XRAY_VERSION"
    log_info "  - VMess端口: $XRAY_PORT"
    log_info "  - SOCKS5端口: $XRAY_SOCKS_PORT"
    log_info "  - UUID: ${XRAY_UUID:0:8}..."

    if [ -n "$CF_TOKEN" ] && [ "$SKIP_CLOUDFLARE" != "yes" ]; then
        log_info "  - Cloudflare Tunnel: 启用"
        log_info "  - 隧道域名: ${TUNNEL_DOMAIN:-未配置}"
    else
        log_info "  - Cloudflare Tunnel: 禁用"
    fi
}

################################################################################
# 安装依赖
################################################################################

install_dependencies() {
    log_step "安装系统依赖..."

    if command_exists apt-get; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq 2>&1 | tee -a "$INSTALL_LOG"
        apt-get install -y -qq curl wget unzip jq netcat-openbsd 2>&1 | tee -a "$INSTALL_LOG"
    elif command_exists yum; then
        yum install -y -q curl wget unzip jq nc 2>&1 | tee -a "$INSTALL_LOG"
    else
        log_error "不支持的包管理器"
        exit 1
    fi

    log_info "系统依赖安装完成"
}

################################################################################
# 安装Xray
################################################################################

install_xray() {
    log_step "安装Xray..."

    # 获取版本
    if [ "$XRAY_VERSION" = "latest" ]; then
        log_info "获取最新版本..."
        XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name | sed 's/v//')
        if [ -z "$XRAY_VERSION" ] || [ "$XRAY_VERSION" = "null" ]; then
            log_warn "无法获取最新版本，使用默认版本 1.8.4"
            XRAY_VERSION="1.8.4"
        fi
    fi
    log_info "Xray版本: $XRAY_VERSION"

    # 检测架构
    local arch=$(detect_architecture)
    local download_url="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-${arch}.zip"

    log_info "下载地址: $download_url"

    # 创建临时目录
    local tmp_dir=$(mktemp -d)
    cd "$tmp_dir"

    # 下载
    log_info "下载Xray..."
    if ! wget -q --show-progress --timeout=30 "$download_url" -O xray.zip 2>&1 | tee -a "$INSTALL_LOG"; then
        log_error "下载失败"
        rm -rf "$tmp_dir"
        exit 1
    fi

    # 解压
    log_info "解压文件..."
    unzip -q xray.zip

    # 安装
    mkdir -p "$XRAY_INSTALL_DIR"
    install -m 755 xray "$XRAY_INSTALL_DIR/xray"

    # 清理
    cd - > /dev/null
    rm -rf "$tmp_dir"

    # 验证安装
    if command_exists xray; then
        log_info "Xray安装成功: $(xray version | head -n 1)"
    else
        log_error "Xray安装失败"
        exit 1
    fi
}

################################################################################
# 配置Xray
################################################################################

configure_xray() {
    log_step "配置Xray..."

    # 创建目录
    mkdir -p "$XRAY_CONFIG_DIR"
    mkdir -p "$XRAY_LOG_DIR"

    # 生成配置文件
    cat > "$XRAY_CONFIG_DIR/config.json" <<EOF
{
  "log": {
    "access": "$XRAY_LOG_DIR/access.log",
    "error": "$XRAY_LOG_DIR/error.log",
    "loglevel": "$LOG_LEVEL"
  },
  "inbounds": [
    {
      "tag": "vmess-in",
      "port": $XRAY_PORT,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$XRAY_UUID",
            "alterId": 0,
            "email": "databricks@proxy"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      }
    },
    {
      "tag": "socks-in",
      "port": $XRAY_SOCKS_PORT,
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "ip": "127.0.0.1"
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {
        "response": {
          "type": "http"
        }
      }
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF

    log_info "配置文件已生成: $XRAY_CONFIG_DIR/config.json"

    # 验证配置
    if xray -test -config "$XRAY_CONFIG_DIR/config.json" 2>&1 | tee -a "$INSTALL_LOG"; then
        log_info "配置文件验证成功"
    else
        log_error "配置文件验证失败"
        exit 1
    fi
}

################################################################################
# 创建Systemd服务
################################################################################

create_xray_service() {
    log_step "创建Xray systemd服务..."

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

    # 重载并启动
    systemctl daemon-reload
    systemctl enable xray 2>&1 | tee -a "$INSTALL_LOG"
    systemctl start xray 2>&1 | tee -a "$INSTALL_LOG"

    # 等待启动
    sleep 3

    # 检查状态
    if systemctl is-active --quiet xray; then
        log_info "Xray服务启动成功"
    else
        log_error "Xray服务启动失败"
        systemctl status xray --no-pager | tee -a "$INSTALL_LOG"
        exit 1
    fi
}

################################################################################
# 安装Cloudflare Tunnel
################################################################################

install_cloudflared() {
    if [ "$SKIP_CLOUDFLARE" = "yes" ] || [ -z "$CF_TOKEN" ]; then
        log_info "跳过Cloudflare Tunnel安装"
        return 0
    fi

    log_step "安装Cloudflare Tunnel..."

    local arch=$(detect_cf_architecture)
    local download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}"

    log_info "下载cloudflared..."
    if ! wget -q --show-progress --timeout=30 "$download_url" -O /usr/local/bin/cloudflared 2>&1 | tee -a "$INSTALL_LOG"; then
        log_warn "Cloudflared下载失败，跳过Tunnel配置"
        return 1
    fi

    chmod +x /usr/local/bin/cloudflared

    if command_exists cloudflared; then
        log_info "Cloudflared安装成功: $(cloudflared --version 2>&1 | head -n 1)"
    else
        log_warn "Cloudflared安装失败"
        return 1
    fi
}

################################################################################
# 配置Cloudflare Tunnel
################################################################################

configure_cloudflared() {
    if [ "$SKIP_CLOUDFLARE" = "yes" ] || [ -z "$CF_TOKEN" ]; then
        return 0
    fi

    if ! command_exists cloudflared; then
        log_warn "Cloudflared未安装，跳过配置"
        return 1
    fi

    log_step "配置Cloudflare Tunnel..."

    mkdir -p "$CLOUDFLARED_DIR"

    # 创建隧道（简化版本，适用于自动化）
    log_info "创建隧道: $TUNNEL_NAME"

    # 这里使用简化的配置方式
    # 注意：完整的Tunnel配置需要更多步骤，这里提供基础框架

    cat > "$CLOUDFLARED_DIR/config.yml" <<EOF
# Cloudflare Tunnel配置
# 需要手动完成Tunnel创建和DNS配置

# 使用以下命令完成配置:
# 1. cloudflared tunnel login
# 2. cloudflared tunnel create $TUNNEL_NAME
# 3. cloudflared tunnel route dns $TUNNEL_NAME $TUNNEL_DOMAIN

url: http://localhost:$XRAY_PORT
tunnel: $TUNNEL_NAME
credentials-file: $CLOUDFLARED_DIR/credentials.json

# 日志
loglevel: info
EOF

    log_info "Cloudflared配置模板已创建"
    log_warn "需要手动完成Cloudflare Tunnel认证和配置"
    log_warn "详细步骤请参考: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps"
}

################################################################################
# 生成连接信息
################################################################################

generate_connection_info() {
    log_step "生成连接信息..."

    local info_file="$XRAY_CONFIG_DIR/connection-info.txt"
    local vmess_config_file="$XRAY_CONFIG_DIR/vmess-config.json"

    # 生成文本信息
    cat > "$info_file" <<EOF
╔══════════════════════════════════════════════════════════╗
║          Xray 代理服务连接信息                          ║
╚══════════════════════════════════════════════════════════╝

安装时间: $(date)
安装日志: $INSTALL_LOG

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
基本信息
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

UUID:           $XRAY_UUID
VMess 端口:     $XRAY_PORT
SOCKS5 端口:    $XRAY_SOCKS_PORT
日志级别:       $LOG_LEVEL

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
本地测试
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SOCKS5 测试:
  curl -x socks5://127.0.0.1:$XRAY_SOCKS_PORT https://www.google.com

Python 测试:
  import requests
  proxies = {'http': 'socks5://127.0.0.1:$XRAY_SOCKS_PORT',
             'https': 'socks5://127.0.0.1:$XRAY_SOCKS_PORT'}
  requests.get('https://www.google.com', proxies=proxies)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
服务管理
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

启动服务:       systemctl start xray
停止服务:       systemctl stop xray
重启服务:       systemctl restart xray
查看状态:       systemctl status xray
查看日志:       journalctl -u xray -f

访问日志:       tail -f $XRAY_LOG_DIR/access.log
错误日志:       tail -f $XRAY_LOG_DIR/error.log

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
客户端配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

VMess 配置 (需要配置Cloudflare Tunnel后使用):
  服务器地址: ${TUNNEL_DOMAIN:-your-domain.com}
  端口: 443
  UUID: $XRAY_UUID
  额外ID: 0
  加密: auto
  传输协议: tcp
  TLS: 启用

详细配置请查看: $vmess_config_file

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Cloudflare Tunnel 配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

    if [ -n "$CF_TOKEN" ] && [ "$SKIP_CLOUDFLARE" != "yes" ]; then
        cat >> "$info_file" <<EOF
状态: 已安装
配置文件: $CLOUDFLARED_DIR/config.yml

手动配置步骤:
1. cloudflared tunnel login
2. cloudflared tunnel create $TUNNEL_NAME
3. cloudflared tunnel route dns $TUNNEL_NAME $TUNNEL_DOMAIN
4. systemctl start cloudflared

参考文档:
https://developers.cloudflare.com/cloudflare-one/connections/connect-apps
EOF
    else
        cat >> "$info_file" <<EOF
状态: 未配置

如需配置Cloudflare Tunnel:
1. 获取Cloudflare API Token
2. 设置环境变量并重新运行脚本:
   export CF_TOKEN="your-token"
   export TUNNEL_DOMAIN="proxy.yourdomain.com"
   ./databricks-xray-allinone.sh
EOF
    fi

    cat >> "$info_file" <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
注意事项
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. 请妥善保管UUID，不要泄露
2. 定期更新Xray版本
3. 监控日志文件大小
4. 遵守当地法律法规
5. 仅用于学习和正当用途

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

    # 生成VMess配置JSON
    cat > "$vmess_config_file" <<EOF
{
  "v": "2",
  "ps": "Databricks-Xray",
  "add": "${TUNNEL_DOMAIN:-your-domain.com}",
  "port": "443",
  "id": "$XRAY_UUID",
  "aid": "0",
  "scy": "auto",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": "tls",
  "sni": "${TUNNEL_DOMAIN:-your-domain.com}",
  "alpn": ""
}
EOF

    # 输出到控制台
    cat "$info_file"

    log_info "连接信息已保存到: $info_file"
    log_info "VMess配置已保存到: $vmess_config_file"

    # 如果在Databricks环境，尝试保存到DBFS
    if [ "$IS_DATABRICKS" = true ] && [ -n "${DB_HOME:-}" ]; then
        local db_info="$DB_HOME/xray-connection-info.txt"
        cp "$info_file" "$db_info" 2>/dev/null || true
        log_info "连接信息已复制到: $db_info"
    fi
}

################################################################################
# 健康检查
################################################################################

health_check() {
    log_step "执行健康检查..."

    local status=0

    # 检查Xray服务
    if systemctl is-active --quiet xray; then
        log_info "✓ Xray服务运行正常"
    else
        log_error "✗ Xray服务未运行"
        status=1
    fi

    # 检查端口
    sleep 2
    if nc -z 127.0.0.1 "$XRAY_PORT" 2>/dev/null; then
        log_info "✓ VMess端口 $XRAY_PORT 可访问"
    else
        log_warn "✗ VMess端口 $XRAY_PORT 不可访问"
        status=1
    fi

    if nc -z 127.0.0.1 "$XRAY_SOCKS_PORT" 2>/dev/null; then
        log_info "✓ SOCKS5端口 $XRAY_SOCKS_PORT 可访问"
    else
        log_warn "✗ SOCKS5端口 $XRAY_SOCKS_PORT 不可访问"
        status=1
    fi

    # 测试SOCKS5代理
    if command_exists curl; then
        if timeout 10 curl -s -x socks5://127.0.0.1:$XRAY_SOCKS_PORT https://www.google.com > /dev/null 2>&1; then
            log_info "✓ SOCKS5代理测试成功"
        else
            log_warn "✗ SOCKS5代理测试失败（可能是网络问题）"
        fi
    fi

    return $status
}

################################################################################
# 清理函数
################################################################################

cleanup_on_error() {
    log_error "安装过程中出现错误"
    log_info "日志文件: $INSTALL_LOG"
    log_info "请查看日志排查问题"
}

################################################################################
# 主函数
################################################################################

main() {
    # 设置错误处理
    trap cleanup_on_error ERR

    # 显示横幅
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                                          ║${NC}"
    echo -e "${BLUE}║      Databricks Xray 代理一体化部署脚本                 ║${NC}"
    echo -e "${BLUE}║                                                          ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_info "开始部署流程..."
    log_info "日志文件: $INSTALL_LOG"
    echo ""

    # 执行安装步骤
    check_requirements
    install_dependencies
    install_xray
    configure_xray
    create_xray_service

    # Cloudflare Tunnel（可选）
    install_cloudflared
    configure_cloudflared

    # 生成信息
    generate_connection_info

    # 健康检查
    health_check

    # 完成
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                          ║${NC}"
    echo -e "${GREEN}║                  🎉 部署完成！🎉                         ║${NC}"
    echo -e "${GREEN}║                                                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_info "安装日志: $INSTALL_LOG"
    log_info "连接信息: $XRAY_CONFIG_DIR/connection-info.txt"
    echo ""
    log_info "查看连接信息: cat $XRAY_CONFIG_DIR/connection-info.txt"
    log_info "查看服务状态: systemctl status xray"
    echo ""
}

################################################################################
# 执行主函数
################################################################################

main "$@"
