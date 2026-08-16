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
