#!/bin/bash
################################################################################
#
# Databricks Xray 代理部署脚本 - 节点架构优化版
#
# 专为Databricks集群设计，智能识别节点类型：
# - Driver节点：安装Xray代理服务
# - Worker节点：跳过安装或配置客户端
#
# 使用方法：
#   作为Cluster Init Script:
#     dbutils.fs.put("/databricks/init-scripts/xray.sh", script, True)
#     在集群配置 > Init Scripts 中添加路径
#
# 环境变量：
#   XRAY_NODE_MODE        - 安装模式: driver_only(默认) | all_nodes | manual
#   XRAY_UUID             - VMess UUID (留空自动生成)
#   XRAY_PORT             - VMess端口 (默认: 10809)
#   XRAY_SOCKS_PORT       - SOCKS5端口 (默认: 1080)
#   XRAY_BIND_ADDRESS     - 绑定地址 (默认: 0.0.0.0，允许集群内访问)
#   CF_TOKEN              - Cloudflare API Token (可选)
#   TUNNEL_DOMAIN         - 隧道域名 (可选)
#
################################################################################

set -e

################################################################################
# 配置
################################################################################

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 默认配置
XRAY_VERSION="${XRAY_VERSION:-latest}"
XRAY_INSTALL_DIR="${XRAY_INSTALL_DIR:-/usr/local/bin}"
XRAY_CONFIG_DIR="${XRAY_CONFIG_DIR:-/etc/xray}"
XRAY_LOG_DIR="${XRAY_LOG_DIR:-/var/log/xray}"
XRAY_PORT="${XRAY_PORT:-10809}"
XRAY_SOCKS_PORT="${XRAY_SOCKS_PORT:-1080}"
XRAY_BIND_ADDRESS="${XRAY_BIND_ADDRESS:-0.0.0.0}"  # 允许集群内其他节点访问
XRAY_UUID="${XRAY_UUID:-}"
LOG_LEVEL="${LOG_LEVEL:-warning}"

# 节点模式
XRAY_NODE_MODE="${XRAY_NODE_MODE:-driver_only}"  # driver_only | all_nodes | manual

# Cloudflare
CF_TOKEN="${CF_TOKEN:-}"
TUNNEL_DOMAIN="${TUNNEL_DOMAIN:-}"
TUNNEL_NAME="${TUNNEL_NAME:-databricks-xray}"

# 日志
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
# Databricks节点检测
################################################################################

detect_databricks_node() {
    log_step "检测Databricks节点类型..."

    # 方法1: 检查环境变量
    if [ -n "${DB_IS_DRIVER:-}" ]; then
        if [ "$DB_IS_DRIVER" = "TRUE" ]; then
            echo "driver"
            return 0
        else
            echo "worker"
            return 0
        fi
    fi

    # 方法2: 检查Spark配置
    if [ -f "/databricks/spark/conf/spark-env.sh" ]; then
        if grep -q "SPARK_MASTER" /databricks/spark/conf/spark-env.sh 2>/dev/null; then
            echo "driver"
            return 0
        fi
    fi

    # 方法3: 检查进程
    if pgrep -f "spark.*driver" > /dev/null 2>&1; then
        echo "driver"
        return 0
    elif pgrep -f "spark.*executor" > /dev/null 2>&1; then
        echo "worker"
        return 0
    fi

    # 方法4: 检查hostname
    if hostname | grep -iq "driver"; then
        echo "driver"
        return 0
    elif hostname | grep -iq "worker"; then
        echo "worker"
        return 0
    fi

    # 方法5: 检查Databricks特定路径
    if [ -f "/databricks/driver/conf/driver-env.sh" ]; then
        echo "driver"
        return 0
    fi

    # 默认假设为driver（安全选择）
    log_warn "无法确定节点类型，默认作为driver处理"
    echo "driver"
}

################################################################################
# 决定是否安装
################################################################################

should_install() {
    local node_type="$1"

    case "$XRAY_NODE_MODE" in
        driver_only)
            if [ "$node_type" = "driver" ]; then
                return 0
            else
                log_info "当前为Worker节点，driver_only模式下跳过安装"
                return 1
            fi
            ;;
        all_nodes)
            log_info "all_nodes模式，在所有节点安装"
            return 0
            ;;
        manual)
            log_info "manual模式，继续安装"
            return 0
            ;;
        *)
            log_error "未知的NODE_MODE: $XRAY_NODE_MODE"
            return 1
            ;;
    esac
}

################################################################################
# 主安装函数（简化版，从all-in-one提取核心功能）
################################################################################

install_dependencies() {
    log_step "安装依赖..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq 2>&1 | tee -a "$INSTALL_LOG"
    apt-get install -y -qq curl wget unzip jq netcat-openbsd 2>&1 | tee -a "$INSTALL_LOG"
}

detect_architecture() {
    case $(uname -m) in
        x86_64) echo "linux-64" ;;
        aarch64|arm64) echo "linux-arm64-v8a" ;;
        *) log_error "不支持的架构"; exit 1 ;;
    esac
}

generate_uuid() {
    if [ -z "$XRAY_UUID" ]; then
        XRAY_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "")
    fi
}

install_xray() {
    log_step "安装Xray..."

    if [ "$XRAY_VERSION" = "latest" ]; then
        XRAY_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name | sed 's/v//')
        [ -z "$XRAY_VERSION" ] && XRAY_VERSION="1.8.4"
    fi

    local arch=$(detect_architecture)
    local url="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-${arch}.zip"

    local tmp_dir=$(mktemp -d)
    cd "$tmp_dir"
    wget -q --timeout=30 "$url" -O xray.zip || { log_error "下载失败"; exit 1; }
    unzip -q xray.zip
    mkdir -p "$XRAY_INSTALL_DIR"
    install -m 755 xray "$XRAY_INSTALL_DIR/xray"
    cd - > /dev/null
    rm -rf "$tmp_dir"

    log_info "Xray安装成功: $(xray version | head -n 1)"
}

configure_xray() {
    log_step "配置Xray（集群优化）..."

    mkdir -p "$XRAY_CONFIG_DIR" "$XRAY_LOG_DIR"

    # 注意：绑定到0.0.0.0以允许集群内其他节点访问
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
      "listen": "$XRAY_BIND_ADDRESS",
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
      "listen": "$XRAY_BIND_ADDRESS",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

    xray -test -config "$XRAY_CONFIG_DIR/config.json" || { log_error "配置验证失败"; exit 1; }
    log_info "配置文件已生成并验证"
}

create_xray_service() {
    log_step "创建Xray服务..."

    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Proxy Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=$XRAY_INSTALL_DIR/xray run -config $XRAY_CONFIG_DIR/config.json
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray
    systemctl start xray

    sleep 3

    if systemctl is-active --quiet xray; then
        log_info "✓ Xray服务启动成功"
    else
        log_error "✗ Xray服务启动失败"
        systemctl status xray --no-pager
        exit 1
    fi
}

################################################################################
# 生成集群访问信息
################################################################################

generate_cluster_info() {
    log_step "生成集群访问信息..."

    # 获取Driver节点IP
    local driver_ip=$(hostname -I | awk '{print $1}')
    local internal_ip=$(hostname -i 2>/dev/null || echo "127.0.0.1")

    cat > "$XRAY_CONFIG_DIR/cluster-access-info.txt" <<EOF
╔══════════════════════════════════════════════════════════╗
║          Databricks 集群代理访问信息                    ║
╚══════════════════════════════════════════════════════════╝

安装时间: $(date)
节点类型: Driver
日志文件: $INSTALL_LOG

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
基本配置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

UUID:           $XRAY_UUID
VMess端口:      $XRAY_PORT
SOCKS5端口:     $XRAY_SOCKS_PORT
绑定地址:       $XRAY_BIND_ADDRESS

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
集群内访问（Notebook中使用）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Driver IP:      $driver_ip
Internal IP:    $internal_ip

Python代码示例（在任意Notebook中运行）:
───────────────────────────────────────────────────────────
import requests

# 配置代理
proxies = {
    'http': 'socks5://${driver_ip}:${XRAY_SOCKS_PORT}',
    'https': 'socks5://${driver_ip}:${XRAY_SOCKS_PORT}'
}

# 使用代理
response = requests.get('https://www.google.com', proxies=proxies)
print(response.status_code)
───────────────────────────────────────────────────────────

Spark配置（在集群配置中添加）:
───────────────────────────────────────────────────────────
spark.driver.extraJavaOptions -Dhttp.proxyHost=${driver_ip} -Dhttp.proxyPort=${XRAY_SOCKS_PORT}
───────────────────────────────────────────────────────────

Bash测试:
───────────────────────────────────────────────────────────
curl -x socks5://${driver_ip}:${XRAY_SOCKS_PORT} https://www.google.com
───────────────────────────────────────────────────────────

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
外部访问（通过Cloudflare Tunnel）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

    if [ -n "$TUNNEL_DOMAIN" ]; then
        cat >> "$XRAY_CONFIG_DIR/cluster-access-info.txt" <<EOF
状态: 已配置
域名: https://$TUNNEL_DOMAIN

客户端配置:
  服务器: $TUNNEL_DOMAIN
  端口: 443
  UUID: $XRAY_UUID
  TLS: 启用
EOF
    else
        cat >> "$XRAY_CONFIG_DIR/cluster-access-info.txt" <<EOF
状态: 未配置

配置Cloudflare Tunnel可实现外部访问。
详见: docs/CLOUDFLARE_TUNNEL_SETUP.md
EOF
    fi

    cat >> "$XRAY_CONFIG_DIR/cluster-access-info.txt" <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
服务管理
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

查看状态: systemctl status xray
重启服务: systemctl restart xray
查看日志: journalctl -u xray -f

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
注意事项
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. 代理服务运行在Driver节点上
2. 集群内所有节点和Notebook都可以访问
3. 如果集群重启，IP可能会改变
4. 建议使用Init Script确保服务自动启动
5. Worker节点访问Driver代理无需额外配置

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

    cat "$XRAY_CONFIG_DIR/cluster-access-info.txt"
    log_info "集群访问信息已保存到: $XRAY_CONFIG_DIR/cluster-access-info.txt"
}

################################################################################
# 主函数
################################################################################

main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║     Databricks Xray 代理 - 节点架构优化版               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_info "开始部署..."

    # 检查权限
    if [ "$EUID" -ne 0 ]; then
        log_error "需要root权限"
        exit 1
    fi

    # 检测节点类型
    NODE_TYPE=$(detect_databricks_node)
    log_info "节点类型: $NODE_TYPE"
    log_info "安装模式: $XRAY_NODE_MODE"

    # 决定是否安装
    if ! should_install "$NODE_TYPE"; then
        log_info "跳过安装"

        # 如果是worker，提供driver访问信息
        if [ "$NODE_TYPE" = "worker" ]; then
            echo ""
            log_info "作为Worker节点，可通过以下方式访问Driver上的代理:"
            log_info "1. 等待Driver节点安装完成"
            log_info "2. 使用 'socks5://<driver-ip>:1080' 作为代理地址"
            log_info "3. Driver IP可通过集群UI或日志查看"
        fi

        exit 0
    fi

    # 生成UUID
    generate_uuid
    log_info "UUID: ${XRAY_UUID:0:8}..."

    # 执行安装
    install_dependencies
    install_xray
    configure_xray
    create_xray_service

    # 生成信息
    generate_cluster_info

    # 完成
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                  🎉 部署完成！🎉                         ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_info "节点类型: $NODE_TYPE"
    log_info "服务状态: $(systemctl is-active xray)"
    log_info "访问信息: $XRAY_CONFIG_DIR/cluster-access-info.txt"
    echo ""

    # 在Databricks环境中保存信息
    if [ -n "${DB_HOME:-}" ]; then
        cp "$XRAY_CONFIG_DIR/cluster-access-info.txt" "$DB_HOME/xray-info.txt" 2>/dev/null || true
        log_info "信息已复制到: $DB_HOME/xray-info.txt"
    fi
}

# 执行
main "$@"
