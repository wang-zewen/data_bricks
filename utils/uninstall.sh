#!/bin/bash
#
# 卸载脚本
# 用途：完全卸载 Xray 和 Cloudflare Tunnel
#

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# 确认卸载
confirm_uninstall() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_warn "警告：即将完全卸载 Xray 和 Cloudflare Tunnel"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "这将删除："
    echo "  - Xray 服务和配置"
    echo "  - Cloudflare Tunnel 服务和配置"
    echo "  - 所有日志文件"
    echo "  - 相关的二进制文件"
    echo ""
    read -p "确定要继续吗？(输入 YES 继续): " confirm

    if [ "$confirm" != "YES" ]; then
        log_info "已取消卸载"
        exit 0
    fi
}

# 停止服务
stop_services() {
    log_info "停止服务..."

    if systemctl is-active --quiet xray; then
        systemctl stop xray
        log_info "已停止 Xray 服务"
    fi

    if systemctl is-active --quiet cloudflared; then
        systemctl stop cloudflared
        log_info "已停止 Cloudflare Tunnel 服务"
    fi
}

# 禁用服务
disable_services() {
    log_info "禁用服务自启动..."

    if systemctl is-enabled --quiet xray 2>/dev/null; then
        systemctl disable xray
        log_info "已禁用 Xray 服务"
    fi

    if systemctl is-enabled --quiet cloudflared 2>/dev/null; then
        systemctl disable cloudflared
        log_info "已禁用 Cloudflare Tunnel 服务"
    fi
}

# 删除服务文件
remove_service_files() {
    log_info "删除 systemd 服务文件..."

    if [ -f "/etc/systemd/system/xray.service" ]; then
        rm -f /etc/systemd/system/xray.service
        log_info "已删除 Xray 服务文件"
    fi

    if [ -f "/etc/systemd/system/cloudflared.service" ]; then
        rm -f /etc/systemd/system/cloudflared.service
        log_info "已删除 Cloudflare Tunnel 服务文件"
    fi

    systemctl daemon-reload
}

# 删除 Cloudflare Tunnel
remove_cloudflare_tunnel() {
    log_info "删除 Cloudflare Tunnel..."

    # 获取隧道名称
    local tunnel_name="${TUNNEL_NAME:-databricks-xray-proxy}"

    # 删除隧道
    if command -v cloudflared &> /dev/null; then
        if cloudflared tunnel list 2>/dev/null | grep -q "$tunnel_name"; then
            log_warn "删除隧道: $tunnel_name"
            cloudflared tunnel delete -f "$tunnel_name" 2>/dev/null || log_warn "隧道删除失败（可能需要手动删除）"
        fi
    fi
}

# 删除二进制文件
remove_binaries() {
    log_info "删除二进制文件..."

    if [ -f "/usr/local/bin/xray" ]; then
        rm -f /usr/local/bin/xray
        log_info "已删除 Xray 二进制文件"
    fi

    if [ -f "/usr/local/bin/cloudflared" ]; then
        rm -f /usr/local/bin/cloudflared
        log_info "已删除 cloudflared 二进制文件"
    fi
}

# 删除配置文件
remove_configs() {
    log_info "删除配置文件..."

    # 备份配置（可选）
    read -p "是否备份配置文件到 /tmp/xray-backup? (y/N): " backup

    if [ "$backup" = "y" ] || [ "$backup" = "Y" ]; then
        local backup_dir="/tmp/xray-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"

        if [ -d "/etc/xray" ]; then
            cp -r /etc/xray "$backup_dir/"
        fi

        if [ -d "/etc/cloudflared" ]; then
            cp -r /etc/cloudflared "$backup_dir/"
        fi

        log_info "配置已备份到: $backup_dir"
    fi

    # 删除配置目录
    if [ -d "/etc/xray" ]; then
        rm -rf /etc/xray
        log_info "已删除 Xray 配置目录"
    fi

    if [ -d "/etc/cloudflared" ]; then
        rm -rf /etc/cloudflared
        log_info "已删除 Cloudflare Tunnel 配置目录"
    fi

    if [ -d "$HOME/.cloudflared" ]; then
        rm -rf "$HOME/.cloudflared"
        log_info "已删除 Cloudflare 认证文件"
    fi
}

# 删除日志文件
remove_logs() {
    log_info "删除日志文件..."

    if [ -d "/var/log/xray" ]; then
        rm -rf /var/log/xray
        log_info "已删除 Xray 日志目录"
    fi
}

# 清理防火墙规则（如果有）
cleanup_firewall() {
    log_info "清理防火墙规则..."

    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "10809\|1080"; then
            log_warn "发现防火墙规则，请手动检查并清理"
            log_warn "运行: sudo ufw status numbered"
        fi
    fi
}

# 最终清理
final_cleanup() {
    log_info "执行最终清理..."

    # 清理临时文件
    rm -f /tmp/vmess-url.txt 2>/dev/null || true
    rm -f /tmp/xray-*.log 2>/dev/null || true

    log_info "清理完成"
}

# 生成卸载报告
generate_report() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "卸载完成！"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "已删除的内容："
    echo "  ✓ Xray 服务和二进制文件"
    echo "  ✓ Cloudflare Tunnel 服务和二进制文件"
    echo "  ✓ 所有配置文件"
    echo "  ✓ 所有日志文件"
    echo ""

    # 检查是否有残留
    local remnants=0

    if [ -f "/usr/local/bin/xray" ] || [ -d "/etc/xray" ]; then
        log_warn "发现 Xray 残留文件"
        remnants=1
    fi

    if [ -f "/usr/local/bin/cloudflared" ] || [ -d "/etc/cloudflared" ]; then
        log_warn "发现 Cloudflare Tunnel 残留文件"
        remnants=1
    fi

    if [ $remnants -eq 1 ]; then
        echo ""
        echo "请手动检查以下目录："
        echo "  /usr/local/bin/"
        echo "  /etc/xray/"
        echo "  /etc/cloudflared/"
        echo "  /var/log/xray/"
    else
        log_info "系统已完全清理"
    fi

    echo ""
    echo "注意事项："
    echo "  1. Cloudflare Tunnel 可能需要在控制台手动删除"
    echo "  2. DNS 记录需要在 Cloudflare 控制台手动删除"
    echo "  3. 如有备份文件，请妥善保管或删除"
    echo ""
}

# 主函数
main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║     Xray 代理服务卸载工具             ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        exit 1
    fi

    confirm_uninstall
    stop_services
    disable_services
    remove_service_files
    remove_cloudflare_tunnel
    remove_binaries
    remove_configs
    remove_logs
    cleanup_firewall
    final_cleanup
    generate_report
}

main "$@"
