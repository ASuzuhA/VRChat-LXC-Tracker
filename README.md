# VRChat Track Logger & Auto Deployer (PVE LXC)

一个专为 PVE Debian 12 LXC 容器打造的自动化 VRChat 轨迹监听与数据提取工具。通过在后台轻量化运行 VRCX 小号，实时捕获目标账号的上下线记录、房间切换以及每个地图的停留时长，并自动导出为易于解析的结构化 `JSON` 文件。

---

## 📁 项目文件与目录结构

部署完成后，系统内相关的核心文件及默认路径说明如下：

| 文件 / 目录绝对路径 | 类型 | 作用与说明 |
| :--- | :--- | :--- |
| `/root/vrcx_data/data.json` | JSON 文件 | **【核心产物】** 提取并格式化后的数据文件，包含日期、上下线事件、换房记录及停留时长。供后续前端/AI 读取。 |
| `/root/vrcx/export_daily.py` | Python 脚本 | **【解析逻辑】** 定时读取 VRCX 的 SQLite 数据库，计算时间差与停留时长，并更新 `data.json`。 |
| `/root/vrcx/deploy_vrcx.sh` | Shell 脚本 | **【部署脚本】** 交互式一键安装脚本，处理环境依赖、解压 VRCX、生成解析脚本并配置轮询。 |
| `/root/vrcx/squashfs-root/` | 目录 | **【VRCX 程序】** 从 `.AppImage` 提取的绿色免 Installer 运行目录，避开 LXC 容器的 FUSE 权限问题。 |
| `~/.config/VRCX/VRCX.sqlite3` | SQLite 数据库 | **【原始数据库】** VRCX 客户端接收并存储的原始轨迹与状态日志。 |
| `/root/vrcx/daemon.log` | 日志文件 | （仅秒级轮询模式下产生）记录后台守护进程的运行与异常日志。 |

---

## 🚀 快速开始与自动化部署

在全新的 Debian 12 CT 容器中运行以下命令即可启动交互式安装面板：

```bash
# 1. 下载或创建部署脚本
nano deploy_vrcx.sh

# 2. 赋予执行权限并运行
chmod +x deploy_vrcx.sh && ./deploy_vrcx.sh
```

### 🛠️ 交互式面板配置项说明

运行脚本后将弹出控制台配置界面，按提示输入参数（直接回车使用默认值）：

- **目标 User ID (TARGET_USER_ID)**：需要监控的 VRChat 主账号 ID，格式为 `usr_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`。
- **RDP 账号 / 密码**：用于登录 XFCE 图形界面的远程桌面凭据，默认 `admin / password`。
- **轮询频率**：自定义数据刷新的间隔，支持选择 **分钟 / 小时 / 秒**，并指定具体数值，例如每 `5` 分钟刷新一次。

---

## 💻 首次运行与图形桌面 (GUI) 操作指南

由于 VRCX 是基于 Electron / GUI 的客户端应用，首次部署完成后必须通过远程桌面进入图形界面登录小号并初始化配置。

### 1. 远程桌面 (RDP) 连接

- 打开任意 RDP 客户端（如 Windows 自带的 `mstsc` 或 Mac 的 Microsoft Remote Desktop）。
- 输入 LXC 容器的 IP 地址进行连接。
- 使用在部署面板中设定的 RDP 账号与密码登录 XFCE 桌面。

### 2. 启动并登录 VRCX

在桌面左上角打开 `Applications -> Terminal`，输入以下命令启动 VRCX：

```bash
/root/vrcx/squashfs-root/vrcx --no-sandbox
```

> 追加 `--no-sandbox` 参数是为了防止 Linux 容器内的沙盒权限冲突导致无法打开界面。

### 3. 配置账号与后台静默运行

1. **登录小号**：使用你的 VRChat 监听小号登录 VRCX，建议勾选“记住密码 / 自动登录”。
2. **确认好友**：确保该小号已与需要监控的目标主账号互为好友，否则无法捕获其真实在线与房间状态。
3. **设置托盘与自启**：进入 VRCX 顶部的 `Settings` 设置界面：
   - 勾选 `Start Minimized / Close to Tray`（最小化到系统托盘 / 关闭主窗口时自动隐藏至后台）。
   - 勾选 `Auto-Start on Login`（系统登录时自动启动 VRCX）。
4. **后置处理**：完成上述配置后，可直接关闭 RDP 远程桌面连接。VRCX 将在图形会话后台持续静默运行并写入日志。

---

## 🤖 容器重启无人值守（自动登录桌面与后台自启）

为了避免 PVE 宿主机或 LXC 容器重启后需要手动重新连 RDP 桌面，可以通过以下配置实现开机自动进入桌面并后台拉起 VRCX。

### 1. 配置 LightDM 桌面环境自动登录 (Auto-login)

修改 LightDM 显示管理器配置文件：

```bash
nano /etc/lightdm/lightdm.conf
```

在 `[Seat:*]` 段落中找到并修改以下两行（去掉开头的 `#` 注释号，并将用户名替换为你设置的 RDP 用户，例如 `admin`）：

```ini
[Seat:*]
autologin-user=admin
autologin-user-timeout=0
```

### 2. 添加 VRCX 开机图形桌面自启动项

将 VRCX 的启动脚本加入 XFCE 桌面环境的 autostart 自动化目录中：

```bash
mkdir -p ~/.config/autostart
cat << 'EOF' > ~/.config/autostart/vrcx.desktop
[Desktop Entry]
Type=Application
Name=VRCX AutoStart
Exec=/root/vrcx/squashfs-root/vrcx --no-sandbox
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
```

配置完成后，无论何时重启 LXC 容器，系统都会自动静默登录桌面并后台运行 VRCX，实现真正的无人值守抓取。

---

## 📊 导出数据格式说明 (data.json)

解析脚本生成的 JSON 数据位于 `/root/vrcx_data/data.json`，按日期降序排列，时间戳已自动转换为北京时间（UTC+8）。结构示例：

```json
[
  {
    "date": "2026-08-17",
    "timeline": [
      {
        "event_type": "status",
        "time": "02:30",
        "action": "上线"
      },
      {
        "event_type": "world_change",
        "time": "02:30",
        "world": "窓外の雨音",
        "duration": "24分钟"
      },
      {
        "event_type": "world_change",
        "time": "02:54",
        "world": "私人房间 (Private Instance)",
        "duration": "1小时15分钟"
      },
      {
        "event_type": "status",
        "time": "04:09",
        "action": "下线"
      }
    ]
  }
]
```

### 字段说明

| 字段 | 类型 | 说明 |
| :--- | :--- | :--- |
| `date` | string | 记录日期，格式 `YYYY-MM-DD` |
| `timeline` | array | 当天的轨迹事件列表，按时间升序排列 |
| `event_type` | string | 事件类型：`status`（上线/下线）或 `world_change`（切换房间） |
| `time` | string | 事件发生时间，北京时间 `HH:MM` |
| `action` | string | 当 `event_type` 为 `status` 时出现，值为 `上线` 或 `下线` |
| `world` | string | 当 `event_type` 为 `world_change` 时出现，表示房间名称 |
| `duration` | string | 当 `event_type` 为 `world_change` 时出现，表示在该房间停留时长（从进入该房间到离开/下线） |

---

## ⚙️ 架构匹配与更新机制

- **架构自适应**：脚本通过 `uname -m` 自动检测宿主机 CPU 架构（`x86_64` / `aarch64`），并自动调用 GitHub API 匹配下载对应的 AppImage 包（`x64` 或 `arm64`）。
- **版本保持最新**：通过动态解析 `vrcx-team/VRCX` 仓库的 `latest` Release 资产列表，摆脱了硬编码固定版本号的限制，确保每次安装都是官方最新版。
- **数据轮询机制**：
  - **分钟 / 小时级轮询**：由 Linux 原生 `crontab` 计划任务定时调度运行，资源占用极低。
  - **秒级轮询**：由后台 Python 守护进程（Daemon）死循环调度，并自动写入系统开机自启。

---

## 🧪 手动部署补充说明

如果自动化脚本不可用，可参考以下核心步骤手动完成部署：

### 1. 安装系统依赖

```bash
apt update && apt upgrade -y
apt install -y wget curl unzip xfce4 xrdp lightdm python3 python3-pip sqlite3 jq
```

### 2. 下载并提取 VRCX AppImage

```bash
# 示例：自动获取最新版下载地址
LATEST_URL=$(curl -s https://api.github.com/repos/vrcx-team/VRCX/releases/latest | jq -r '.assets[] | select(.name | test("x86_64.*AppImage$")) | .browser_download_url')
wget -O /root/vrcx/VRCX.AppImage "$LATEST_URL"
chmod +x /root/vrcx/VRCX.AppImage
cd /root/vrcx
./VRCX.AppImage --appimage-extract
mv squashfs-root /root/vrcx/squashfs-root
```

### 3. 配置解析脚本与计划任务

- 将 `export_daily.py` 放置到 `/root/vrcx/export_daily.py`。
- 添加执行权限：`chmod +x /root/vrcx/export_daily.py`。
- 配置 crontab（例如每 5 分钟）：

```bash
crontab -e
```

添加：

```cron
*/5 * * * * /usr/bin/python3 /root/vrcx/export_daily.py >> /root/vrcx/daemon.log 2>&1
```

---

## ✅ 验证与测试

部署完成后，可通过以下方式确认系统正常工作：

```bash
# 1. 手动运行一次解析脚本，观察输出与错误
/usr/bin/python3 /root/vrcx/export_daily.py

# 2. 查看导出的 JSON 数据
cat /root/vrcx_data/data.json | jq .

# 3. 查看 VRCX 是否已成功记录目标账号数据
sqlite3 ~/.config/VRCX/VRCX.sqlite3 "SELECT * FROM ...;"  # 具体表名请参考 VRCX 数据库结构

# 4. 检查 cron 计划任务是否已添加
crontab -l

# 5. 若使用秒级轮询，查看守护进程日志
tail -f /root/vrcx/daemon.log
```

---

## ❓ 常见问题 (FAQ)

### Q1：为什么启动 VRCX 必须加 `--no-sandbox`？

因为 LXC 容器默认权限不足，Electron 的 Chromium 沙盒机制会阻止程序正常启动，添加 `--no-sandbox` 可以绕过该限制。

### Q2：无法连接 RDP 远程桌面？

- 检查容器内 `xrdp` 服务是否运行：`systemctl status xrdp`
- 确保防火墙放行 3389 端口：`ufw allow 3389`
- 确认使用的用户名密码与部署时设置一致。

### Q3：重启后桌面没有自动登录？

- 检查 `/etc/lightdm/lightdm.conf` 中的 `autologin-user` 是否与你的 RDP 用户名一致。
- 确认 LightDM 服务已启用：`systemctl enable lightdm`
- 如果使用其他桌面管理器（如 GDM），路径与配置会不同，请改用对应的自动登录配置。

### Q4：`data.json` 没有生成或长时间不更新？

- 检查 cron 任务是否添加成功：`crontab -l`
- 手动运行 `/usr/bin/python3 /root/vrcx/export_daily.py` 查看报错。
- 检查 VRCX 是否已正确登录小号并处于运行状态。
- 确保系统时区为北京时间：`timedatectl set-timezone Asia/Shanghai`。

### Q5：VRCX 数据库中找不到目标账号信息？

- 确认监听小号已与目标主账号互为好友。
- 检查 VRCX 是否在后台正常接收数据，可尝试在 VRCX 界面中手动刷新。
- 确认目标主账号的 User ID 填写正确。

### Q6：如何修改轮询频率？

- 若为 cron 方式：重新运行 `deploy_vrcx.sh` 或手动编辑 `crontab -e`。
- 若为秒级守护进程：停止当前 daemon，修改脚本中的轮询间隔，重新启动。

---

## 🔒 安全与隐私建议

1. **不要将小号凭证、RDP 密码、目标 User ID 硬编码到公开仓库中。**
2. 建议使用 `.gitignore` 忽略 `data.json`、`daemon.log`、`VRCX.sqlite3` 等敏感数据。
3. 如果必须远程访问 RDP，请使用 SSH 隧道或 VPN，避免直接暴露 3389 端口到公网。
4. 定期清理日志文件，避免占用过多磁盘空间。

---

## 🧹 停止与卸载

### 停止自动抓取

- **cron 方式**：删除对应的计划任务

  ```bash
  crontab -e
  # 删除或注释掉 export_daily.py 那一行
  ```

- **守护进程方式**：找到并终止进程

  ```bash
  pkill -f export_daily.py
  systemctl disable <daemon服务名>  # 如果配置了 systemd
  ```

### 完全卸载

```bash
# 1. 停止所有相关进程
pkill -f vrcx
pkill -f export_daily.py

# 2. 删除 VRCX 程序目录、脚本及数据
rm -rf /root/vrcx
rm -rf /root/vrcx_data
rm -f ~/.config/autostart/vrcx.desktop
rm -rf ~/.config/VRCX

# 3. 移除系统依赖（可选）
apt remove --purge -y xrdp xfce4 lightdm
apt autoremove -y
```

---

## 🔄 更新 VRCX 版本

当 VRCX 官方发布新版本时，有两种更新方式：

### 方法一：重新运行部署脚本

```bash
cd /root/vrcx
./deploy_vrcx.sh
```

脚本会自动下载并解压最新版 AppImage 覆盖旧版本。

### 方法二：手动更新

```bash
LATEST_URL=$(curl -s https://api.github.com/repos/vrcx-team/VRCX/releases/latest | jq -r '.assets[] | select(.name | test("x86_64.*AppImage$")) | .browser_download_url')
wget -O /root/vrcx/VRCX.AppImage "$LATEST_URL"
chmod +x /root/vrcx/VRCX.AppImage
cd /root/vrcx
./VRCX.AppImage --appimage-extract
rm -rf /root/vrcx/squashfs-root
mv /root/vrcx/squashfs-root /root/vrcx/squashfs-root.new
rm -rf /root/vrcx/squashfs-root
mv /root/vrcx/squashfs-root.new /root/vrcx/squashfs-root
```

更新后重启 VRCX 即可。

---

## 📜 许可证

本项目仅供学习与个人监控用途，请遵守 VRChat 服务条款及相关法律法规。使用本工具产生的一切风险由使用者自行承担。

---

## 🙏 致谢

- [VRCX](https://github.com/vrcx-team/VRCX) —— VRChat 第三方客户端，提供完整数据接口与数据库。
- PVE / Debian / XFCE / LightDM —— 提供稳定的容器化运行环境与图形桌面支持。
