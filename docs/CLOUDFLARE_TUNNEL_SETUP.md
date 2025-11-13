# Cloudflare Tunnel 完整配置指南

本文档详细说明如何在Cloudflare中配置Tunnel，将Databricks上的Xray代理服务暴露到公网。

## 📋 目录

- [前置要求](#前置要求)
- [方式一：通过Cloudflare Dashboard配置（推荐新手）](#方式一通过cloudflare-dashboard配置推荐新手)
- [方式二：通过命令行配置（推荐高级用户）](#方式二通过命令行配置推荐高级用户)
- [方式三：在Databricks中配置](#方式三在databricks中配置)
- [验证和测试](#验证和测试)
- [故障排查](#故障排查)

---

## 前置要求

### 1. Cloudflare账户
- 注册地址：https://dash.cloudflare.com/sign-up
- 免费账户即可

### 2. 域名
- 域名必须在Cloudflare上托管
- 如果域名在其他DNS服务商（如阿里云、GoDaddy等）：
  1. 登录Cloudflare Dashboard
  2. 点击 "Add a Site"
  3. 输入域名
  4. 按照指引修改域名的NS记录指向Cloudflare

### 3. Xray已安装
- 确保Xray服务已在Databricks上运行
- 验证：`systemctl status xray`

---

## 方式一：通过Cloudflare Dashboard配置（推荐新手）

这是最简单的方式，全程图形化操作。

### 步骤1：登录Cloudflare Zero Trust

1. 访问 https://one.dash.cloudflare.com/
2. 首次使用需要设置Team Name（随意设置，如：your-team）
3. 选择免费计划（Free Plan）

### 步骤2：创建Tunnel

1. 在左侧菜单中选择：**Access** → **Tunnels**

   或直接访问：https://one.dash.cloudflare.com/[your-account-id]/access/tunnels

2. 点击右上角 **"Create a tunnel"** 按钮

3. 选择tunnel类型：**Cloudflared**

4. 输入tunnel名称：
   ```
   databricks-xray-proxy
   ```
   或其他你喜欢的名称

5. 点击 **"Save tunnel"**

### 步骤3：安装Connector（在Databricks中）

创建tunnel后，Cloudflare会显示安装命令。

**重要：不要使用它显示的命令！** 我们有更好的方式。

1. 记下页面上显示的 **Tunnel Token**（一长串字符）
   ```
   类似：eyJhIjoixxxxxx...很长的字符串
   ```

2. 或者下载凭证文件（.json格式）

3. 在Databricks中执行以下命令：

#### 方式A：使用Token（推荐）

```bash
# 在Databricks Notebook中执行
%sh
# 设置token
export TUNNEL_TOKEN="eyJhIjoixxxxxx..."  # 替换为你的token

# 安装cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared

# 运行tunnel（使用token方式）
sudo cloudflared tunnel run --token $TUNNEL_TOKEN
```

#### 方式B：使用凭证文件

```bash
# 在Databricks Notebook中
%sh
# 创建配置目录
sudo mkdir -p /etc/cloudflared

# 上传凭证文件（在Databricks中）
# 假设你已经把凭证文件上传到DBFS
sudo cp /dbfs/path/to/your-tunnel-credentials.json /etc/cloudflared/

# 创建配置文件
sudo tee /etc/cloudflared/config.yml > /dev/null <<EOF
tunnel: databricks-xray-proxy
credentials-file: /etc/cloudflared/your-tunnel-credentials.json

ingress:
  - service: http://localhost:10809
  - service: http_status:404
EOF

# 运行tunnel
sudo cloudflared tunnel run databricks-xray-proxy
```

### 步骤4：配置Public Hostname（重要！）

回到Cloudflare Dashboard，在tunnel配置页面：

1. 找到 **"Public Hostname"** 标签页

2. 点击 **"Add a public hostname"**

3. 填写配置：
   ```
   Subdomain:  proxy              # 子域名（自定义）
   Domain:     yourdomain.com     # 选择你的域名
   Path:       （留空）

   Service:
     Type:     HTTP
     URL:      localhost:10809    # Xray的VMess端口
   ```

4. 高级设置（可选，点击 "Additional application settings"）：
   ```
   HTTP Settings:
     ☑ No TLS Verify (如果使用HTTP)
     ☑ HTTP/2 Connection

   Connection Timeout: 30s
   ```

5. 点击 **"Save hostname"**

完成后，你的代理将通过以下地址访问：
```
https://proxy.yourdomain.com
```

### 步骤5：创建systemd服务（保持运行）

```bash
# 在Databricks中执行
%sh
# 创建服务文件
sudo tee /etc/systemd/system/cloudflared.service > /dev/null <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel run --token YOUR_TUNNEL_TOKEN
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

# 记得替换 YOUR_TUNNEL_TOKEN！

# 启动服务
sudo systemctl daemon-reload
sudo systemctl enable cloudflared
sudo systemctl start cloudflared

# 检查状态
sudo systemctl status cloudflared
```

---

## 方式二：通过命令行配置（推荐高级用户）

完全通过命令行操作，适合自动化部署。

### 步骤1：获取API Token

1. 访问：https://dash.cloudflare.com/profile/api-tokens

2. 点击 **"Create Token"**

3. 选择模板：**"Create Additional Tokens"**

4. 使用自定义Token，设置以下权限：
   ```
   Account - Cloudflare Tunnel - Edit
   Zone - DNS - Edit
   ```

5. 可选：限制到特定Zone（你的域名）

6. 点击 **"Continue to summary"** → **"Create Token"**

7. **复制并保存Token**（只显示一次！）
   ```
   示例：xxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```

### 步骤2：在Databricks中配置

在Databricks Notebook中执行：

```python
# Cell 1: 设置环境变量
import os

# 设置Cloudflare Token
os.environ['CLOUDFLARE_API_TOKEN'] = 'your-api-token-here'
os.environ['TUNNEL_NAME'] = 'databricks-xray-proxy'
os.environ['TUNNEL_DOMAIN'] = 'proxy.yourdomain.com'

print("✓ 环境变量已设置")
```

```bash
# Cell 2: 安装和配置cloudflared
%sh
# 安装cloudflared
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
sudo mv cloudflared-linux-amd64 /usr/local/bin/cloudflared
sudo chmod +x /usr/local/bin/cloudflared

echo "✓ cloudflared已安装: $(cloudflared --version)"
```

```bash
# Cell 3: 登录Cloudflare
%sh
# 使用API Token登录
cloudflared tunnel login --api-token $CLOUDFLARE_API_TOKEN

# 或者使用交互式登录
# cloudflared tunnel login
# （会生成一个URL，在浏览器中打开并授权）
```

```bash
# Cell 4: 创建tunnel
%sh
# 创建tunnel
cloudflared tunnel create $TUNNEL_NAME

# 查看创建的tunnel
cloudflared tunnel list

# 记录Tunnel ID（后续需要用）
TUNNEL_ID=$(cloudflared tunnel list | grep $TUNNEL_NAME | awk '{print $1}')
echo "Tunnel ID: $TUNNEL_ID"
```

```bash
# Cell 5: 配置DNS
%sh
# 将域名路由到tunnel
cloudflared tunnel route dns $TUNNEL_NAME $TUNNEL_DOMAIN

echo "✓ DNS配置完成: $TUNNEL_DOMAIN"
```

```bash
# Cell 6: 创建配置文件
%sh
# 获取Tunnel ID
TUNNEL_ID=$(cloudflared tunnel list | grep $TUNNEL_NAME | awk '{print $1}')

# 创建配置目录
sudo mkdir -p /etc/cloudflared

# 创建配置文件
sudo tee /etc/cloudflared/config.yml > /dev/null <<EOF
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json

ingress:
  - hostname: $TUNNEL_DOMAIN
    service: http://localhost:10809
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
  - service: http_status:404

loglevel: info
EOF

echo "✓ 配置文件已创建"
cat /etc/cloudflared/config.yml
```

```bash
# Cell 7: 创建systemd服务
%sh
# 复制凭证文件
TUNNEL_ID=$(cloudflared tunnel list | grep $TUNNEL_NAME | awk '{print $1}')
sudo cp /root/.cloudflared/$TUNNEL_ID.json /etc/cloudflared/

# 创建服务文件
sudo tee /etc/systemd/system/cloudflared.service > /dev/null <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
sudo systemctl daemon-reload
sudo systemctl enable cloudflared
sudo systemctl start cloudflared

echo "✓ cloudflared服务已启动"
```

```bash
# Cell 8: 验证状态
%sh
# 检查服务状态
sudo systemctl status cloudflared --no-pager

# 查看tunnel信息
cloudflared tunnel info $TUNNEL_NAME

# 检查连接
sleep 5
curl -I https://$TUNNEL_DOMAIN
```

---

## 方式三：在Databricks中配置

### 使用all-in-one脚本（最简单）

```python
# 在Databricks Notebook中
import os

# 设置环境变量
os.environ['CF_TOKEN'] = 'your-cloudflare-api-token'
os.environ['TUNNEL_DOMAIN'] = 'proxy.yourdomain.com'

# 上传并执行脚本
script = open('databricks-xray-allinone.sh').read()
dbutils.fs.put('/tmp/xray-install.sh', script, True)
```

```bash
%sh
chmod +x /dbfs/tmp/xray-install.sh
sudo /dbfs/tmp/xray-install.sh
```

脚本会自动：
1. 安装Xray
2. 安装cloudflared
3. 配置tunnel（需要手动完成认证步骤）

---

## 验证和测试

### 1. 检查Tunnel状态

```bash
# 查看tunnel列表
cloudflared tunnel list

# 查看特定tunnel信息
cloudflared tunnel info databricks-xray-proxy

# 查看服务状态
sudo systemctl status cloudflared
```

### 2. 检查DNS解析

```bash
# 检查DNS记录
nslookup proxy.yourdomain.com

# 或使用dig
dig proxy.yourdomain.com
```

应该看到CNAME记录指向Cloudflare。

### 3. 测试连接

```bash
# 测试HTTP连接
curl -I https://proxy.yourdomain.com

# 测试延迟
ping proxy.yourdomain.com
```

### 4. 查看日志

```bash
# 查看cloudflared日志
sudo journalctl -u cloudflared -f

# 查看最近的日志
sudo journalctl -u cloudflared -n 50
```

### 5. 在客户端测试

配置你的代理客户端（Clash/V2RayN等）：
- 服务器：proxy.yourdomain.com
- 端口：443
- UUID：从Xray配置中获取
- 加密：auto
- 传输：tcp
- TLS：启用

---

## 故障排查

### 问题1：Tunnel创建失败

**症状**：`cloudflared tunnel create` 失败

**解决**：
```bash
# 检查API Token权限
# 确保Token有以下权限：
# - Account.Cloudflare Tunnel: Edit
# - Zone.DNS: Edit

# 重新登录
cloudflared tunnel login

# 查看现有tunnels
cloudflared tunnel list
```

### 问题2：DNS记录未创建

**症状**：域名无法解析

**手动创建DNS记录**：
1. 登录Cloudflare Dashboard
2. 选择你的域名
3. 进入 **DNS** → **Records**
4. 添加CNAME记录：
   ```
   Type: CNAME
   Name: proxy
   Target: <tunnel-id>.cfargotunnel.com
   Proxy status: Proxied (橙色云朵)
   ```

或使用命令：
```bash
cloudflared tunnel route dns databricks-xray-proxy proxy.yourdomain.com
```

### 问题3：Tunnel无法连接到Xray

**症状**：Tunnel运行正常，但无法访问

**检查**：
```bash
# 1. 检查Xray是否运行
systemctl status xray

# 2. 检查端口
nc -zv localhost 10809

# 3. 查看cloudflared日志
journalctl -u cloudflared -n 50

# 4. 测试本地连接
curl -v http://localhost:10809
```

### 问题4：证书错误

**症状**：客户端提示SSL证书错误

**解决**：
1. 确保在ingress配置中添加了 `noTLSVerify: true`
2. 或配置正确的证书

### 问题5：连接超时

**症状**：连接经常断开

**优化配置**：
```yaml
# 在 /etc/cloudflared/config.yml 中
ingress:
  - hostname: proxy.yourdomain.com
    service: http://localhost:10809
    originRequest:
      noTLSVerify: true
      connectTimeout: 30s
      keepAliveConnections: 100
      keepAliveTimeout: 90s
```

---

## 高级配置

### 配置多个服务

如果要通过同一个tunnel暴露多个服务：

```yaml
# /etc/cloudflared/config.yml
tunnel: your-tunnel-id
credentials-file: /etc/cloudflared/credentials.json

ingress:
  - hostname: proxy.yourdomain.com
    service: http://localhost:10809
  - hostname: admin.yourdomain.com
    service: http://localhost:8080
  - hostname: api.yourdomain.com
    service: http://localhost:3000
  - service: http_status:404
```

### 配置访问策略

在Cloudflare Zero Trust中：
1. **Access** → **Applications**
2. 创建Application
3. 配置访问规则（IP白名单、邮箱验证等）

### 监控和日志

```bash
# 启用详细日志
# 在 config.yml 中设置
loglevel: debug

# 重启服务
sudo systemctl restart cloudflared

# 实时查看日志
sudo journalctl -u cloudflared -f
```

---

## 📞 获取帮助

- **Cloudflare文档**：https://developers.cloudflare.com/cloudflare-one/connections/connect-apps
- **Cloudflare社区**：https://community.cloudflare.com/
- **本项目Issues**：提交问题到GitHub

---

## 📝 总结

**推荐配置流程**：

1. **新手用户**：使用Cloudflare Dashboard（方式一）
   - 图形化界面，易于理解
   - 适合首次配置

2. **高级用户**：使用命令行（方式二）
   - 适合自动化部署
   - 可集成到CI/CD

3. **Databricks用户**：使用all-in-one脚本（方式三）
   - 最简单快速
   - 一个命令完成所有配置

选择最适合你的方式开始配置吧！

---

**最后更新**：2025-01-13
