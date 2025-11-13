# Databricks 单文件部署指南

这是最简单的Databricks部署方式，只需要一个脚本文件即可完成所有配置。

## 📄 单文件部署

使用 `databricks-xray-allinone.sh` 这个all-in-one脚本，包含了所有必要的功能。

## 🚀 快速开始

### 方式一：通过Databricks Notebook部署（推荐）

#### 步骤1：上传脚本到DBFS

在Databricks Notebook中运行：

```python
# 读取脚本内容
with open('databricks-xray-allinone.sh', 'r') as f:
    script_content = f.read()

# 上传到DBFS
dbutils.fs.put(
    "/databricks/init-scripts/xray-proxy.sh",
    script_content,
    overwrite=True
)

print("✓ 脚本已上传到 DBFS")
```

#### 步骤2：配置集群环境变量

在集群配置中添加环境变量：

```
Cluster Configuration → Advanced Options → Environment Variables
```

必需配置：
```bash
# 无需配置，UUID会自动生成
```

可选配置（如需Cloudflare Tunnel）：
```bash
CF_TOKEN=your_cloudflare_api_token_here
TUNNEL_DOMAIN=proxy.yourdomain.com
```

#### 步骤3：添加Init Script

在集群配置中添加：

```
Cluster Configuration → Advanced Options → Init Scripts

Init Script Path:
dbfs:/databricks/init-scripts/xray-proxy.sh
```

#### 步骤4：启动集群

保存配置并启动/重启集群，脚本会自动执行。

#### 步骤5：获取连接信息

集群启动后，在Notebook中运行：

```python
# 查看连接信息
print(dbutils.fs.head("/etc/xray/connection-info.txt"))
```

或通过SSH连接到集群：

```bash
cat /etc/xray/connection-info.txt
```

---

### 方式二：直接在Notebook中执行

如果不想使用Init Script，可以直接在Notebook中执行：

```python
# Cell 1: 上传脚本
script_content = """
<粘贴 databricks-xray-allinone.sh 的完整内容>
"""

dbutils.fs.put("/tmp/xray-install.sh", script_content, overwrite=True)

# Cell 2: 设置环境变量并执行
%sh
export XRAY_UUID="your-custom-uuid-optional"
export CF_TOKEN="your-cloudflare-token-optional"
export TUNNEL_DOMAIN="proxy.yourdomain.com-optional"

chmod +x /dbfs/tmp/xray-install.sh
sudo /dbfs/tmp/xray-install.sh
```

---

### 方式三：本地执行后上传到Databricks

#### 1. 本地准备脚本

```bash
# 下载脚本
wget https://raw.githubusercontent.com/yourusername/databricks-xray-proxy/main/databricks-xray-allinone.sh

# 或使用git clone
git clone <repo-url>
cd data_bricks
```

#### 2. 上传到Databricks

```python
# 在Databricks Notebook中
import requests

# 方式A: 从本地上传
with open('/path/to/databricks-xray-allinone.sh', 'r') as f:
    script = f.read()

# 方式B: 从GitHub直接下载
url = "https://raw.githubusercontent.com/yourusername/databricks-xray-proxy/main/databricks-xray-allinone.sh"
script = requests.get(url).text

# 保存到DBFS
dbutils.fs.put("/databricks/init-scripts/xray-proxy.sh", script, overwrite=True)
```

#### 3. 按方式一的步骤配置集群

---

## ⚙️ 环境变量配置说明

| 变量名 | 必需 | 默认值 | 说明 |
|--------|------|--------|------|
| `XRAY_UUID` | 否 | 自动生成 | VMess UUID，建议留空自动生成 |
| `XRAY_PORT` | 否 | 10809 | VMess监听端口 |
| `XRAY_SOCKS_PORT` | 否 | 1080 | SOCKS5监听端口 |
| `CF_TOKEN` | 否 | - | Cloudflare API Token |
| `TUNNEL_DOMAIN` | 否 | - | 隧道域名 |
| `TUNNEL_NAME` | 否 | databricks-xray | 隧道名称 |
| `SKIP_CLOUDFLARE` | 否 | no | 跳过Cloudflare配置（yes/no） |
| `LOG_LEVEL` | 否 | warning | 日志级别 |

---

## 📋 完整示例：Notebook代码

创建一个新的Databricks Notebook，复制以下代码：

```python
# Databricks notebook source
# MAGIC %md
# MAGIC # Xray 代理一键部署
# MAGIC
# MAGIC 使用单文件脚本快速部署Xray代理服务

# COMMAND ----------

# MAGIC %md
# MAGIC ## 步骤1：上传脚本

# COMMAND ----------

# 从GitHub下载最新脚本
import requests

script_url = "https://raw.githubusercontent.com/yourusername/databricks-xray-proxy/main/databricks-xray-allinone.sh"
script_content = requests.get(script_url).text

# 上传到DBFS
dbutils.fs.put(
    "/databricks/init-scripts/xray-proxy.sh",
    script_content,
    overwrite=True
)

print("✓ 脚本已上传")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 步骤2：直接执行（不使用Init Script）

# COMMAND ----------

%sh
# 赋予执行权限
chmod +x /dbfs/databricks/init-scripts/xray-proxy.sh

# 执行安装
sudo /dbfs/databricks/init-scripts/xray-proxy.sh

# COMMAND ----------

# MAGIC %md
# MAGIC ## 步骤3：查看连接信息

# COMMAND ----------

%sh
cat /etc/xray/connection-info.txt

# COMMAND ----------

# MAGIC %md
# MAGIC ## 步骤4：测试代理

# COMMAND ----------

import requests

# 配置代理
proxies = {
    'http': 'socks5://127.0.0.1:1080',
    'https': 'socks5://127.0.0.1:1080'
}

# 测试连接
try:
    response = requests.get('https://www.google.com', proxies=proxies, timeout=10)
    print(f"✓ 代理测试成功！状态码: {response.status_code}")
except Exception as e:
    print(f"✗ 代理测试失败: {e}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 步骤5：获取VMess配置

# COMMAND ----------

import json
import base64

# 读取配置
with open('/etc/xray/vmess-config.json', 'r') as f:
    vmess_config = json.load(f)

# 生成VMess URL
vmess_json = json.dumps(vmess_config)
vmess_url = "vmess://" + base64.b64encode(vmess_json.encode()).decode()

print("VMess URL:")
print(vmess_url)
print("\n将此URL导入到V2RayN、V2RayNG等客户端")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 管理命令

# COMMAND ----------

# 查看服务状态
%sh
systemctl status xray --no-pager

# COMMAND ----------

# 查看日志
%sh
tail -n 50 /var/log/xray/access.log

# COMMAND ----------

# 重启服务
%sh
sudo systemctl restart xray

# COMMAND ----------

# MAGIC %md
# MAGIC ## 卸载（如需要）

# COMMAND ----------

# 谨慎执行！这会完全删除Xray
%sh
sudo systemctl stop xray
sudo systemctl disable xray
sudo rm -rf /etc/xray /var/log/xray /usr/local/bin/xray
sudo rm -f /etc/systemd/system/xray.service
sudo systemctl daemon-reload
echo "✓ 已卸载"
```

---

## 🔍 验证部署

### 检查服务状态

```bash
# SSH到集群后执行
systemctl status xray
```

### 查看日志

```bash
# 查看实时日志
journalctl -u xray -f

# 查看访问日志
tail -f /var/log/xray/access.log
```

### 测试本地连接

```bash
# 测试SOCKS5代理
curl -x socks5://127.0.0.1:1080 https://www.google.com

# 查看端口
netstat -tlnp | grep -E '10809|1080'
```

---

## 📱 客户端配置

### 获取UUID

```bash
grep '"id"' /etc/xray/config.json
```

或

```python
import json
with open('/etc/xray/config.json') as f:
    config = json.load(f)
uuid = config['inbounds'][0]['settings']['clients'][0]['id']
print(f"UUID: {uuid}")
```

### Clash配置示例

```yaml
proxies:
  - name: "Databricks-Proxy"
    type: vmess
    server: proxy.yourdomain.com  # 替换为您的域名
    port: 443
    uuid: <从上面获取的UUID>
    alterId: 0
    cipher: auto
    tls: true
    network: tcp
```

### V2RayN配置

1. 打开V2RayN
2. 服务器 → 添加VMess服务器
3. 填入信息：
   - 地址：proxy.yourdomain.com
   - 端口：443
   - 用户ID：<UUID>
   - 额外ID：0
   - 加密方式：auto
   - 传输协议：tcp
   - 启用TLS：是

---

## ⚠️ 常见问题

### Q1: 脚本执行失败？

**检查日志：**
```bash
cat /tmp/xray-install-*.log
```

### Q2: 集群重启后服务未运行？

**确认使用了Init Script**，而不是直接在Notebook中执行。

### Q3: 如何更新UUID？

```bash
# 生成新UUID
NEW_UUID=$(cat /proc/sys/kernel/random/uuid)

# 更新配置
sudo sed -i "s/\"id\": \".*\"/\"id\": \"$NEW_UUID\"/" /etc/xray/config.json

# 重启服务
sudo systemctl restart xray

# 查看新配置
cat /etc/xray/connection-info.txt
```

### Q4: 如何配置Cloudflare Tunnel？

如果安装时没有配置Cloudflare Token，可以重新运行：

```bash
export CF_TOKEN="your-token"
export TUNNEL_DOMAIN="proxy.yourdomain.com"
sudo /dbfs/databricks/init-scripts/xray-proxy.sh
```

或手动配置：

```bash
# 安装cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared

# 登录
cloudflared tunnel login

# 创建隧道
cloudflared tunnel create databricks-xray

# 配置DNS
cloudflared tunnel route dns databricks-xray proxy.yourdomain.com
```

---

## 🔗 相关资源

- [完整文档](README.md)
- [FAQ](docs/FAQ.md)
- [客户端配置](client-configs/README.md)
- [Xray官方文档](https://xtls.github.io/)
- [Cloudflare Tunnel文档](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps)

---

## 📞 获取帮助

如有问题：

1. 查看安装日志：`/tmp/xray-install-*.log`
2. 查看服务日志：`journalctl -u xray -n 100`
3. 查看FAQ：`docs/FAQ.md`
4. 提交Issue：GitHub Issues

---

**最后更新**: 2025-01-13
