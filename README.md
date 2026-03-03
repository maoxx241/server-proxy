# FRP 代理共享工具

将 Windows 本机的 Clash 代理共享给远端 Linux 服务器使用。

## 功能简介

- **场景**: 服务器没有外网访问权限，但本机有 Clash 代理
- **方案**: 使用 FRP 内网穿透，将本机 Clash 代理端口映射到服务器
- **效果**: 服务器上的应用可以通过代理访问外网（如 GitHub、Google 等）
- **扩展**: 支持自定义 SSH 端口，支持 Docker 容器内使用代理

## 前置条件

### Windows 本机
1. 已安装 **Clash for Windows** 或其他代理软件
2. Clash HTTP 代理端口为 **7897**（可在 Clash 设置中确认）
3. 已安装 **Git for Windows**（提供 SSH 客户端）

### Linux 服务器
1. IP 地址: `173.125.1.2`（如需修改见下文）
2. SSH 端口: `22`（支持自定义端口，如 2222）
3. 用户名: `root`（或有 sudo 权限的用户）
4. **已通过 SSH 密钥配置免密登录**（重要！）
5. 如有 Docker 容器，也可配置容器内代理

### 网络要求
- Windows 可以 SSH 连接到 Linux 服务器
- Linux 服务器可以访问 Windows 的 Clash 代理端口（通过 FRP 隧道）

## 快速开始

假设项目已克隆/解压到 `C:\Users\maoxx241\code\server-proxy` 目录。

### 第一步：配置 SSH 免密登录

如果还没有配置 SSH 密钥，请在 **PowerShell** 中执行：

```powershell
# 生成密钥（一路回车）
ssh-keygen -t ed25519 -C "your_email@example.com"

# 复制公钥到服务器（默认端口 22）
ssh-copy-id -p 22 root@173.125.1.2

# 如果服务器使用非标准端口（如 2222）
ssh-copy-id -p 2222 root@173.125.1.2

# 测试免密登录
ssh -p 22 root@173.125.1.2
# 如果不需要输入密码就登录成功，说明配置正确
```

### 第二步：确保 Clash 运行

打开 Clash 客户端，确认：
- 状态为 "运行中"
- HTTP 代理端口为 7897（可在 设置 > 端口 中查看）

### 第三步：一键部署

在 `server-proxy` 目录下执行：

```powershell
# 进入项目目录
cd C:\Users\maoxx241\code\server-proxy

# 查看帮助
.\setup.ps1

# 首次部署（默认 SSH 端口 22）
.\setup.ps1 -Action deploy

# 如果服务器使用非标准 SSH 端口（如 2222）
.\setup.ps1 -Action deploy -ServerPort 2222
```

部署过程约 1-3 分钟，会自动：
1. 检测服务器架构
2. 下载对应版本的 FRP
3. 上传到服务器并安装
4. 配置防火墙规则
5. 启动 frp 服务

### 第四步：启动 Windows 客户端

在 `server-proxy` 目录下执行：

```powershell
# 默认端口
.\setup.ps1 -Action start

# 如果使用非标准 SSH 端口，查看状态时需指定
.\setup.ps1 -Action status -ServerPort 2222
```

启动成功后，Windows 任务管理器中应能看到 `frpc.exe` 进程。

### 第五步：在服务器上使用代理

SSH 登录到服务器，执行：

```bash
# 启用代理
source /opt/proxy-tools/set-proxy.sh

# 测试代理是否生效
curl -I https://www.google.com
curl ipinfo.io  # 查看出口IP

# 关闭代理
source /opt/proxy-tools/unset-proxy.sh
```

## Docker 容器代理（可选）

如果服务器上运行着 Docker 容器，可以为容器配置代理：

```powershell
# 配置容器代理（在 Windows 上执行）
.\setup.ps1 -Action docker -ContainerName myapp -ServerPort 2222

# 多个容器需要分别配置
.\setup.ps1 -Action docker -ContainerName app1
.\setup.ps1 -Action docker -ContainerName app2
```

然后在容器内使用：

```bash
# 进入容器
docker exec -it myapp sh

# 启用代理
set-proxy

# 测试
curl https://www.google.com

# 关闭代理
unset-proxy
```

## 常用命令

### Windows 本机（在 server-proxy 目录下执行）

```powershell
# 查看所有命令
.\setup.ps1

# 基础命令（默认 SSH 端口 22）
.\setup.ps1 -Action deploy     # 部署到服务器
.\setup.ps1 -Action start      # 启动 frp 客户端
.\setup.ps1 -Action stop       # 停止 frp 客户端
.\setup.ps1 -Action status     # 查看运行状态

# 自定义 SSH 端口（如 2222）
.\setup.ps1 -Action deploy -ServerPort 2222
.\setup.ps1 -Action status -ServerPort 2222

# Docker 容器代理
.\setup.ps1 -Action docker -ContainerName <容器名> -ServerPort 2222
```

### 参数说明

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-ServerIP` | 173.125.1.2 | 服务器 IP 地址 |
| `-ServerUser` | root | SSH 用户名 |
| `-ServerPort` | 22 | SSH 端口 |
| `-ContainerName` | (无) | Docker 容器名称 |

### Linux 服务器

```bash
# 启用代理（仅对当前终端会话有效）
source /opt/proxy-tools/set-proxy.sh

# 检查代理状态
/opt/proxy-tools/check-proxy.sh

# 关闭代理
source /opt/proxy-tools/unset-proxy.sh

# 查看 frp 服务状态
sudo systemctl status frps

# 重启 frp 服务
sudo systemctl restart frps

# 查看 frp 面板（浏览器访问）
# http://173.125.1.2:7500
# 用户名: admin
# 密码: admin123
```

## 修改服务器 IP 或端口

### 修改服务器 IP

编辑 `server-proxy\frpc.toml`：
```toml
serverAddr = "新的IP地址"
```

然后重新部署：
```powershell
cd C:\Users\maoxx241\code\server-proxy
.\setup.ps1 -Action deploy -ServerPort 2222
```

### 修改 SSH 端口

所有命令都支持 `-ServerPort` 参数：
```powershell
.\setup.ps1 -Action deploy -ServerPort 2222
.\setup.ps1 -Action status -ServerPort 2222
.\setup.ps1 -Action docker -ContainerName myapp -ServerPort 2222
```

## 故障排查

### 1. SSH 连接失败

**现象**: 部署时报 "SSH 连接失败"

**排查**:
```powershell
# 测试 SSH 连接（默认端口 22）
ssh -p 22 root@173.125.1.2

# 或使用非标准端口
ssh -p 2222 root@173.125.1.2

# 如果要求输入密码，说明免密登录未配置成功
# 重新执行: ssh-copy-id -p 2222 root@173.125.1.2
```

### 2. frpc 启动失败

**现象**: "frpc 启动失败"

**排查**（在 `server-proxy` 目录下）:
```powershell
# 检查服务器 frps 是否运行（注意指定端口）
ssh -p 2222 root@173.125.1.2 "systemctl status frps"

# 检查端口是否可连接
Test-NetConnection -ComputerName 173.125.1.2 -Port 7000

# 手动启动查看错误
.\frp\frpc.exe -c frpc.toml
```

### 3. 代理不生效

**现象**: `curl google.com` 失败

**排查**:
```bash
# 在服务器上检查代理环境变量
echo $http_proxy

# 检查 frp 端口是否监听
ss -tlnp | grep frps

# 检查防火墙
sudo firewall-cmd --list-ports
# 应包含: 7000/tcp 7897/tcp 7898/tcp
```

### 4. Docker 容器代理不生效

**现象**: 容器内执行 `set-proxy` 后仍无法访问外网

**排查**:
```bash
# 检查容器内代理脚本是否存在
docker exec myapp ls -la /usr/local/bin/set-proxy

# 检查容器是否能访问宿主机代理端口
docker exec myapp wget -O- http://173.125.1.2:7897

# 重新配置容器代理
# 在 Windows 上重新执行:
# .\setup.ps1 -Action docker -ContainerName myapp -ServerPort 2222
```

### 5. 下载 frp 失败

**现象**: 部署时下载卡住或失败

**解决**:
- 确保 Clash 正常运行
- 尝试切换 Clash 节点
- 手动下载后放到 `server-proxy\frp\` 目录

## 项目结构

```
server-proxy/                    <-- 在此目录下执行所有命令
├── frp/                         # FRP 客户端程序
│   └── frpc.exe                # Windows 客户端
├── frpc.toml                    # 客户端配置
├── setup.ps1                    # 主控脚本（一键操作）
├── start-frpc.bat               # 传统启动脚本
├── start-frpc.vbs               # 后台启动脚本
├── README.md                    # 本文件
└── deploy/
    └── deploy.ps1               # 服务器部署脚本
```

## 注意事项

1. **安全性**: 默认面板密码为 `admin123`，生产环境请修改
2. **端口占用**: 确保 Windows 7897/7898 端口未被占用
3. **防火墙**: 服务器需要开放 7000、7897、7898、7500 端口
4. **代理范围**: 代理仅对当前终端会话有效，不会全局生效
5. **执行目录**: 所有 Windows 命令需在 `server-proxy` 目录下执行
6. **SSH 端口**: 使用非标准端口时，所有命令都需加 `-ServerPort` 参数

## 进阶配置

### 修改面板密码

编辑 `server-proxy\deploy\deploy.ps1`，找到：
```powershell
webServer.password = "admin123"
```
修改后重新部署：
```powershell
cd C:\Users\maoxx241\code\server-proxy
.\setup.ps1 -Action deploy -ServerPort 2222
```

### 使用其他代理端口

如果 Clash 代理端口不是 7897：

1. 修改 `server-proxy\frpc.toml` 中的 `localPort`
2. 修改 `server-proxy\setup.ps1` 中的 `$LocalProxyPort`
3. 重新部署

## 卸载

Windows 本机（在 `server-proxy` 目录下）:
```powershell
# 停止 frpc
.\setup.ps1 -Action stop

# 删除项目文件夹即可
```

Linux 服务器:
```bash
# 停止并删除服务
sudo systemctl stop frps
sudo systemctl disable frps
sudo rm -f /etc/systemd/system/frps.service

# 删除文件
sudo rm -rf /opt/frp
sudo rm -rf /opt/proxy-tools

# 关闭防火墙端口
sudo firewall-cmd --permanent --remove-port=7000/tcp
sudo firewall-cmd --permanent --remove-port=7897/tcp
sudo firewall-cmd --permanent --remove-port=7898/tcp
sudo firewall-cmd --reload
```

## 技术支持

如有问题，请检查：
1. 所有前置条件是否满足
2. 确认在 `server-proxy` 目录下执行命令
3. 如使用非标准 SSH 端口，确认所有命令都加了 `-ServerPort` 参数
4. 按照 "故障排查" 章节逐步排查
5. 查看日志：`frpc.log` 或服务器 `/var/log/frps.log`
