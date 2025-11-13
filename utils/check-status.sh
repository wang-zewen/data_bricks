#!/bin/bash
#
# 状态检查脚本
# 用途：检查 Xray 和 Cloudflare Tunnel 的运行状态
#

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 状态图标
CHECK="✓"
CROSS="✗"
WARN="⚠"

log_success() {
    echo -e "${GREEN}${CHECK}${NC} $1"
}

log_error() {
    echo -e "${RED}${CROSS}${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}${WARN}${NC} $1"
}

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# 检查服务状态
check_service() {
    local service=$1
    local display_name=$2

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "检查 $display_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if systemctl is-active --quiet "$service"; then
        log_success "服务运行中"

        # 运行时间
        local uptime=$(systemctl show "$service" --property=ActiveEnterTimestamp --value)
        log_info "启动时间: $uptime"

        # 进程信息
        local pid=$(systemctl show "$service" --property=MainPID --value)
        if [ "$pid" != "0" ]; then
            log_info "进程 PID: $pid"

            # 内存使用
            local mem=$(ps -p "$pid" -o rss= 2>/dev/null || echo "0")
            mem_mb=$((mem / 1024))
            log_info "内存使用: ${mem_mb}MB"
        fi

        # 重启次数
        local restart_count=$(systemctl show "$service" --property=NRestarts --value)
        if [ "$restart_count" -gt 0 ]; then
            log_warn "重启次数: $restart_count"
        else
            log_success "重启次数: 0"
        fi
    else
        log_error "服务未运行"
        return 1
    fi
}

# 检查端口
check_port() {
    local port=$1
    local name=$2

    if nc -z 127.0.0.1 "$port" 2>/dev/null; then
        log_success "$name 端口 $port 可访问"
    else
        log_error "$name 端口 $port 不可访问"
        return 1
    fi
}

# 检查配置文件
check_config() {
    local file=$1
    local name=$2

    if [ -f "$file" ]; then
        log_success "$name 配置文件存在: $file"

        # 检查文件大小
        local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
        if [ "$size" -eq 0 ]; then
            log_error "配置文件为空"
            return 1
        fi
    else
        log_error "$name 配置文件不存在: $file"
        return 1
    fi
}

# 检查 Xray
check_xray() {
    check_service "xray" "Xray 服务"

    # 检查配置
    if check_config "/etc/xray/config.json" "Xray"; then
        # 验证配置语法
        if xray -test -config /etc/xray/config.json &>/dev/null; then
            log_success "配置文件语法正确"
        else
            log_error "配置文件语法错误"
        fi
    fi

    # 检查端口
    check_port 10809 "VMess"
    check_port 1080 "SOCKS5"

    # 检查日志
    if [ -f "/var/log/xray/error.log" ]; then
        local error_count=$(grep -c "error\|Error\|ERROR" /var/log/xray/error.log 2>/dev/null || echo "0")
        if [ "$error_count" -gt 0 ]; then
            log_warn "发现 $error_count 条错误日志"
            echo ""
            echo "最近的错误："
            tail -n 5 /var/log/xray/error.log
        else
            log_success "无错误日志"
        fi
    fi
}

# 检查 Cloudflare Tunnel
check_cloudflared() {
    check_service "cloudflared" "Cloudflare Tunnel 服务"

    # 检查配置
    check_config "/etc/cloudflared/config.yml" "Cloudflare Tunnel"

    # 检查隧道状态
    if command -v cloudflared &> /dev/null; then
        log_info "Cloudflared 版本: $(cloudflared --version | head -n 1)"

        # 列出隧道
        echo ""
        log_info "已配置的隧道:"
        cloudflared tunnel list 2>/dev/null | tail -n +2 || log_warn "无法获取隧道列表"
    fi

    # 检查域名
    if [ -f "/etc/cloudflared/tunnel-domain.txt" ]; then
        local domain=$(cat /etc/cloudflared/tunnel-domain.txt)
        log_info "配置域名: $domain"

        # DNS 解析检查
        if nslookup "$domain" &>/dev/null; then
            log_success "DNS 解析正常"
        else
            log_warn "DNS 解析可能有问题"
        fi
    fi
}

# 测试连接
test_connection() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "测试代理连接"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 测试 SOCKS5 代理
    if curl -s --max-time 10 --proxy socks5://127.0.0.1:1080 https://www.google.com &>/dev/null; then
        log_success "SOCKS5 代理测试成功"
    else
        log_error "SOCKS5 代理测试失败"
    fi

    # 测试延迟
    if command -v cloudflared &> /dev/null && [ -f "/etc/cloudflared/tunnel-domain.txt" ]; then
        local domain=$(cat /etc/cloudflared/tunnel-domain.txt)
        local start_time=$(date +%s%N)

        if curl -s --max-time 10 "https://$domain" &>/dev/null; then
            local end_time=$(date +%s%N)
            local latency=$(( (end_time - start_time) / 1000000 ))
            log_success "隧道延迟: ${latency}ms"
        else
            log_warn "隧道连接测试失败（可能是正常的）"
        fi
    fi
}

# 系统资源检查
check_resources() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "系统资源"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # CPU 负载
    if [ -f /proc/loadavg ]; then
        local load=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
        log_info "CPU 负载: $load"
    fi

    # 内存使用
    if command -v free &> /dev/null; then
        local mem=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
        log_info "内存使用: $mem"
    fi

    # 磁盘使用
    local disk=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
    log_info "磁盘使用: $disk"

    # 网络连接数
    local conn_count=$(netstat -an 2>/dev/null | grep -c ESTABLISHED || echo "0")
    log_info "活动连接数: $conn_count"
}

# 生成报告摘要
generate_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "状态摘要"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local xray_status="未知"
    local cf_status="未知"

    if systemctl is-active --quiet xray; then
        xray_status="运行中 ${CHECK}"
    else
        xray_status="已停止 ${CROSS}"
    fi

    if systemctl is-active --quiet cloudflared; then
        cf_status="运行中 ${CHECK}"
    else
        cf_status="已停止 ${CROSS}"
    fi

    echo ""
    echo "Xray:              $xray_status"
    echo "Cloudflare Tunnel: $cf_status"
    echo ""

    if systemctl is-active --quiet xray && systemctl is-active --quiet cloudflared; then
        log_success "所有服务运行正常！"
    else
        log_error "部分服务未运行"
        echo ""
        echo "修复建议："
        if ! systemctl is-active --quiet xray; then
            echo "  sudo systemctl start xray"
        fi
        if ! systemctl is-active --quiet cloudflared; then
            echo "  sudo systemctl start cloudflared"
        fi
    fi
}

# 主函数
main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║   Databricks Xray 代理状态检查工具    ║"
    echo "╚════════════════════════════════════════╝"

    check_xray
    check_cloudflared
    test_connection
    check_resources
    generate_summary

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "查看详细日志："
    echo "  Xray:       journalctl -u xray -f"
    echo "  Cloudflared: journalctl -u cloudflared -f"
    echo ""
    echo "配置信息："
    echo "  cat /etc/cloudflared/connection-info.txt"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

main "$@"
