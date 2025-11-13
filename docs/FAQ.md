# 常见问题解答 (FAQ)

## 📋 目录

- [安装相关](#安装相关)
- [配置相关](#配置相关)
- [连接问题](#连接问题)
- [性能问题](#性能问题)
- [Databricks 特定问题](#databricks-特定问题)
- [Cloudflare Tunnel 问题](#cloudflare-tunnel-问题)
- [客户端问题](#客户端问题)
- [安全相关](#安全相关)

---

## 安装相关

### Q1: 支持哪些操作系统？

**A:** 支持以下操作系统：
- Ubuntu 18.04+
- Debian 10+
- CentOS 7+
- Amazon Linux 2
- 其他基于 systemd 的 Linux 发行版

支持的架构：
- x86_64 (amd64)
- ARM64 (aarch64)

### Q2: 安装失败提示权限不足？

**A:** 请确保使用 root 权限运行脚本：
```bash
sudo ./install-xray-proxy.sh
```

或切换到 root 用户：
```bash
sudo su -
./install-xray-proxy.sh
```

### Q3: 下载速度很慢或超时？

**A:** 可能的解决方案：

1. **使用代理下载**（如果您已经有可用的代理）：
```bash
export http_proxy=http://your-proxy:port
export https_proxy=http://your-proxy:port
./install-xray-proxy.sh
```

2. **使用国内镜像**（如果在中国大陆）：
编辑脚本，将 GitHub 下载链接替换为镜像站点。

3. **手动下载并安装**：
```bash
# 手动下载 Xray
wget https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip

# 解压并安装
unzip Xray-linux-64.zip
sudo install -m 755 xray /usr/local/bin/xray
```

### Q4: 提示找不到 jq 命令？

**A:** 安装 jq：
```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y jq

# CentOS/RHEL
sudo yum install -y jq
```

---

## 配置相关

### Q5: 如何修改 UUID？

**A:**

1. **安装时指定**：
```bash
export XRAY_UUID="your-custom-uuid"
./install-xray-proxy.sh
```

2. **安装后修改**：
```bash
# 生成新 UUID
NEW_UUID=$(cat /proc/sys/kernel/random/uuid)

# 修改配置
sudo sed -i "s/\"id\": \".*\"/\"id\": \"$NEW_UUID\"/" /etc/xray/config.json

# 重启服务
sudo systemctl restart xray
```

### Q6: 如何更改端口？

**A:** 编辑配置文件：
```bash
sudo nano /etc/xray/config.json
```

修改 `port` 字段，然后重启服务：
```bash
sudo systemctl restart xray
```

### Q7: 可以同时运行多个 Xray 实例吗？

**A:** 可以，但需要：
1. 使用不同的端口
2. 创建不同的 systemd 服务文件
3. 使用不同的配置文件路径

示例：
```bash
# 复制配置
sudo cp /etc/xray/config.json /etc/xray/config-2.json

# 修改端口
sudo sed -i 's/10809/10810/' /etc/xray/config-2.json

# 创建新服务
sudo cp /etc/systemd/system/xray.service /etc/systemd/system/xray-2.service

# 修改服务配置中的配置文件路径
sudo nano /etc/systemd/system/xray-2.service
```

---

## 连接问题

### Q8: 客户端无法连接？

**A:** 按以下步骤排查：

1. **检查服务状态**：
```bash
sudo systemctl status xray
sudo systemctl status cloudflared
```

2. **检查端口**：
```bash
nc -z 127.0.0.1 10809  # VMess 端口
nc -z 127.0.0.1 1080   # SOCKS5 端口
```

3. **检查 UUID**：
```bash
grep '"id"' /etc/xray/config.json
```

4. **查看日志**：
```bash
sudo journalctl -u xray -f
sudo tail -f /var/log/xray/error.log
```

5. **测试本地连接**：
```bash
curl -x socks5://127.0.0.1:1080 https://www.google.com
```

### Q9: 提示 "connection refused"？

**A:**
1. 确认 Xray 服务正在运行
2. 检查防火墙设置
3. 确认客户端配置的服务器地址正确
4. 检查 Cloudflare Tunnel 是否正常运行

### Q10: 连接成功但无法访问网站？

**A:** 可能的原因：

1. **DNS 问题**：尝试使用不同的 DNS
```json
// 在 Xray 配置中添加
{
  "dns": {
    "servers": [
      "8.8.8.8",
      "1.1.1.1"
    ]
  }
}
```

2. **路由规则问题**：检查 Xray 配置中的路由规则

3. **目标网站屏蔽了 Cloudflare IP**：考虑更换协议或使用其他方案

---

## 性能问题

### Q11: 速度很慢？

**A:** 优化建议：

1. **选择更近的 Cloudflare 节点**（自动选择，多试几次）

2. **优化 Xray 配置**：
```json
{
  "policy": {
    "levels": {
      "0": {
        "handshake": 4,
        "connIdle": 300,
        "uplinkOnly": 2,
        "downlinkOnly": 5
      }
    }
  }
}
```

3. **调整系统参数**：
```bash
# 启用 BBR
echo "net.core.default_qdisc=fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

4. **检查 Databricks 集群资源**：
   - 增加节点数量
   - 使用更高配置的实例类型

### Q12: CPU 使用率过高？

**A:**
1. 减少日志级别：将 `loglevel` 设置为 `error`
2. 检查是否有异常流量
3. 考虑升级 Databricks 集群配置

### Q13: 内存占用过大？

**A:**
1. 限制连接数
2. 定期重启服务
3. 优化路由规则，减少不必要的连接

---

## Databricks 特定问题

### Q14: 集群重启后服务没有自动启动？

**A:**
1. **确认使用了 Init Script**：
   - 检查集群配置中的 Init Scripts 设置
   - 确认脚本路径正确

2. **检查 Init Script 日志**：
```python
# 在 Databricks Notebook 中
display(dbutils.fs.ls("/databricks/init-scripts/logs/"))
```

3. **手动验证 Init Script**：
```bash
# SSH 到集群后执行
sudo /dbfs/databricks/init-scripts/xray-proxy-init.sh
```

### Q15: 在 Databricks 中如何查看日志？

**A:**
```python
# 在 Notebook 中
%sh
journalctl -u xray -n 50
```

或者：
```bash
# SSH 到集群
sudo journalctl -u xray -f
```

### Q16: Init Script 执行失败？

**A:**
1. **检查脚本权限**：
```python
dbutils.fs.ls("/databricks/init-scripts/")
```

2. **验证脚本内容**：
```python
print(dbutils.fs.head("/databricks/init-scripts/xray-proxy-init.sh"))
```

3. **查看 Init Script 日志**：
   - 集群 UI -> Event Log -> Init Scripts

### Q17: 如何在 Databricks Notebook 中使用代理？

**A:**
```python
import os
import requests

# 设置代理
os.environ['HTTP_PROXY'] = 'socks5://127.0.0.1:1080'
os.environ['HTTPS_PROXY'] = 'socks5://127.0.0.1:1080'

# 或者在请求中指定
proxies = {
    'http': 'socks5://127.0.0.1:1080',
    'https': 'socks5://127.0.0.1:1080'
}

response = requests.get('https://www.google.com', proxies=proxies)
print(response.status_code)
```

---

## Cloudflare Tunnel 问题

### Q18: Cloudflare Tunnel 认证失败？

**A:**
1. **验证 Token**：
   - 确认 Token 没有过期
   - 检查 Token 权限是否正确
   - 重新生成 Token

2. **重新认证**：
```bash
cloudflared tunnel login
```

### Q19: DNS 记录没有自动创建？

**A:** 手动创建 DNS 记录：
```bash
cloudflared tunnel route dns <tunnel-name> <domain>
```

或在 Cloudflare Dashboard 中手动添加 CNAME 记录。

### Q20: 隧道状态显示 "reconnecting"？

**A:**
1. 检查网络连接
2. 查看 cloudflared 日志：
```bash
sudo journalctl -u cloudflared -f
```
3. 重启服务：
```bash
sudo systemctl restart cloudflared
```

### Q21: 如何删除 Cloudflare Tunnel？

**A:**
```bash
# 停止服务
sudo systemctl stop cloudflared

# 删除隧道
cloudflared tunnel delete <tunnel-name>

# 删除 DNS 记录（在 Cloudflare Dashboard 中）

# 删除本地文件
sudo rm -rf /etc/cloudflared
```

---

## 客户端问题

### Q22: Clash 导入配置后无法连接？

**A:**
1. 检查配置文件格式
2. 确认域名和 UUID 正确
3. 尝试手动添加节点而不是导入配置
4. 查看 Clash 日志

### Q23: V2RayN 提示 "bad config"？

**A:**
1. 检查 VMess URL 格式
2. 确认所有必需字段都已填写
3. 尝试手动输入配置而不是使用 URL

### Q24: iOS 上无法使用？

**A:**
iOS 限制较多，建议：
1. 使用付费客户端（Shadowrocket、Quantumult X）
2. 确认客户端支持 VMess 协议
3. 手动输入配置信息
4. 检查 iOS 系统版本兼容性

### Q25: 客户端显示连接成功但无法上网？

**A:**
1. 检查系统代理设置
2. 在客户端中测试连接
3. 查看客户端日志
4. 尝试切换代理模式（全局/规则/直连）

---

## 安全相关

### Q26: UUID 泄露了怎么办？

**A:** 立即更换 UUID：
```bash
# 生成新 UUID
NEW_UUID=$(cat /proc/sys/kernel/random/uuid)

# 更新配置
sudo sed -i "s/\"id\": \".*\"/\"id\": \"$NEW_UUID\"/" /etc/xray/config.json

# 重启服务
sudo systemctl restart xray

# 更新客户端配置
```

### Q27: 如何防止被检测？

**A:**
1. 使用 Cloudflare Tunnel（已经提供了很好的伪装）
2. 定期更换端口和 UUID
3. 启用 TLS
4. 使用 WebSocket 传输
5. 添加 CDN

### Q28: 日志中有大量未知 IP 连接？

**A:**
1. 立即更换 UUID
2. 添加 IP 白名单
3. 启用认证
4. 检查是否有服务暴露在公网

### Q29: 如何启用访问日志但保护隐私？

**A:**
1. 设置合理的日志级别（warning 或 error）
2. 定期清理日志
3. 配置日志轮转
4. 确保日志文件权限正确（600）

---

## 其他问题

### Q30: 如何升级 Xray？

**A:**
```bash
# 停止服务
sudo systemctl stop xray

# 重新运行安装脚本
sudo ./install-xray-proxy.sh

# 或手动下载新版本
wget https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
unzip Xray-linux-64.zip
sudo install -m 755 xray /usr/local/bin/xray

# 启动服务
sudo systemctl start xray

# 检查版本
xray version
```

### Q31: 如何备份配置？

**A:**
```bash
# 创建备份目录
mkdir -p ~/xray-backup

# 备份配置和密钥
sudo cp -r /etc/xray ~/xray-backup/
sudo cp -r /etc/cloudflared ~/xray-backup/

# 创建压缩包
tar -czf xray-backup-$(date +%Y%m%d).tar.gz ~/xray-backup

# 安全地存储备份文件
```

### Q32: 如何完全卸载？

**A:**
```bash
# 使用卸载脚本
sudo ./utils/uninstall.sh

# 或手动卸载
sudo systemctl stop xray cloudflared
sudo systemctl disable xray cloudflared
sudo rm -rf /etc/xray /etc/cloudflared /var/log/xray
sudo rm -f /usr/local/bin/xray /usr/local/bin/cloudflared
sudo rm -f /etc/systemd/system/xray.service /etc/systemd/system/cloudflared.service
sudo systemctl daemon-reload
```

### Q33: 支持 IPv6 吗？

**A:**
Xray 支持 IPv6，但需要：
1. 服务器支持 IPv6
2. Cloudflare 启用 IPv6
3. 在配置中指定 IPv6 地址

### Q34: 可以用于企业环境吗？

**A:**
可以，但建议：
1. 进行充分的安全评估
2. 遵守公司的网络政策
3. 配置更严格的访问控制
4. 启用详细的审计日志
5. 定期更新和维护

### Q35: 遇到其他问题怎么办？

**A:**
1. 查看完整日志：
```bash
sudo journalctl -u xray -n 100
sudo journalctl -u cloudflared -n 100
```

2. 运行诊断脚本：
```bash
./utils/check-status.sh
```

3. 提交 Issue：
   - 到 GitHub 项目页面
   - 提供详细的错误信息和日志
   - 说明您的环境和配置

4. 查看项目文档和 README

---

## 📞 获取帮助

如果以上 FAQ 没有解决您的问题：

1. **查看完整文档**：README.md
2. **搜索已有 Issues**：https://github.com/yourusername/databricks-xray-proxy/issues
3. **提交新 Issue**：提供详细信息和日志
4. **加入讨论**：GitHub Discussions

---

**最后更新**: 2025-01-13
