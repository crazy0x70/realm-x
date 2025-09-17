# Realm-X 管理工具

![Version](https://img.shields.io/badge/version-2.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)

Realm-X 是一个功能强大的 Realm 转发管理工具，提供了一键安装、配置管理、MPTCP 支持等全面功能，让端口转发配置变得简单高效。

## ✨ 主要特性

- 🚀 **一键安装** - 自动检测系统架构，智能下载对应版本
- 🔄 **MPTCP 支持** - 自动检测并配置 MPTCP（多路径 TCP）功能
- 🔐 **加密隧道** - 支持 TLS、WebSocket、WSS 等多种加密方式
- 📊 **可视化管理** - 交互式菜单和命令行双重操作模式
- 🛡️ **服务管理** - 集成 systemd 服务，支持开机自启
- 🔧 **灵活配置** - 支持 IPv4/IPv6，动态管理转发规则
- 💾 **配置备份** - 自动备份配置文件，安全删除规则

## 📋 系统要求

### 支持的操作系统
- Ubuntu 18.04+
- Debian 9+
- CentOS 7+
- RHEL 7+
- Fedora 30+
- Alpine Linux 3.10+

### 支持的系统架构
- x86_64 (AMD64)
- ARM64/aarch64
- ARMv7
- ARM

### MPTCP 支持要求
- Linux 内核版本 ≥ 5.6
- 系统支持 MPTCP 内核模块

## 🚀 快速开始

### 一键安装

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/crazy0x70/realm-x/refs/heads/main/realm-install.sh)"
```

或使用 wget：

```bash
sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/crazy0x70/realm-x/refs/heads/main/realm-install.sh)"
```

### 首次使用

安装完成后，可以通过以下方式使用：

```bash
# 显示交互式菜单
realm-x

# 查看帮助信息
realm-x -h

# 添加转发规则
realm-x -a

# 查看当前规则
realm-x -l
```

## 📖 使用指南

### 命令行参数

| 参数 | 长参数 | 描述 |
|:---:|:---:|:---|
| `-h` | `--help` | 显示帮助信息 |
| `-i` | `--install` | 安装或更新 Realm |
| `-s` | `--status` | 查看 Realm 服务状态 |
| `-r` | `--restart` | 重启 Realm 服务 |
| `-l` | `--list` | 列出当前转发规则 |
| `-a` | `--add` | 添加新的转发规则 |
| `-d` | `--delete` | 删除转发规则 |
| `-e` | `--edit` | 编辑配置文件 |
| `-m` | `--mptcp` | 管理 MPTCP 设置 |
| `-u` | `--uninstall` | 卸载 Realm |

### 交互式菜单

直接运行 `realm-x` 进入交互式菜单：

```
====== Realm 管理脚本 ======
1. 安装或更新 Realm
2. 显示当前转发规则
3. 添加新的转发规则
4. 删除转发规则
5. 编辑配置文件
6. 管理MPTCP设置
7. 重启 Realm 服务
8. 查看 Realm 状态
9. 卸载 Realm
10. 退出
===========================
```

## 🔧 功能详解

### 端口转发配置

添加基本转发规则：
```bash
realm-x -a
# 输入本地端口: 8080
# 输入远程地址: example.com
# 输入远程端口: 80
```

### 加密隧道支持

支持三种加密方式：
- **TLS** - 传输层安全协议
- **WebSocket (WS)** - WebSocket 协议
- **WebSocket + TLS (WSS)** - 加密的 WebSocket

### MPTCP 多路径传输

MPTCP 功能可以：
- 提高网络连接的可靠性
- 增加带宽利用率
- 自动故障切换

检查 MPTCP 状态：
```bash
# 查看系统 MPTCP 状态
cat /proc/sys/net/mptcp/enabled

# 管理 MPTCP 设置
realm-x -m
```

### IPv6 支持

自动检测并正确处理 IPv6 地址：
```bash
# IPv6 地址会自动添加方括号
# 例如: 2001:db8::1 -> [2001:db8::1]
```

## 📁 文件位置

| 文件类型 | 路径 |
|:---:|:---|
| **Realm 二进制** | `/usr/local/bin/realm` |
| **配置文件** | `/usr/local/etc/realm/realm.toml` |
| **服务文件** | `/etc/systemd/system/realm.service` |
| **管理工具** | `/usr/local/bin/realm-x` |
| **MPTCP 配置** | `/etc/sysctl.conf` 或 `/etc/sysctl.d/99-mptcp.conf` |

## 🔍 故障排查

### 检查服务状态
```bash
# 查看服务状态
systemctl status realm

# 查看服务日志
journalctl -u realm -f

# 检查配置文件
realm-x -e
```

### 检查 MPTCP 状态
```bash
# 检查内核支持
uname -r

# 检查 MPTCP 启用状态
sysctl net.mptcp.enabled

# 查看 MPTCP 连接
ss -M
```

### 常见问题

1. **权限不足**
```bash
   # 使用 sudo 运行
   sudo realm-x
   ```

2. **端口被占用**
   ```bash
   # 检查端口占用
   netstat -tlnp | grep 端口号
   ```

3. **MPTCP 不支持**
   - 检查内核版本是否 ≥ 5.6
   - 确认内核编译时启用了 MPTCP 支持

## 🔒 安全建议

1. **定期备份配置**
   ```bash
   cp /usr/local/etc/realm/realm.toml ~/realm.toml.backup
   ```

2. **使用加密隧道**
   - 对于敏感数据传输，建议启用 TLS 或 WSS 加密

3. **限制访问权限**
   - 配置防火墙规则限制访问来源
   - 使用强密码保护管理界面

## 🔄 更新和卸载

### 更新到最新版本
```bash
realm-x -i
```

### 完全卸载
```bash
realm-x -u
# 可选择保留配置文件以便将来重新安装
```

## 📊 性能优化

### MPTCP 优化
```bash
# 启用 MPTCP
echo "net.mptcp.enabled=1" >> /etc/sysctl.conf
sysctl -p

# 调整 MPTCP 参数
sysctl -w net.mptcp.checksum_enabled=0 # 禁用校验和以提高性能
```

### 系统优化
```bash
# 增加文件描述符限制
ulimit -n 65535

# 优化网络参数
echo "net.core.somaxconn=65535" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog=65535" >> /etc/sysctl.conf
sysctl -p
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

### 报告问题
请在提交 Issue 时包含：
- 系统版本信息 (`uname -a`)
- Realm 版本
- 错误日志
- 复现步骤

## 📜 许可证

本项目采用 MIT 许可证。详情请参阅 [LICENSE](LICENSE) 文件。

## 🙏 致谢

- [Realm](https://github.com/zhboner/realm) - 核心转发引擎
- 所有贡献者和用户的支持

---

**注意事项：**
- ⚠️ 大多数操作需要 root 权限
- ⚠️ 卸载操作会完全移除 Realm 和 realm-x 工具
- ⚠️ 修改配置后需要重启服务生效
- ⚠️ 建议在生产环境使用前先在测试环境验证
