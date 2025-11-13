# 🚀 Databricks Xray Node.js 部署指南（Bore Tunnel版）

使用 Node.js + Express + bore.pub，替代 Argo Tunnel

## 📦 文件说明

```
package.json  - Node.js 包配置（依赖：express, axios）
index.js      - 主程序（Express服务器 + Xray + bore.pub隧道）
```

## 🎯 核心特性

- ✅ **无需Argo** - 使用 bore.pub 免费隧道
- ✅ **Express服务器** - 提供HTTP服务和订阅接口
- ✅ **多协议支持** - VMess、VLESS、Trojan
- ✅ **自动订阅** - 自动生成订阅链接
- ✅ **三种隧道** - bore（默认）、ngrok、localtunnel

## 🚀 快速部署

### 方式一：在 Databricks 上部署（推荐）

#### 步骤1：上传文件

```python
# 在 Databricks Notebook 中执行

# 读取文件
package_json = open('package.json').read()
index_js = open('index.js').read()

# 上传到 DBFS
dbutils.fs.put("/databricks/scripts/package.json", package_json, True)
dbutils.fs.put("/databricks/scripts/index.js", index_js, True)

print("✓ 文件已上传")
```

#### 步骤2：安装 Node.js 和依赖

```bash
%sh
# 安装 Node.js（如果没有）
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# 验证安装
node --version
npm --version

# 复制文件到工作目录
mkdir -p /tmp/xray-app
cp /dbfs/databricks/scripts/package.json /tmp/xray-app/
cp /dbfs/databricks/scripts/index.js /tmp/xray-app/

# 安装依赖
cd /tmp/xray-app
npm install

echo "✓ 依赖安装完成"
```

#### 步骤3：配置环境变量

```python
# 在 Notebook 中设置
import os

os.environ['UUID'] = 'your-uuid-here'           # 必需
os.environ['TUNNEL_TYPE'] = 'bore'              # bore | ngrok | localtunnel
os.environ['NAME'] = 'MyNode'                   # 节点名称（可选）
os.environ['PORT'] = '3000'                     # HTTP服务端口
os.environ['XRAY_PORT'] = '8001'                # Xray端口
os.environ['SOCKS_PORT'] = '1080'               # SOCKS5端口

# 如果使用 ngrok
# os.environ['TUNNEL_TYPE'] = 'ngrok'
# os.environ['NGROK_TOKEN'] = 'your-ngrok-token'

print("✓ 环境变量已设置")
```

#### 步骤4：启动服务

```bash
%sh
cd /tmp/xray-app

# 后台启动
nohup node index.js > app.log 2>&1 &

echo "✓ 服务已启动"
sleep 10

# 查看日志
tail -50 app.log
```

#### 步骤5：获取订阅

```bash
%sh
# 查看订阅（Base64编码）
cat /tmp/xray-app/tmp/sub.txt

# 查看原始链接
cat /tmp/xray-app/tmp/sub.txt | base64 -d
```

---

### 方式二：本地测试

```bash
# 1. 安装依赖
npm install

# 2. 设置环境变量
export UUID="your-uuid-here"
export TUNNEL_TYPE="bore"

# 3. 启动
npm start

# 或
node index.js
```

---

## 📊 环境变量配置

| 变量名 | 必需 | 默认值 | 说明 |
|--------|------|--------|------|
| `UUID` | ✅ | 自动生成 | VMess/VLESS UUID |
| `TUNNEL_TYPE` | ❌ | bore | bore\|ngrok\|localtunnel |
| `NGROK_TOKEN` | ❌ | - | ngrok认证token（使用ngrok时必需） |
| `NAME` | ❌ | - | 节点名称前缀 |
| `PORT` | ❌ | 3000 | HTTP服务端口 |
| `XRAY_PORT` | ❌ | 8001 | Xray监听端口 |
| `SOCKS_PORT` | ❌ | 1080 | SOCKS5代理端口 |
| `CFIP` | ❌ | cdns.doon.eu.org | 优选域名/IP |
| `CFPORT` | ❌ | 443 | 优选端口 |
| `UPLOAD_URL` | ❌ | - | 节点上传地址 |
| `PROJECT_URL` | ❌ | - | 项目URL |
| `SUB_PATH` | ❌ | sub | 订阅路径 |

---

## 🌐 访问订阅

### 方法1：通过HTTP接口

```bash
# 访问订阅地址
curl http://localhost:3000/sub

# 或在浏览器中访问
http://<server-ip>:3000/sub
```

### 方法2：从文件读取

```bash
# 查看订阅内容
cat ./tmp/sub.txt | base64 -d
```

---

## 🔧 隧道类型对比

| 隧道 | 优点 | 缺点 | 配置 |
|------|------|------|------|
| **bore.pub** | 完全免费、无需注册、开源 | 随机域名、稳定性中等 | `TUNNEL_TYPE=bore` |
| **ngrok** | 最稳定、功能丰富、速度快 | 需要注册、免费版有限制 | `TUNNEL_TYPE=ngrok`<br>`NGROK_TOKEN=xxx` |
| **localtunnel** | 完全免费、易用 | 不太稳定、经常断连 | `TUNNEL_TYPE=localtunnel` |

### 切换隧道示例

```bash
# 使用 bore（默认）
export TUNNEL_TYPE=bore

# 使用 ngrok
export TUNNEL_TYPE=ngrok
export NGROK_TOKEN=your_token_here

# 使用 localtunnel（需要npx）
export TUNNEL_TYPE=localtunnel
```

---

## 📱 客户端配置

### 1. 获取订阅链接

```python
# 在 Notebook 中
%sh
cat /tmp/xray-app/tmp/sub.txt | base64 -d
```

会看到类似输出：
```
vless://uuid@cdns.doon.eu.org:443?...#NodeName
vmess://base64encoded...
trojan://uuid@cdns.doon.eu.org:443?...#NodeName
```

### 2. 导入客户端

**Clash**：
```yaml
proxies:
  - name: "Databricks-Node"
    type: vmess
    server: cdns.doon.eu.org
    port: 443
    uuid: your-uuid
    alterId: 0
    cipher: auto
    tls: true
    skip-cert-verify: false
    servername: bore.pub
    network: ws
    ws-opts:
      path: /vmess
      headers:
        Host: bore.pub:xxxxx
```

**V2RayN/V2RayNG**：
1. 复制 vmess:// 或 vless:// 链接
2. 在客户端中选择"从剪贴板导入"

**订阅方式**：
```
在客户端添加订阅URL：
http://<databricks-ip>:3000/sub
```

---

## 🔍 监控和调试

### 查看应用日志

```bash
%sh
tail -f /tmp/xray-app/app.log
```

### 查看隧道日志

```bash
%sh
tail -f /tmp/xray-app/tmp/tunnel.log
```

### 检查服务状态

```bash
%sh
# 检查进程
ps aux | grep -E 'node|xray|bore'

# 检查端口
netstat -tlnp | grep -E '3000|8001|1080'

# 测试HTTP服务
curl http://localhost:3000/

# 测试SOCKS5代理
curl -x socks5://localhost:1080 https://www.google.com
```

---

## 🐛 故障排查

### 问题1：bore连接失败

```bash
# 检查bore日志
tail -50 /tmp/xray-app/tmp/tunnel.log

# 手动启动bore测试
cd /tmp/xray-app/tmp
./bore local 8001 --to bore.pub
```

### 问题2：无法获取隧道域名

```bash
# 等待更长时间（bore需要几秒建立连接）
sleep 10
cat /tmp/xray-app/tmp/tunnel.log

# 重启bore进程
pkill bore
cd /tmp/xray-app
node index.js
```

### 问题3：Xray未启动

```bash
# 检查Xray配置
/tmp/xray-app/tmp/xray -test -config /tmp/xray-app/tmp/config.json

# 手动启动Xray
cd /tmp/xray-app/tmp
./xray -config config.json
```

### 问题4：依赖安装失败

```bash
# 清理并重新安装
cd /tmp/xray-app
rm -rf node_modules package-lock.json
npm cache clean --force
npm install
```

---

## 💡 在 Notebook 中使用代理

```python
# 使用SOCKS5代理访问外网
import requests

driver_ip = spark.conf.get("spark.driver.host")

proxies = {
    'http': f'socks5://{driver_ip}:1080',
    'https': f'socks5://{driver_ip}:1080'
}

# 测试连接
response = requests.get('https://www.google.com', proxies=proxies)
print(f"✓ 状态码: {response.status_code}")
```

---

## 🔄 自动启动（Init Script）

### 创建启动脚本

```bash
#!/bin/bash
# /databricks/init-scripts/start-xray.sh

# 安装Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# 准备应用
mkdir -p /tmp/xray-app
cp /dbfs/databricks/scripts/package.json /tmp/xray-app/
cp /dbfs/databricks/scripts/index.js /tmp/xray-app/
cd /tmp/xray-app

# 安装依赖
npm install

# 启动应用
nohup node index.js > app.log 2>&1 &

echo "Xray proxy started"
```

### 配置Init Script

```python
# 上传启动脚本
script = open('start-xray.sh').read()
dbutils.fs.put("/databricks/init-scripts/start-xray.sh", script, True)

# 在集群配置中添加：
# Advanced Options > Init Scripts
# Path: dbfs:/databricks/init-scripts/start-xray.sh
```

---

## 📊 完整部署示例

```python
# Databricks Notebook - 完整部署示例

# COMMAND ----------
# 步骤1：上传文件
package_json = open('package.json').read()
index_js = open('index.js').read()

dbutils.fs.put("/databricks/scripts/package.json", package_json, True)
dbutils.fs.put("/databricks/scripts/index.js", index_js, True)

# COMMAND ----------
# 步骤2：设置环境并安装
%sh
# 安装Node.js
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# 准备目录
mkdir -p /tmp/xray-app
cp /dbfs/databricks/scripts/* /tmp/xray-app/
cd /tmp/xray-app
npm install

# COMMAND ----------
# 步骤3：配置环境变量
import os
os.environ['UUID'] = 'your-uuid-here'
os.environ['TUNNEL_TYPE'] = 'bore'
os.environ['NAME'] = 'MyNode'

# COMMAND ----------
# 步骤4：启动服务
%sh
cd /tmp/xray-app
nohup node index.js > app.log 2>&1 &
sleep 15
echo "Service started!"

# COMMAND ----------
# 步骤5：查看订阅
%sh
cat /tmp/xray-app/tmp/sub.txt | base64 -d

# COMMAND ----------
# 步骤6：测试代理
import requests

driver_ip = spark.conf.get("spark.driver.host")
proxies = {
    'http': f'socks5://{driver_ip}:1080',
    'https': f'socks5://{driver_ip}:1080'
}

response = requests.get('https://www.google.com', proxies=proxies, timeout=10)
print(f"✓ 代理测试成功！状态码: {response.status_code}")
```

---

## 🔗 相关资源

- **bore.pub**: https://github.com/ekzhang/bore
- **ngrok**: https://ngrok.com/
- **Xray**: https://github.com/XTLS/Xray-core
- **Express**: https://expressjs.com/

---

## 📝 注意事项

1. **Node.js版本**: 需要Node.js 14+
2. **依赖**: axios 和 express 会自动安装
3. **端口**: 确保端口未被占用
4. **权限**: 某些操作可能需要sudo
5. **Databricks限制**: 注意网络策略和资源限制

---

**最后更新**: 2025-01-13

**提示**: 如果bore.pub不稳定，建议切换到ngrok（需要注册获取token）。
