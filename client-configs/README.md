# 客户端配置指南

这个目录包含了各种常见代理客户端的配置示例。

## 📱 支持的客户端

### Windows

- **Clash for Windows** (推荐)
  - 配置文件: `clash.yaml`
  - 下载: https://github.com/Fndroid/clash_for_windows_pkg/releases

- **V2RayN**
  - 配置文件: `v2rayn-config.json`
  - 下载: https://github.com/2dust/v2rayN/releases

### macOS

- **ClashX**
  - 配置文件: `clash.yaml`
  - 下载: https://github.com/yichengchen/clashX/releases

- **V2RayU**
  - 支持 VMess URL 导入
  - 下载: https://github.com/yanue/V2rayU/releases

### Linux

- **Clash**
  - 配置文件: `clash.yaml`
  - 安装: `sudo snap install clash`

- **V2Ray**
  - 配置文件: `v2ray-config.json`
  - 安装: https://www.v2ray.com/

### Android

- **Clash for Android**
  - 配置文件: `clash.yaml`
  - 下载: https://github.com/Kr328/ClashForAndroid/releases

- **V2RayNG**
  - 支持 VMess URL 和配置文件导入
  - 下载: https://github.com/2dust/v2rayNG/releases

### iOS

- **Shadowrocket** (付费)
  - 支持 VMess URL 导入
  - App Store 下载

- **Quantumult X** (付费)
  - 支持多种配置格式
  - App Store 下载

## 🔧 配置步骤

### 1. 获取连接信息

在服务器上运行：

```bash
cat /etc/cloudflared/connection-info.txt
```

您将看到以下信息：
- 域名 (如: proxy.yourdomain.com)
- UUID
- 端口 (默认: 443)

### 2. Clash 配置步骤

#### Windows / macOS

1. 打开 Clash 客户端
2. 点击 "配置" -> "打开配置文件夹"
3. 复制 `clash.yaml` 到该目录
4. 在配置文件中替换：
   - `proxy.yourdomain.com` → 您的域名
   - `YOUR_UUID_HERE` → 您的 UUID
5. 在 Clash 中选择该配置
6. 启用 "系统代理"

#### Android

1. 打开 Clash for Android
2. 点击右上角 "+" 按钮
3. 选择 "从文件导入"
4. 选择修改后的 `clash.yaml`
5. 点击配置文件启用

### 3. V2RayN 配置步骤 (Windows)

#### 方式一：使用配置文件

1. 打开 V2RayN
2. 点击 "服务器" -> "从剪贴板导入批量URL"
3. 或直接添加 VMess 服务器：
   - 地址: proxy.yourdomain.com
   - 端口: 443
   - 用户ID: YOUR_UUID
   - 额外ID: 0
   - 加密方式: auto
   - 传输协议: tcp
   - 启用 TLS

#### 方式二：使用 VMess URL

1. 生成 VMess URL（使用 `generate-vmess-url.sh`）
2. 复制生成的 URL
3. 在 V2RayN 中选择 "从剪贴板导入批量URL"

### 4. V2RayNG 配置步骤 (Android)

1. 打开 V2RayNG
2. 点击右上角 "+" 按钮
3. 选择 "手动输入[Vmess]"
4. 填入连接信息：
   - 别名: Databricks-Proxy
   - 地址: proxy.yourdomain.com
   - 端口: 443
   - 用户ID: YOUR_UUID
   - 额外ID: 0
   - 加密方式: auto
   - 传输协议: tcp
   - 传输层安全: tls
5. 保存并连接

### 5. Shadowrocket 配置步骤 (iOS)

1. 打开 Shadowrocket
2. 点击右上角 "+" 按钮
3. 类型选择 "VMess"
4. 填入连接信息：
   - 地址: proxy.yourdomain.com
   - 端口: 443
   - UUID: YOUR_UUID
   - 额外ID: 0
   - 加密方式: auto
   - 传输方式: tcp
   - TLS: 开启
5. 保存并连接

## 🧪 测试连接

### 方式一：使用客户端测试

1. 连接代理后，访问 https://www.google.com
2. 如果能正常访问，说明代理工作正常

### 方式二：使用命令行测试

#### Windows PowerShell

```powershell
# 设置代理
$env:HTTP_PROXY="http://127.0.0.1:7890"
$env:HTTPS_PROXY="http://127.0.0.1:7890"

# 测试连接
curl https://www.google.com
```

#### Linux / macOS

```bash
# 设置代理
export http_proxy=http://127.0.0.1:7890
export https_proxy=http://127.0.0.1:7890

# 测试连接
curl https://www.google.com
```

## 🔍 常见问题

### Q: 配置后无法连接？

**A:** 请检查：
1. 域名是否正确
2. UUID 是否正确
3. 服务器上的 Xray 和 Cloudflared 是否正常运行
4. 本地防火墙是否阻止了客户端

### Q: 连接速度慢？

**A:** 可能的原因：
1. Cloudflare CDN 节点选择问题（多试几次）
2. Databricks 集群资源不足
3. 本地网络问题

### Q: 无法访问某些网站？

**A:** 请检查：
1. Clash 规则配置是否正确
2. 目标网站是否屏蔽了 Cloudflare IP
3. 尝试切换代理模式（全局/规则）

### Q: iOS 上如何导入配置？

**A:** iOS 限制较多，推荐使用以下方式：
1. 使用 VMess URL（通过 AirDrop 或扫码）
2. 手动输入配置信息
3. 通过网页导入配置文件

## 📚 进阶配置

### 分流规则

Clash 支持强大的分流功能，可以根据域名、IP、GeoIP 等规则自动选择代理或直连。

示例：
```yaml
rules:
  # 国内网站直连
  - DOMAIN-SUFFIX,cn,DIRECT
  - GEOIP,CN,DIRECT

  # 国外网站走代理
  - DOMAIN-SUFFIX,google.com,PROXY
  - DOMAIN-SUFFIX,youtube.com,PROXY

  # 默认规则
  - MATCH,PROXY
```

### 多服务器负载均衡

如果您有多个代理服务器，可以配置负载均衡：

```yaml
proxy-groups:
  - name: "LOAD-BALANCE"
    type: load-balance
    proxies:
      - "Server-1"
      - "Server-2"
      - "Server-3"
    url: 'http://www.gstatic.com/generate_204'
    interval: 300
```

### 广告拦截

在 Clash 中添加广告拦截规则：

```yaml
rules:
  - DOMAIN-SUFFIX,doubleclick.net,REJECT
  - DOMAIN-KEYWORD,adservice,REJECT
  - DOMAIN-KEYWORD,analytics,REJECT
```

## 🔗 相关资源

- [Clash 官方文档](https://github.com/Dreamacro/clash/wiki)
- [V2Ray 配置指南](https://www.v2ray.com/chapter_02/)
- [VMess 协议说明](https://www.v2fly.org/config/protocols/vmess.html)

## ⚠️ 注意事项

1. **安全性**：请妥善保管您的 UUID，不要泄露给他人
2. **合法使用**：请遵守当地法律法规，仅用于学习和正当用途
3. **流量消耗**：注意 Databricks 集群的流量使用情况
4. **定期更新**：建议定期更新客户端和服务端软件

---

如有问题，请参考主项目 README 或提交 Issue。
