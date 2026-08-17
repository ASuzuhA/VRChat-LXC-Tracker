#!/bin/bash
# ==============================================================================
# VRChat Track Logger 一键纯环境部署脚本
# 作用：安装系统依赖、自动识别 CPU 架构并下载解压 VRCX，生成底层运行环境
# 说明：仅需在全新的容器/系统上运行一次！
# ==============================================================================

set -e

echo "=================================================="
echo "   VRChat Track Logger 环境部署 (仅首次运行)"
echo "=================================================="

# 默认安装绝对路径
DEFAULT_INSTALL_DIR="$HOME"
read -p "请输入部署根目录绝对路径 [默认: $DEFAULT_INSTALL_DIR]: " INSTALL_DIR
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
INSTALL_DIR=$(eval echo "$INSTALL_DIR")

APP_DIR="$INSTALL_DIR/vrcx"
DATA_DIR="$INSTALL_DIR/vrcx_data"
mkdir -p "$APP_DIR" "$DATA_DIR"

echo -e "\n⏳ 1. 正在更新系统软件包并安装基础依赖..."
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y wget curl unzip xfce4 xrdp python3 python3-pip sqlite3 jq tzdata

# 设置系统时区为 Asia/Shanghai (UTC+8)
timedatectl set-timezone Asia/Shanghai || true
systemctl enable --now xrdp

echo -e "\n🔍 2. 识别 CPU 架构并自动获取最新版 VRCX AppImage..."
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    REGEX="x86_64.*AppImage$"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    REGEX="arm64.*AppImage$"
else
    echo "❌ 暂不支持的系统架构: $ARCH"
    exit 1
fi

LATEST_URL=$(curl -s https://api.github.com/repos/vrcx-team/VRCX/releases/latest | jq -r ".assets[] | select(.name | test(\"$REGEX\")) | .browser_download_url")

if [ -z "$LATEST_URL" ] || [ "$LATEST_URL" = "null" ]; then
    echo "❌ 无法获取 VRCX 下载地址，请检查网络或 GitHub API 限制。"
    exit 1
fi

cd "$APP_DIR"
wget -O VRCX.AppImage "$LATEST_URL"
chmod +x VRCX.AppImage

echo "📦 正在解压 VRCX 免安装绿色运行环境..."
rm -rf squashfs-root
./VRCX.AppImage --appimage-extract

# 3. 初始化默认配置文件 (config.json)
if [ ! -f "$APP_DIR/config.json" ]; then
    cat <<JSON > "$APP_DIR/config.json"
{
  "target_user_id": "",
  "cron_minutes": 5,
  "log_status": true,
  "log_world": true,
  "log_avatar": true,
  "log_bio": true
}
JSON
fi

# 4. 生成底层的 Python 解析核心 (export_daily.py)
cat << 'PYEOF' > "$APP_DIR/export_daily.py"
import os
import sys
import json
import sqlite3
from datetime import datetime, timezone, timedelta

APP_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(APP_DIR, "config.json")
DATA_DIR = os.path.join(os.path.dirname(APP_DIR), "vrcx_data")
OUTPUT_JSON = os.path.join(DATA_DIR, "data.json")

HOME_DIR = os.path.expanduser("~")
DB_PATH = os.path.join(HOME_DIR, ".config", "VRCX", "VRCX.sqlite3")

def load_config():
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def get_beijing_time(utc_str):
    try:
        dt = datetime.strptime(utc_str, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone(timedelta(hours=8)))
    except Exception:
        return None

def process_data():
    cfg = load_config()
    target_user_id = cfg.get("target_user_id", "").strip()

    if not target_user_id or not os.path.exists(DB_PATH):
        return

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    events_by_date = {}

    # 1. 上下线与状态模式
    if cfg.get("log_status", True):
        cursor.execute(
            "SELECT created_at, type, status, status_description FROM user_status_history WHERE user_id = ? ORDER BY created_at ASC",
            (target_user_id,)
        )
        for row in cursor.fetchall():
            dt = get_beijing_time(row[0])
            if not dt: continue
            date_str = dt.strftime("%Y-%m-%d")
            time_str = dt.strftime("%H:%M:%S")

            status_type = row[1]
            desc = row[3] or ""
            action_text = f"状态变动: {status_type}"
            if desc: action_text += f" - 签名: \"{desc}\""

            events_by_date.setdefault(date_str, []).append({
                "raw_time": dt,
                "time": time_str,
                "event_type": "status_change",
                "action": action_text
            })

    # 2. 房间变动
    if cfg.get("log_world", True):
        cursor.execute(
            "SELECT created_at, world_name, duration FROM location_history WHERE user_id = ? ORDER BY created_at ASC",
            (target_user_id,)
        )
        for row in cursor.fetchall():
            dt = get_beijing_time(row[0])
            if not dt: continue
            date_str = dt.strftime("%Y-%m-%d")
            time_str = dt.strftime("%H:%M:%S")

            duration_sec = row[2] or 0
            dur_str = f"{duration_sec // 60}分钟" if duration_sec >= 60 else f"{duration_sec}秒"

            events_by_date.setdefault(date_str, []).append({
                "raw_time": dt,
                "time": time_str,
                "event_type": "world_change",
                "world": row[1] or "未知房间",
                "duration": dur_str
            })

    # 3. Avatar 模型更换
    if cfg.get("log_avatar", True):
        cursor.execute(
            "SELECT created_at, avatar_name, thumbnail_url FROM avatar_history WHERE user_id = ? ORDER BY created_at ASC",
            (target_user_id,)
        )
        for row in cursor.fetchall():
            dt = get_beijing_time(row[0])
            if not dt: continue
            date_str = dt.strftime("%Y-%m-%d")
            time_str = dt.strftime("%H:%M:%S")

            events_by_date.setdefault(date_str, []).append({
                "raw_time": dt,
                "time": time_str,
                "event_type": "avatar_change",
                "avatar_name": row[1] or "未知 Avatar",
                "thumbnail": row[2] or "",
                "action": f"更换模型为 [{row[1]}]"
            })

    # 4. Bio 修改
    if cfg.get("log_bio", True):
        cursor.execute(
            "SELECT created_at, bio FROM bio_history WHERE user_id = ? ORDER BY created_at ASC",
            (target_user_id,)
        )
        for row in cursor.fetchall():
            dt = get_beijing_time(row[0])
            if not dt: continue
            date_str = dt.strftime("%Y-%m-%d")
            time_str = dt.strftime("%H:%M:%S")

            events_by_date.setdefault(date_str, []).append({
                "raw_time": dt,
                "time": time_str,
                "event_type": "bio_change",
                "action": f"修改个人简介 Bio: {row[1]}"
            })

    conn.close()

    final_output = []
    for date_key in sorted(events_by_date.keys(), reverse=True):
        day_events = sorted(events_by_date[date_key], key=lambda x: x["raw_time"])
        for e in day_events:
            del e["raw_time"]

        final_output.append({
            "date": date_key,
            "timeline": day_events
        })

    os.makedirs(DATA_DIR, exist_ok=True)
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(final_output, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    process_data()
PYEOF

echo "✅ 基础环境搭建完成！即将自动调用交互式配置脚本..."
sleep 1

# 首次自动启动配置脚本
chmod +x "$APP_DIR/config_logger.sh" 2>/dev/null || true
if [ -f "$APP_DIR/config_logger.sh" ]; then
    bash "$APP_DIR/config_logger.sh"
fi
