# Proxy Tunnel - 智能端口管理版

一台 Windows 给多台 Linux 服务器共享代理。自动端口管理，智能问题检测。

---

## 特点

- ✅ **智能端口清理** - 启动前自动检测并清理服务器上的旧隧道
- ✅ **预飞行检查** - 服务器启用代理前检查端口是否就绪
- ✅ **自动故障诊断** - 端口不通时自动给出解决方案
- ✅ **配置即文档** - `config.yaml` 自动记录每台服务器的实际端口
- ✅ **多源检测** - 支持 `.tunnel-mapping` 或 `config.yaml` 两种方式

---

## 使用流程

### 1. 配置（Windows）

编辑 `config.yaml`，填入服务器列表：

```yaml
servers:
  - name: server-1
    host: 173.125.1.2
    user: root
    port: 22
  
  - name: server-2
    host: 192.168.1.100
    user: root
    port: 22

proxy:
  local_proxy_port: 7897      # Windows 代理软件端口
  base_tunnel_port: 11080     # 起始端口（程序从此开始找可用端口）
```

**注意**：确保 Windows 能用公钥登录这些服务器。

---

### 2. 启动服务（Windows）

```powershell
# 启动所有隧道（自动清理旧隧道、检测端口）
.\proxy.ps1 start

# 查看状态
.\proxy.ps1 status

# 仅清理服务器上的旧隧道（修复模式）
.\proxy.ps1 fix

# 停止所有隧道
.\proxy.ps1 stop
```

启动时会：
1. 检测并清理服务器上的旧 SSH 隧道
2. 自动找到可用的端口
3. 启动新的 SSH 隧道
4. 生成 `.tunnel-mapping` 文件
5. 更新 `config.yaml` 记录分配的端口

---

### 3. 使用代理（Linux 服务器）

把整个 `proxy` 文件夹传到服务器：

```bash
# Windows PowerShell
scp -r proxy root@173.125.1.2:/home/m00663269/
```

SSH 登录服务器：

```bash
cd /home/m00663269/proxy

# 检查端口是否就绪（可选）
source proxy.sh check

# 启用代理（会自动检查端口，失败会提示）
source proxy.sh on

# 测试连接
source proxy.sh test
```

---

## 命令速查

### Windows

| 命令 | 作用 |
|-----|------|
| `proxy.ps1 start` | 启动隧道（自动清理旧隧道） |
| `proxy.ps1 fix` | 仅清理服务器上的旧隧道 |
| `proxy.ps1 stop` | 停止所有隧道 |
| `proxy.ps1 status` | 查看运行状态 |

### Linux 服务器

| 命令 | 作用 |
|-----|------|
| `source proxy.sh on` | 启用代理（带预飞行检查） |
| `source proxy.sh off` | 关闭代理 |
| `source proxy.sh check` | 检查端口是否就绪 |
| `source proxy.sh test` | 测试连接（Google/GitHub/Baidu） |
| `source proxy.sh status` | 查看状态 |

---

## 智能端口管理

### 启动时自动清理

```powershell
.\proxy.ps1 start

# 输出：
# [INFO] Checking port 11080 on 173.125.1.2...
# [WARN] Port 11080 is occupied on server
# [OK] Port 11080 cleared on server
# [OK] Tunnel started
```

### 服务器启用前检查

```bash
source proxy.sh on

# 输出：
# === Server Auto-Configuration ===
# Server IP:    173.125.1.2
# Tunnel Port:  11080
#
# Checking port connectivity...
#   ✓ Port 11080 is ready
#
# ✓ Proxy enabled
```

如果端口有问题：
```bash
source proxy.sh on

# Checking port connectivity...
#   ✗ Port 11080 is not accessible
#
# === Port Diagnostics ===
# Port 11080 is not listening
#
# Common solutions:
#   1. On Windows: Run: .\proxy.ps1 start
#   2. On Windows: Run: .\proxy.ps1 fix
```

---

## 常见问题自动解决

### 问题 1：服务器端口被旧隧道占用

**现象：**
```
remote port forwarding failed for listen port 11080
```

**解决（已自动化）：**
```powershell
# Windows 会自动检测并清理
.\proxy.ps1 start

# 或手动清理
.\proxy.ps1 fix
```

### 问题 2：服务器启动代理时端口不通

**现象：**
```
✗ Port 11080 is not accessible
```

**解决：**
```bash
# 服务器检查端口状态
source proxy.sh check

# 根据提示在 Windows 上执行修复
.\proxy.ps1 fix
# 或
.\proxy.ps1 start
```

### 问题 3：Windows 换行符导致脚本无法执行

**现象：**
```
-bash: $'': command not found
```

**解决：**
Windows 上传时已自动转换。如果仍有问题，在服务器上执行：
```bash
sed -i 's/\r$//' proxy.sh
```

---

## 查看分配的端口

启动后，查看 `config.yaml`：

```yaml
servers:
  - name: server-1
    host: 173.125.1.2
    assigned_tunnel_port: 11082  # 实际分配的端口
```

或查看 `.tunnel-mapping`：
```
173.125.1.2 11082
192.168.1.100 11083
```

---

## 不同代理软件配置

| 代理软件 | 默认端口 | config.yaml 设置 |
|---------|---------|-----------------|
| Clash Verge | 7890/7897 | `local_proxy_port: 7897` |
| v2rayN | 10808 | `local_proxy_port: 10808` |
| SSR | 1080 | `local_proxy_port: 1080` |

---

## 文件说明

| 文件 | 说明 | 人需要改？ |
|-----|------|----------|
| `config.yaml` | 主配置（含自动分配的端口） | ✅ 初始化时填服务器 |
| `proxy.ps1` | Windows 脚本（智能端口管理） | ❌ 不改 |
| `proxy.sh` | Linux 脚本（带诊断功能） | ❌ 不改 |
| `.tunnel-mapping` | 自动生成的 IP→端口映射 | ❌ 自动生成 |

---

**一句话：填配置 → 启动（自动清理）→ 传文件夹 → 服务器运行（自动检查）。**
