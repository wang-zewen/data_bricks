#!/bin/bash
#
# VMess URL 生成脚本
# 用途：从配置文件生成 VMess URL，方便导入客户端
#

set -e

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# 检查依赖
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        log_info "安装 jq..."
        apt-get update -qq && apt-get install -y jq
    fi
}

# 从配置文件读取信息
read_config() {
    local config_file="/etc/xray/config.json"
    local domain_file="/etc/cloudflared/tunnel-domain.txt"

    if [ ! -f "$config_file" ]; then
        echo "错误：找不到 Xray 配置文件: $config_file"
        exit 1
    fi

    # 读取 UUID
    UUID=$(jq -r '.inbounds[0].settings.clients[0].id' "$config_file")

    # 读取端口
    PORT="443"

    # 读取域名
    if [ -f "$domain_file" ]; then
        DOMAIN=$(cat "$domain_file")
    else
        echo "请输入您的域名："
        read -r DOMAIN
    fi
}

# 生成 VMess URL
generate_vmess_url() {
    local config_json=$(cat <<EOF
{
  "v": "2",
  "ps": "Databricks-Xray-Proxy",
  "add": "$DOMAIN",
  "port": "$PORT",
  "id": "$UUID",
  "aid": "0",
  "scy": "auto",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": "tls",
  "sni": "$DOMAIN",
  "alpn": ""
}
EOF
)

    # Base64 编码
    local vmess_url="vmess://$(echo -n "$config_json" | base64 -w 0)"

    echo ""
    log_info "================================"
    log_info "VMess URL 生成成功"
    log_info "================================"
    echo ""
    echo "连接信息："
    echo "  域名: $DOMAIN"
    echo "  端口: $PORT"
    echo "  UUID: $UUID"
    echo ""
    echo "VMess URL (复制下面完整内容)："
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$vmess_url"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "使用方法："
    echo "1. 复制上面的完整 URL"
    echo "2. 在 V2RayN/V2RayNG 等客户端中选择 '从剪贴板导入'"
    echo ""

    # 生成二维码（如果安装了 qrencode）
    if command -v qrencode &> /dev/null; then
        echo "二维码（使用手机客户端扫描）："
        qrencode -t ANSIUTF8 "$vmess_url"
    else
        echo "提示：安装 qrencode 可以生成二维码"
        echo "  apt-get install qrencode"
    fi

    # 保存到文件
    echo "$vmess_url" > /tmp/vmess-url.txt
    echo ""
    log_info "URL 已保存到: /tmp/vmess-url.txt"
}

# 主函数
main() {
    check_dependencies
    read_config
    generate_vmess_url
}

main "$@"
