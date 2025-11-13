#!/bin/bash
#
# Cloudflare Tunnel 配置脚本
# 用途：将Databricks上的Xray代理服务通过Cloudflare Tunnel暴露到公网
# 前置条件：已安装Xray并正常运行
#

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 配置变量
CLOUDFLARED_DIR="${CLOUDFLARED_DIR:-/etc/cloudflared}"
XRAY_PORT="${XRAY_PORT:-10809}"
TUNNEL_NAME="${TUNNEL_NAME:-databricks-xray-proxy}"
CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-}"
CF_TOKEN="${CF_TOKEN:-}"

# 检测系统架构
detect_architecture() {
    local arch=$(uname -m)
    case $arch in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            log_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
}

# 安装 cloudflared
install_cloudflared() {
    log_step "开始安装 cloudflared..."

    local arch=$(detect_architecture)
    local download_url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}"

    log_info "下载 cloudflared..."
    wget -q --show-progress "$download_url" -O /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared

    log_info "cloudflared 安装完成: $(cloudflared --version)"
}

# 检查环境变量
check_env() {
    log_step "检查环境变量..."

    if [ -f ".env" ]; then
        log_info "加载 .env 文件..."
        source .env
    fi

    if [ -z "$CF_TOKEN" ]; then
        log_error "未设置 CF_TOKEN 环境变量"
        echo ""
        echo "请按以下步骤操作："
        echo "1. 访问 https://dash.cloudflare.com/profile/api-tokens"
        echo "2. 创建一个具有以下权限的 API Token："
        echo "   - Account.Cloudflare Tunnel: Edit"
        echo "   - Zone.DNS: Edit"
        echo "3. 将 token 设置为环境变量："
        echo "   export CF_TOKEN='your-token-here'"
        echo ""
        exit 1
    fi
}

# 认证 Cloudflare
authenticate() {
    log_step "认证 Cloudflare 账户..."

    mkdir -p "$CLOUDFLARED_DIR"

    # 使用 token 登录
    if ! cloudflared tunnel login --token "$CF_TOKEN" 2>/dev/null; then
        # 如果 token 方式失败，尝试交互式登录
        log_warn "Token 认证失败，切换到交互式登录..."
        cloudflared tunnel login
    fi

    if [ -f "$HOME/.cloudflared/cert.pem" ]; then
        cp "$HOME/.cloudflared/cert.pem" "$CLOUDFLARED_DIR/"
        log_info "认证成功"
    else
        log_error "认证失败"
        exit 1
    fi
}

# 创建隧道
create_tunnel() {
    log_step "创建 Cloudflare Tunnel..."

    # 检查隧道是否已存在
    if cloudflared tunnel list | grep -q "$TUNNEL_NAME"; then
        log_warn "隧道 '$TUNNEL_NAME' 已存在，将使用现有隧道"
        return 0
    fi

    # 创建新隧道
    cloudflared tunnel create "$TUNNEL_NAME"

    log_info "隧道创建成功"
}

# 获取隧道 ID
get_tunnel_id() {
    cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}'
}

# 生成配置文件
generate_config() {
    log_step "生成 cloudflared 配置..."

    local tunnel_id=$(get_tunnel_id)

    if [ -z "$tunnel_id" ]; then
        log_error "无法获取隧道 ID"
        exit 1
    fi

    cat > "$CLOUDFLARED_DIR/config.yml" <<EOF
tunnel: $tunnel_id
credentials-file: $CLOUDFLARED_DIR/$tunnel_id.json

ingress:
  # 将所有流量路由到本地 Xray 服务
  - service: http://localhost:$XRAY_PORT
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      keepAliveConnections: 100
  # 默认服务（必需）
  - service: http_status:404

# 日志配置
loglevel: info

# 性能优化
no-autoupdate: true
EOF

    log_info "配置文件已生成: $CLOUDFLARED_DIR/config.yml"
}

# 配置 DNS
configure_dns() {
    log_step "配置 DNS 记录..."

    local tunnel_id=$(get_tunnel_id)

    echo ""
    echo "请输入您想要使用的域名（例如：proxy.yourdomain.com）："
    read -r domain

    if [ -z "$domain" ]; then
        log_error "域名不能为空"
        exit 1
    fi

    log_info "配置 DNS: $domain -> $TUNNEL_NAME"

    # 创建 DNS 记录
    cloudflared tunnel route dns "$TUNNEL_NAME" "$domain"

    log_info "DNS 配置完成"
    echo "您的代理服务将通过以下地址访问："
    echo "  https://$domain"

    # 保存域名信息
    echo "$domain" > "$CLOUDFLARED_DIR/tunnel-domain.txt"
}

# 创建 systemd 服务
create_systemd_service() {
    log_step "创建 systemd 服务..."

    cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --config $CLOUDFLARED_DIR/config.yml run
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable cloudflared
    systemctl start cloudflared

    sleep 3

    if systemctl is-active --quiet cloudflared; then
        log_info "Cloudflare Tunnel 服务已成功启动"
    else
        log_error "Cloudflare Tunnel 服务启动失败"
        systemctl status cloudflared
        exit 1
    fi
}

# 测试隧道
test_tunnel() {
    log_step "测试隧道连接..."

    if [ -f "$CLOUDFLARED_DIR/tunnel-domain.txt" ]; then
        local domain=$(cat "$CLOUDFLARED_DIR/tunnel-domain.txt")

        log_info "等待 DNS 传播（最多60秒）..."
        local count=0
        while [ $count -lt 12 ]; do
            if curl -s -o /dev/null -w "%{http_code}" "https://$domain" | grep -q "200\|404\|400"; then
                log_info "隧道测试成功！"
                echo ""
                echo "您的代理服务已可通过以下地址访问："
                echo "  https://$domain"
                return 0
            fi
            sleep 5
            count=$((count + 1))
        done

        log_warn "DNS 可能尚未完全传播，请稍后测试"
    fi
}

# 生成连接信息
generate_connection_info() {
    log_step "生成连接信息..."

    local domain=$(cat "$CLOUDFLARED_DIR/tunnel-domain.txt" 2>/dev/null || echo "未配置")
    local tunnel_id=$(get_tunnel_id)
    local xray_config="/etc/xray/config.json"
    local uuid=$(grep -oP '"id":\s*"\K[^"]+' "$xray_config" 2>/dev/null | head -n 1 || echo "未找到")

    local info_file="$CLOUDFLARED_DIR/connection-info.txt"

    cat > "$info_file" <<EOF
================================
Cloudflare Tunnel 连接信息
================================

配置时间: $(date)

隧道信息:
- 隧道名称: $TUNNEL_NAME
- 隧道 ID: $tunnel_id
- 公网域名: $domain

Xray 配置:
- UUID: $uuid
- 端口: $XRAY_PORT

客户端配置示例:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

VMess 配置:
{
  "add": "$domain",
  "port": "443",
  "id": "$uuid",
  "aid": "0",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": "tls"
}

Clash 配置:
proxies:
  - name: "Databricks-Proxy"
    type: vmess
    server: $domain
    port: 443
    uuid: $uuid
    alterId: 0
    cipher: auto
    tls: true
    skip-cert-verify: false

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

管理命令:
- 查看隧道状态: systemctl status cloudflared
- 查看隧道日志: journalctl -u cloudflared -f
- 重启隧道: systemctl restart cloudflared
- 查看所有隧道: cloudflared tunnel list
- 查看隧道信息: cloudflared tunnel info $TUNNEL_NAME

配置文件位置:
- Cloudflared 配置: $CLOUDFLARED_DIR/config.yml
- 凭证文件: $CLOUDFLARED_DIR/$tunnel_id.json

测试命令:
curl -x https://$domain https://www.google.com

================================
EOF

    cat "$info_file"
    log_info "连接信息已保存至: $info_file"
}

# 主函数
main() {
    echo ""
    log_info "================================"
    log_info "Cloudflare Tunnel 配置脚本"
    log_info "================================"
    echo ""

    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi

    # 检查 Xray 是否运行
    if ! systemctl is-active --quiet xray; then
        log_error "Xray 服务未运行，请先运行 install-xray-proxy.sh"
        exit 1
    fi

    check_env
    install_cloudflared
    authenticate
    create_tunnel
    generate_config
    configure_dns
    create_systemd_service
    test_tunnel
    generate_connection_info

    echo ""
    log_info "================================"
    log_info "配置完成！"
    log_info "================================"
    echo ""
    log_info "请查看 $CLOUDFLARED_DIR/connection-info.txt 获取客户端配置信息"
}

# 执行主函数
main "$@"
