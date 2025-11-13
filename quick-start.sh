#!/bin/bash
#
# 快速启动脚本
# 用途：一键完成所有安装和配置步骤
#

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    echo -e "${CYAN}[STEP]${NC} $1"
}

# 显示横幅
show_banner() {
    clear
    echo -e "${BLUE}"
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║   ____        _        _          _      _                 ║
║  |  _ \  __ _| |_ __ _| |__  _ __(_) ___| | _____          ║
║  | | | |/ _` | __/ _` | '_ \| '__| |/ __| |/ / __|         ║
║  | |_| | (_| | || (_| | |_) | |  | | (__|   <\__ \         ║
║  |____/ \__,_|\__\__,_|_.__/|_|  |_|\___|_|\_\___/         ║
║                                                            ║
║              Xray 代理一键部署脚本                         ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# 检查系统要求
check_requirements() {
    log_step "检查系统要求..."

    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        echo "运行: sudo $0"
        exit 1
    fi

    # 检查操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "操作系统: $PRETTY_NAME"
    else
        log_warn "无法检测操作系统版本"
    fi

    # 检查架构
    local arch=$(uname -m)
    log_info "系统架构: $arch"

    if [ "$arch" != "x86_64" ] && [ "$arch" != "aarch64" ] && [ "$arch" != "arm64" ]; then
        log_error "不支持的架构: $arch"
        exit 1
    fi

    # 检查网络连接
    log_info "检查网络连接..."
    if ! ping -c 1 github.com &>/dev/null; then
        log_error "无法连接到 GitHub，请检查网络连接"
        exit 1
    fi

    log_info "系统要求检查通过"
}

# 配置向导
configuration_wizard() {
    log_step "配置向导"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "请提供以下信息："
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Cloudflare Token
    if [ -z "$CF_TOKEN" ]; then
        echo "请输入 Cloudflare API Token:"
        echo "(如果暂时没有，可以按回车跳过，稍后手动配置)"
        read -r CF_TOKEN

        if [ -z "$CF_TOKEN" ]; then
            log_warn "跳过 Cloudflare Tunnel 配置"
            SKIP_CLOUDFLARE=true
        else
            export CF_TOKEN
        fi
    fi

    # 域名
    if [ "$SKIP_CLOUDFLARE" != true ]; then
        echo ""
        echo "请输入您想使用的域名 (例如: proxy.yourdomain.com):"
        read -r DOMAIN
        export DOMAIN
    fi

    # UUID (可选)
    echo ""
    echo "是否自定义 UUID? (留空自动生成)"
    read -r CUSTOM_UUID

    if [ -n "$CUSTOM_UUID" ]; then
        export XRAY_UUID="$CUSTOM_UUID"
    fi

    # 确认配置
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "配置摘要："
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Cloudflare Token: ${CF_TOKEN:0:10}..." || echo "未配置"
    echo "域名: ${DOMAIN:-未配置}"
    echo "自定义 UUID: ${XRAY_UUID:-自动生成}"
    echo ""
    read -p "确认配置并继续? (y/N): " confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "已取消安装"
        exit 0
    fi
}

# 安装 Xray
install_xray_wrapper() {
    log_step "步骤 1/3: 安装 Xray"
    echo ""

    if [ ! -f "./install-xray-proxy.sh" ]; then
        log_error "找不到 install-xray-proxy.sh"
        exit 1
    fi

    chmod +x ./install-xray-proxy.sh
    ./install-xray-proxy.sh

    echo ""
    log_info "Xray 安装完成"
    sleep 2
}

# 配置 Cloudflare Tunnel
setup_cloudflare_wrapper() {
    if [ "$SKIP_CLOUDFLARE" = true ]; then
        log_warn "跳过 Cloudflare Tunnel 配置"
        return 0
    fi

    log_step "步骤 2/3: 配置 Cloudflare Tunnel"
    echo ""

    if [ ! -f "./setup-cloudflared.sh" ]; then
        log_error "找不到 setup-cloudflared.sh"
        exit 1
    fi

    chmod +x ./setup-cloudflared.sh

    # 自动输入域名
    if [ -n "$DOMAIN" ]; then
        echo "$DOMAIN" | ./setup-cloudflared.sh
    else
        ./setup-cloudflared.sh
    fi

    echo ""
    log_info "Cloudflare Tunnel 配置完成"
    sleep 2
}

# 运行状态检查
run_status_check() {
    log_step "步骤 3/3: 验证安装"
    echo ""

    if [ -f "./utils/check-status.sh" ]; then
        chmod +x ./utils/check-status.sh
        ./utils/check-status.sh
    else
        log_warn "找不到状态检查脚本，跳过"
    fi
}

# 显示完成信息
show_completion() {
    echo ""
    echo -e "${GREEN}"
    cat << "EOF"
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║                   🎉 安装完成！🎉                          ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "下一步操作："
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # 连接信息
    if [ -f "/etc/cloudflared/connection-info.txt" ]; then
        echo "📋 查看连接信息:"
        echo "   cat /etc/cloudflared/connection-info.txt"
        echo ""
    fi

    # VMess URL
    if [ -f "./utils/generate-vmess-url.sh" ]; then
        echo "🔗 生成 VMess URL:"
        echo "   ./utils/generate-vmess-url.sh"
        echo ""
    fi

    # 客户端配置
    echo "📱 配置客户端:"
    echo "   查看 client-configs/ 目录下的配置示例"
    echo ""

    # 管理命令
    echo "🔧 管理命令:"
    echo "   检查状态: ./utils/check-status.sh"
    echo "   查看日志: journalctl -u xray -f"
    echo "   重启服务: systemctl restart xray"
    echo ""

    # 文档
    echo "📚 完整文档:"
    echo "   README.md"
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 如果跳过了 Cloudflare 配置
    if [ "$SKIP_CLOUDFLARE" = true ]; then
        echo ""
        log_warn "您跳过了 Cloudflare Tunnel 配置"
        echo ""
        echo "要手动配置，请运行:"
        echo "  export CF_TOKEN='your-token-here'"
        echo "  ./setup-cloudflared.sh"
        echo ""
    fi
}

# 错误处理
error_handler() {
    echo ""
    log_error "安装过程中出现错误"
    echo ""
    echo "故障排查："
    echo "  1. 查看错误日志: journalctl -xe"
    echo "  2. 检查网络连接"
    echo "  3. 查看详细日志输出"
    echo "  4. 参考 README.md 的故障排查章节"
    echo ""
    echo "如需帮助，请提交 Issue"
    exit 1
}

# 主函数
main() {
    # 设置错误处理
    trap error_handler ERR

    show_banner
    check_requirements
    configuration_wizard

    echo ""
    log_info "开始安装流程..."
    echo ""

    install_xray_wrapper
    setup_cloudflare_wrapper
    run_status_check
    show_completion
}

# 执行主函数
main "$@"
