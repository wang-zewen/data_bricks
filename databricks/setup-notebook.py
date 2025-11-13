# Databricks notebook source
# MAGIC %md
# MAGIC # Xray 代理部署 - Databricks Notebook
# MAGIC
# MAGIC 这个 Notebook 用于在 Databricks 集群上部署和管理 Xray 代理服务
# MAGIC
# MAGIC ## 前置要求
# MAGIC - Databricks Runtime 7.0+
# MAGIC - 集群权限：能够执行 bash 命令
# MAGIC - Cloudflare 账户和 API Token

# COMMAND ----------

# MAGIC %md
# MAGIC ## 步骤 1: 配置环境变量

# COMMAND ----------

# 配置参数
import os

# Cloudflare 配置
CF_TOKEN = ""  # 在这里填入您的 Cloudflare API Token
TUNNEL_DOMAIN = "proxy.yourdomain.com"  # 您的域名

# Xray 配置（可选）
XRAY_UUID = ""  # 留空自动生成
XRAY_PORT = 10809
XRAY_SOCKS_PORT = 1080

# 设置环境变量
os.environ['CF_TOKEN'] = CF_TOKEN
os.environ['TUNNEL_DOMAIN'] = TUNNEL_DOMAIN
if XRAY_UUID:
    os.environ['XRAY_UUID'] = XRAY_UUID
os.environ['XRAY_PORT'] = str(XRAY_PORT)
os.environ['XRAY_SOCKS_PORT'] = str(XRAY_SOCKS_PORT)

print("✓ 环境变量配置完成")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 步骤 2: 上传安装脚本到 DBFS

# COMMAND ----------

# 安装脚本 URL（从 GitHub 或其他源获取）
INSTALL_SCRIPT_URL = "https://raw.githubusercontent.com/yourusername/databricks-xray-proxy/main/install-xray-proxy.sh"
CLOUDFLARE_SCRIPT_URL = "https://raw.githubusercontent.com/yourusername/databricks-xray-proxy/main/setup-cloudflared.sh"

# 下载脚本
import urllib.request

def download_script(url, local_path):
    try:
        with urllib.request.urlopen(url) as response:
            content = response.read().decode('utf-8')
            dbutils.fs.put(local_path, content, overwrite=True)
            print(f"✓ 已下载: {local_path}")
            return True
    except Exception as e:
        print(f"✗ 下载失败: {e}")
        return False

# 下载到 DBFS
download_script(INSTALL_SCRIPT_URL, "/dbfs/tmp/install-xray-proxy.sh")
download_script(CLOUDFLARE_SCRIPT_URL, "/dbfs/tmp/setup-cloudflared.sh")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 步骤 3: 执行安装脚本

# COMMAND ----------

# MAGIC %sh
# MAGIC # 安装 Xray
# MAGIC chmod +x /dbfs/tmp/install-xray-proxy.sh
# MAGIC sudo /dbfs/tmp/install-xray-proxy.sh

# COMMAND ----------

# MAGIC %md
# MAGIC ## 步骤 4: 配置 Cloudflare Tunnel

# COMMAND ----------

# MAGIC %sh
# MAGIC # 配置 Cloudflare Tunnel
# MAGIC chmod +x /dbfs/tmp/setup-cloudflared.sh
# MAGIC echo "$TUNNEL_DOMAIN" | sudo /dbfs/tmp/setup-cloudflared.sh

# COMMAND ----------

# MAGIC %md
# MAGIC ## 步骤 5: 验证服务状态

# COMMAND ----------

# MAGIC %sh
# MAGIC # 检查 Xray 服务
# MAGIC echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# MAGIC echo "Xray 服务状态:"
# MAGIC echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# MAGIC sudo systemctl status xray --no-pager
# MAGIC
# MAGIC echo ""
# MAGIC echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# MAGIC echo "Cloudflare Tunnel 状态:"
# MAGIC echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# MAGIC sudo systemctl status cloudflared --no-pager

# COMMAND ----------

# MAGIC %md
# MAGIC ## 步骤 6: 获取连接信息

# COMMAND ----------

# MAGIC %sh
# MAGIC # 显示连接信息
# MAGIC cat /etc/cloudflared/connection-info.txt

# COMMAND ----------

# 生成 VMess URL
def generate_vmess_url():
    import json
    import base64

    # 读取配置
    with open('/etc/xray/config.json', 'r') as f:
        config = json.load(f)

    uuid = config['inbounds'][0]['settings']['clients'][0]['id']

    vmess_config = {
        "v": "2",
        "ps": "Databricks-Xray-Proxy",
        "add": TUNNEL_DOMAIN,
        "port": "443",
        "id": uuid,
        "aid": "0",
        "net": "tcp",
        "type": "none",
        "host": "",
        "path": "",
        "tls": "tls",
        "sni": TUNNEL_DOMAIN
    }

    json_str = json.dumps(vmess_config)
    vmess_url = "vmess://" + base64.b64encode(json_str.encode()).decode()

    return vmess_url, uuid

try:
    vmess_url, uuid = generate_vmess_url()
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("连接信息")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"\n域名: {TUNNEL_DOMAIN}")
    print(f"UUID: {uuid}")
    print(f"端口: 443")
    print(f"\nVMess URL:")
    print(vmess_url)
    print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
except Exception as e:
    print(f"生成 VMess URL 失败: {e}")
    print("请手动查看配置文件: /etc/xray/config.json")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 步骤 7: 测试代理

# COMMAND ----------

# MAGIC %sh
# MAGIC # 测试本地 SOCKS5 代理
# MAGIC echo "测试 SOCKS5 代理..."
# MAGIC curl -x socks5://127.0.0.1:1080 https://www.google.com -I -s | head -n 1

# COMMAND ----------

# 使用 Python 测试代理
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

def test_proxy():
    proxies = {
        'http': f'socks5://127.0.0.1:{XRAY_SOCKS_PORT}',
        'https': f'socks5://127.0.0.1:{XRAY_SOCKS_PORT}'
    }

    try:
        response = requests.get('https://www.google.com',
                              proxies=proxies,
                              timeout=10)
        if response.status_code == 200:
            print("✓ 代理测试成功！")
            return True
        else:
            print(f"✗ 代理测试失败: HTTP {response.status_code}")
            return False
    except Exception as e:
        print(f"✗ 代理测试失败: {e}")
        return False

test_proxy()

# COMMAND ----------

# MAGIC %md
# MAGIC ## 管理命令

# COMMAND ----------

# MAGIC %md
# MAGIC ### 重启服务

# COMMAND ----------

# MAGIC %sh
# MAGIC # 重启 Xray
# MAGIC sudo systemctl restart xray
# MAGIC
# MAGIC # 重启 Cloudflare Tunnel
# MAGIC sudo systemctl restart cloudflared

# COMMAND ----------

# MAGIC %md
# MAGIC ### 查看日志

# COMMAND ----------

# MAGIC %sh
# MAGIC # 查看 Xray 日志
# MAGIC echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# MAGIC echo "Xray 最近日志:"
# MAGIC echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# MAGIC sudo journalctl -u xray -n 20 --no-pager
# MAGIC
# MAGIC echo ""
# MAGIC echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# MAGIC echo "Cloudflare Tunnel 最近日志:"
# MAGIC echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# MAGIC sudo journalctl -u cloudflared -n 20 --no-pager

# COMMAND ----------

# MAGIC %md
# MAGIC ### 停止服务

# COMMAND ----------

# MAGIC %sh
# MAGIC # 停止服务（仅在需要时执行）
# MAGIC # sudo systemctl stop xray
# MAGIC # sudo systemctl stop cloudflared

# COMMAND ----------

# MAGIC %md
# MAGIC ## 注意事项
# MAGIC
# MAGIC 1. **集群重启**: 当集群重启时，服务会自动启动（如果配置了 init script）
# MAGIC 2. **安全性**: 请妥善保管您的 UUID 和 Cloudflare Token
# MAGIC 3. **监控**: 定期检查服务状态和日志
# MAGIC 4. **成本**: 注意 Databricks 集群的运行成本和网络流量费用
# MAGIC 5. **合规性**: 确保使用符合您组织的安全政策

# COMMAND ----------

# MAGIC %md
# MAGIC ## 卸载
# MAGIC
# MAGIC 如需卸载，执行以下命令：

# COMMAND ----------

# MAGIC %sh
# MAGIC # 卸载脚本（谨慎执行）
# MAGIC # sudo systemctl stop xray cloudflared
# MAGIC # sudo systemctl disable xray cloudflared
# MAGIC # sudo rm -rf /etc/xray /etc/cloudflared /var/log/xray
# MAGIC # sudo rm -f /usr/local/bin/xray /usr/local/bin/cloudflared
# MAGIC # sudo rm -f /etc/systemd/system/xray.service /etc/systemd/system/cloudflared.service
# MAGIC # sudo systemctl daemon-reload
# MAGIC # echo "✓ 卸载完成"
