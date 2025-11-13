# Databricks 集群架构代理部署指南

本指南专门针对Databricks的**节点架构**，说明如何在集群环境中正确部署和使用Xray代理。

## 📊 Databricks 集群架构

```
┌─────────────────────────────────────────────────────┐
│                Databricks 集群                       │
│                                                      │
│  ┌────────────────────┐                             │
│  │   Driver 节点      │  ← Xray代理运行在这里       │
│  │  - 运行Notebook    │                             │
│  │  - 管理任务        │                             │
│  │  - Xray服务        │                             │
│  └─────────┬──────────┘                             │
│            │                                         │
│            ├──────┬──────┬──────┐                   │
│            │      │      │      │                   │
│  ┌─────────▼──┐ ┌▼──────▼┐ ┌──▼─────────┐         │
│  │  Worker 1  │ │ Worker 2│ │  Worker 3  │         │
│  │  (执行器)  │ │ (执行器)│ │  (执行器)  │         │
│  └────────────┘ └─────────┘ └────────────┘         │
│                                                      │
│  所有节点都可以访问Driver上的代理服务               │
└─────────────────────────────────────────────────────┘
```

## 🎯 部署策略

### 推荐方案：仅在Driver节点部署（默认）

**优势**：
- ✅ 节省资源（只在一个节点运行）
- ✅ 配置简单（单点管理）
- ✅ 足够用（所有节点都能访问）
- ✅ 避免端口冲突

**实现方式**：
脚本会自动检测节点类型，只在Driver节点安装。

## 🚀 快速部署

### 方式一：使用集群优化脚本（推荐）

```python
# 在Databricks Notebook中

# 1. 上传脚本
script = open('databricks-xray-cluster.sh').read()
dbutils.fs.put("/databricks/init-scripts/xray-cluster.sh", script, overwrite=True)

# 2. 配置集群
# Cluster → Edit → Advanced Options → Init Scripts
# 添加: dbfs:/databricks/init-scripts/xray-cluster.sh

# 3. 启动集群
# 脚本会自动识别节点类型，只在Driver安装
```

### 方式二：手动指定模式

在集群环境变量中配置：

```bash
# Cluster → Advanced Options → Environment Variables

# 模式选择（三选一）
XRAY_NODE_MODE=driver_only    # 只在Driver安装（默认，推荐）
XRAY_NODE_MODE=all_nodes      # 在所有节点安装（不推荐）
XRAY_NODE_MODE=manual         # 手动控制

# 其他配置（可选）
XRAY_UUID=your-uuid-here
XRAY_BIND_ADDRESS=0.0.0.0     # 允许集群内访问
```

## 📝 在Notebook中使用代理

部署完成后，在任意Notebook中可以这样使用：

### Python示例

```python
# Cell 1: 查看代理信息
%sh
cat /etc/xray/cluster-access-info.txt
```

```python
# Cell 2: 获取Driver IP
driver_ip = spark.conf.get("spark.driver.host")
print(f"Driver IP: {driver_ip}")
```

```python
# Cell 3: 使用代理访问外网
import requests

# 配置代理
proxies = {
    'http': f'socks5://{driver_ip}:1080',
    'https': f'socks5://{driver_ip}:1080'
}

# 测试连接
response = requests.get('https://www.google.com', proxies=proxies, timeout=10)
print(f"状态码: {response.status_code}")
print("✓ 代理工作正常！")
```

### Scala示例

```scala
// 获取Driver地址
val driverHost = spark.conf.get("spark.driver.host")
val proxyUrl = s"socks5://${driverHost}:1080"

// 配置系统代理
System.setProperty("socksProxyHost", driverHost)
System.setProperty("socksProxyPort", "1080")

println(s"代理配置: ${proxyUrl}")
```

### R示例

```r
# 获取Driver IP
driver_ip <- SparkR:::callJMethod(
  SparkR:::callJMethod(SparkR::sparkR.session(), "conf"),
  "get",
  "spark.driver.host"
)

# 设置代理
Sys.setenv(
  http_proxy = paste0("socks5://", driver_ip, ":1080"),
  https_proxy = paste0("socks5://", driver_ip, ":1080")
)

# 测试
library(httr)
response <- GET("https://www.google.com")
print(status_code(response))
```

### SQL示例（访问外部API）

```sql
-- 在Notebook中，先设置代理环境变量
%python
import os
os.environ['http_proxy'] = f'socks5://{driver_ip}:1080'
os.environ['https_proxy'] = f'socks5://{driver_ip}:1080'
```

## 🔧 集群配置选项

### 方案A：最简配置（推荐）

```python
# 只上传Init Script，使用默认配置
# - 自动在Driver安装
# - 自动生成UUID
# - 绑定0.0.0.0（集群内可访问）
```

### 方案B：自定义配置

```bash
# 集群环境变量
XRAY_NODE_MODE=driver_only
XRAY_UUID=your-fixed-uuid        # 使用固定UUID
XRAY_PORT=10809
XRAY_SOCKS_PORT=1080
XRAY_BIND_ADDRESS=0.0.0.0        # 集群内访问
LOG_LEVEL=warning
```

### 方案C：包含Cloudflare Tunnel

```bash
# 集群环境变量
XRAY_NODE_MODE=driver_only
CF_TOKEN=your-cloudflare-token
TUNNEL_DOMAIN=proxy.yourdomain.com

# 支持内网+外网访问
```

## 🌐 访问方式对比

| 访问方式 | 场景 | 配置 | 速度 |
|---------|------|------|------|
| **集群内访问** | Notebook代码中使用 | 无需额外配置 | 最快 |
| **Cloudflare Tunnel** | 外部客户端访问 | 需配置CF Token | 较快 |
| **混合模式** | 内外兼顾 | 两者都配置 | 灵活 |

## 📊 Spark作业中使用代理

### 方式一：在Driver上配置

```python
# 在Notebook中
spark.sparkContext.setSystemProperty("http.proxyHost", driver_ip)
spark.sparkContext.setSystemProperty("http.proxyPort", "1080")
spark.sparkContext.setSystemProperty("https.proxyHost", driver_ip)
spark.sparkContext.setSystemProperty("https.proxyPort", "1080")
```

### 方式二：在集群配置中全局设置

在集群配置的Spark Config中添加：

```
spark.driver.extraJavaOptions -Dhttp.proxyHost=<driver-ip> -Dhttp.proxyPort=1080 -Dhttps.proxyHost=<driver-ip> -Dhttps.proxyPort=1080
spark.executor.extraJavaOptions -Dhttp.proxyHost=<driver-ip> -Dhttp.proxyPort=1080 -Dhttps.proxyHost=<driver-ip> -Dhttps.proxyPort=1080
```

**注意**：需要替换`<driver-ip>`为实际IP，或使用环境变量。

### 方式三：在代码中动态配置

```python
from pyspark import SparkConf

# 创建新的Spark Session时配置
conf = SparkConf()
conf.set("spark.driver.extraJavaOptions",
         f"-Dhttp.proxyHost={driver_ip} -Dhttp.proxyPort=1080")

# 应用到Spark作业
```

## 🔍 监控和调试

### 查看服务状态

```bash
%sh
# 检查Xray服务
systemctl status xray

# 检查端口
netstat -tlnp | grep -E '10809|1080'

# 查看日志
tail -f /var/log/xray/access.log
```

### 查看集群连接信息

```python
# 在Notebook中
%sh
cat /etc/xray/cluster-access-info.txt
```

### 测试连接

```python
import requests

def test_proxy(driver_ip):
    proxies = {
        'http': f'socks5://{driver_ip}:1080',
        'https': f'socks5://{driver_ip}:1080'
    }

    try:
        # 测试连接
        r = requests.get('https://www.google.com',
                        proxies=proxies,
                        timeout=10)
        print(f"✓ 连接成功！状态码: {r.status_code}")

        # 测试速度
        import time
        start = time.time()
        r = requests.get('https://www.google.com', proxies=proxies)
        elapsed = time.time() - start
        print(f"✓ 响应时间: {elapsed:.2f}秒")

        return True
    except Exception as e:
        print(f"✗ 连接失败: {e}")
        return False

# 获取Driver IP并测试
driver_ip = spark.conf.get("spark.driver.host")
test_proxy(driver_ip)
```

## ⚠️ 注意事项

### 1. IP地址变化

**问题**：集群重启后Driver IP可能改变

**解决方案**：
```python
# 每次使用前动态获取Driver IP
driver_ip = spark.conf.get("spark.driver.host")

# 或者在Notebook开头声明
import os
os.environ['DRIVER_IP'] = spark.conf.get("spark.driver.host")
```

### 2. 端口冲突

**问题**：如果其他服务占用了1080或10809端口

**解决方案**：
```bash
# 在集群环境变量中修改端口
XRAY_PORT=10810
XRAY_SOCKS_PORT=1081
```

### 3. Worker节点访问

**问题**：Worker节点能访问Driver上的代理吗？

**答案**：可以！因为配置了`XRAY_BIND_ADDRESS=0.0.0.0`

```python
# 在Worker任务中也可以使用
def task_with_proxy(partition):
    import requests
    driver_ip = "从环境变量或配置获取"
    proxies = {'http': f'socks5://{driver_ip}:1080'}
    response = requests.get('https://api.example.com', proxies=proxies)
    return response.json()

rdd.mapPartitions(task_with_proxy).collect()
```

### 4. 性能影响

**建议**：
- 只在需要时使用代理
- 对于内部Databricks资源，不使用代理
- 考虑缓存频繁访问的外部数据

### 5. 安全性

**重要**：
- 代理服务只在集群内网访问（如果只配置内网）
- UUID作为认证，不要泄露
- 定期更新UUID
- 监控访问日志

## 🎯 最佳实践

### 1. 使用环境变量管理配置

```python
# 在Notebook开头统一配置
import os

# 获取Driver IP
DRIVER_IP = spark.conf.get("spark.driver.host")
PROXY_PORT = 1080

# 设置环境变量
os.environ['http_proxy'] = f'socks5://{DRIVER_IP}:{PROXY_PORT}'
os.environ['https_proxy'] = f'socks5://{DRIVER_IP}:{PROXY_PORT}'

# 后续代码自动使用代理
```

### 2. 创建代理工具函数

```python
# 在Notebook中定义
def get_proxies():
    """获取代理配置"""
    driver_ip = spark.conf.get("spark.driver.host")
    return {
        'http': f'socks5://{driver_ip}:1080',
        'https': f'socks5://{driver_ip}:1080'
    }

# 使用
import requests
response = requests.get('https://api.example.com', proxies=get_proxies())
```

### 3. 条件使用代理

```python
# 只对外部请求使用代理
def smart_request(url, use_proxy=None):
    if use_proxy is None:
        # 自动判断：外部URL使用代理
        use_proxy = not url.startswith('https://databricks')

    proxies = get_proxies() if use_proxy else None
    return requests.get(url, proxies=proxies)
```

## 📚 相关文档

- [完整部署指南](../README.md)
- [Cloudflare Tunnel配置](CLOUDFLARE_TUNNEL_SETUP.md)
- [常见问题](FAQ.md)
- [单文件部署](../DATABRICKS_DEPLOYMENT.md)

## 🆘 故障排查

### 问题：代理在Driver上运行，但Worker无法访问

**检查**：
```bash
# 在Driver上
netstat -tlnp | grep 1080

# 应该看到 0.0.0.0:1080 而不是 127.0.0.1:1080
```

**修复**：
```bash
# 确保配置中使用 0.0.0.0
XRAY_BIND_ADDRESS=0.0.0.0
```

### 问题：集群重启后服务未启动

**检查**：
```bash
systemctl status xray
```

**修复**：
确保使用了Init Script，而不是手动执行脚本。

### 问题：无法获取Driver IP

**方法一**：
```python
driver_ip = spark.conf.get("spark.driver.host")
```

**方法二**：
```bash
%sh
hostname -I | awk '{print $1}'
```

**方法三**：
```python
import socket
driver_ip = socket.gethostbyname(socket.gethostname())
```

---

**最后更新**：2025-01-13
