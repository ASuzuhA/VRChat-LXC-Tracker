#!/bin/bash

# =========================================================
# VRCX 数据解析与 JSON 提取全自动部署脚本 (Debian 12 CT)
# 支持：交互式参数面板（含轮询频率设置） + 架构自动匹配下载
# =========================================================

set -e

# 预设默认值
DEFAULT_TARGET_ID="usr_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
DEFAULT_RDP_USER="admin"
DEFAULT_RDP_PASS="password"
DEFAULT_TIMEZONE="Asia/Shanghai"
DEFAULT_INTERVAL_TYPE="1" # 默认: 分钟
DEFAULT_INTERVAL_VAL="10" # 默认: 10分钟

# ----------------- 交互式配置面板 -----------------
clear
echo "========================================================="
echo "       🚀 VRCX 自动化部署与 JSON 数据提取配置面板        "
echo "========================================================="
echo ""
echo "💡 提示：按 [Enter] 回车可直接使用 [括号] 中的默认值"
echo ""

# 1. 配置监控目标用户 ID
read -p "1. 请输入要监控的 VRChat 用户 ID [$DEFAULT_TARGET_ID]: " INPUT_TARGET_ID
TARGET_USER_ID=${INPUT_TARGET_ID:-$DEFAULT_TARGET_ID}

# 2. 配置 RDP 用户名与密码
read -p "2. 请输入远程桌面 (RDP) 登录账号 [$DEFAULT_RDP_USER]: " INPUT_RDP_USER
RDP_USER=${INPUT_RDP_USER:-$DEFAULT_RDP_USER}

read -p "3. 请输入远程桌面 (RDP) 登录密码 [$DEFAULT_RDP_PASS]: " INPUT_RDP_PASS
RDP_PASS=${INPUT_RDP_PASS:-$DEFAULT_RDP_PASS}

# 3. 配置数据刷新轮询频率
echo ""
echo "4. 请选择数据自动刷新的频率类型："
echo "   [1] 按分钟 (Minutes) —— 推荐"
echo "   [2] 按小时 (Hours)"
echo "   [3] 按秒 (Seconds)"
read -p "   请选择 [1-3] (默认 $DEFAULT_INTERVAL_TYPE): " INPUT_TYPE
INTERVAL_TYPE=${INPUT_TYPE:-$DEFAULT_INTERVAL_TYPE}

read -p "   请输入具体数值 (例如: 填 5 代表每 5 分钟/小时/秒) [$DEFAULT_INTERVAL_VAL]: " INPUT_VAL
INTERVAL_VAL=${INPUT_VAL:-$DEFAULT_INTERVAL_VAL}

TIMEZONE="$DEFAULT_TIMEZONE"

echo ""
echo "----------------- 当前生效的配置 -----------------"
echo " 🎯 监控目标 User ID : $TARGET_USER_ID"
echo " 👤 RDP 远程账号    : $RDP_USER"
echo " 🔑 RDP 远程密码    : $RDP_PASS"
case "$INTERVAL_TYPE" in
    1) ECHO_FREQ="每 $INTERVAL_VAL 分钟" ;;
    2) ECHO_FREQ="每 $INTERVAL_VAL 小时" ;;
    3) ECHO_FREQ="每 $INTERVAL_VAL 秒" ;;
    *) ECHO_FREQ="每 $INTERVAL_VAL 分钟" ;;
esac
echo " ⏱️ 数据轮询频率    : $ECHO_FREQ"
echo "--------------------------------------------------"
echo ""
read -p "确认以上配置并开始部署？(Y/n): " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
    echo "❌ 已取消部署。"
    exit 0
fi

echo ""
echo "[1/4] 正在配置系统基础环境与时区..."
timedatectl set-timezone "$TIMEZONE" || true
apt update && apt upgrade -y
apt install -y xfce4 xfce4-terminal xrdp sqlite3 python3 python3-pip wget curl cron jq

echo "[2/4] 正在创建 RDP 远程桌面用户..."
if ! id "$RDP_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$RDP_USER"
fi
echo "$RDP_USER:$RDP_PASS" | chpasswd
systemctl enable --now xrdp

echo "[3/4] 自动检测系统架构并动态抓取最新 VRCX AppImage..."
mkdir -p /root/vrcx
cd /root/vrcx

if [ ! -d "/root/vrcx/squashfs-root" ]; then
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64) KEYWORD="x64" ;;
        aarch64|arm64) KEYWORD="arm64" ;;
        *) KEYWORD="x64" ;;
    esac
    echo "识别到系统 CPU 架构: $ARCH ，检索关键字 [$KEYWORD]..."

    LATEST_URL=$(curl -s https://api.github.com/repos/vrcx-team/VRCX/releases/latest \
        | jq -r ".assets[].browser_download_url" \
        | grep -i "$KEYWORD" \
        | grep -i "\.AppImage$" \
        | head -n 1)

    if [ -z "$LATEST_URL" ] || [ "$LATEST_URL" == "null" ]; then
        echo "⚠️ 未能通过架构关键字精准匹配，获取通用 AppImage..."
        LATEST_URL=$(curl -s https://api.github.com/repos/vrcx-team/VRCX/releases/latest \
            | jq -r ".assets[].browser_download_url" \
            | grep -i "\.AppImage$" \
            | head -n 1)
    fi

    echo "正在下载最新版本: $LATEST_URL"
    wget -q --show-progress "$LATEST_URL" -O VRCX.AppImage

    chmod +x VRCX.AppImage
    ./VRCX.AppImage --appimage-extract
    rm -f VRCX.AppImage
fi

echo "[4/4] 正在生成 Python JSON 轨迹解析脚本与自动定时任务..."
mkdir -p /root/vrcx_data

cat << 'EOF' > /root/vrcx/export_daily.py
import sqlite3
import json
import os
import time
import sys
from datetime import datetime, timedelta

TARGET_USER_ID = "YOUR_TARGET_USER_ID_HERE".strip().lower()
DB_PATH = os.path.expanduser("~/.config/VRCX/VRCX.sqlite3")
OUTPUT_JSON = os.path.expanduser("~/vrcx_data/data.json")

def parse_iso_dt(time_str):
    try:
        clean_time = time_str.split('.')[0].replace('Z', '')
        dt = datetime.strptime(clean_time, "%Y-%m-%dT%H:%M:%S")
        return dt + timedelta(hours=8)
    except Exception:
        return datetime.now()

def format_duration(seconds):
    if seconds < 60:
        return "< 1分钟"
    minutes = int(seconds // 60)
    if minutes < 60:
        return f"{minutes}分钟"
    hours = minutes // 60
    rem_mins = minutes % 60
    if rem_mins == 0:
        return f"{hours}小时"
    return f"{hours}小时{rem_mins}分钟"

def get_full_activity_data():
    if not os.path.exists(DB_PATH):
        print(f"[{datetime.now()}] 暂未找到数据库文件 {DB_PATH}，请确保 VRCX 已运行并登录。")
        return {}

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_feed_gps';")
    gps_tables = cursor.fetchall()
    
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_feed_online_offline';")
    status_tables = cursor.fetchall()

    if not gps_tables:
        conn.close()
        return {}

    gps_table = gps_tables[0]['name']
    status_table = status_tables[0]['name'] if status_tables else None

    cursor.execute(f"SELECT created_at, user_id, location, world_name FROM {gps_table} ORDER BY created_at ASC")
    gps_rows = cursor.fetchall()

    status_rows = []
    if status_table:
        cursor.execute(f"SELECT created_at, user_id, type FROM {status_table} ORDER BY created_at ASC")
        status_rows = cursor.fetchall()

    conn.close()

    events = []

    for row in gps_rows:
        item = dict(row)
        if TARGET_USER_ID not in str(item.get("user_id", "")).lower():
            continue
        dt_local = parse_iso_dt(str(item.get("created_at", "")))
        
        world_name = item.get("world_name")
        location = str(item.get("location", ""))
        if "private" in location.lower() or "hidden" in location.lower() or not world_name or world_name == "Private":
            display_world = "私人房间 (Private Instance)"
        else:
            display_world = str(world_name)

        events.append({
            "dt": dt_local,
            "type": "world",
            "world": display_world
        })

    for row in status_rows:
        item = dict(row)
        if TARGET_USER_ID not in str(item.get("user_id", "")).lower():
            continue
        dt_local = parse_iso_dt(str(item.get("created_at", "")))
        event_type = str(item.get("type", "")).lower()
        
        if "online" in event_type or "offline" in event_type:
            events.append({
                "dt": dt_local,
                "type": "status",
                "status": "上线" if "online" in event_type else "下线"
            })

    events.sort(key=lambda x: x["dt"])

    grouped_data = {}

    for i in range(len(events)):
        curr = events[i]
        dt = curr["dt"]
        date_key = dt.strftime("%Y-%m-%d")
        time_hm = dt.strftime("%H:%M")

        if date_key not in grouped_data:
            grouped_data[date_key] = []

        if curr["type"] == "status":
            grouped_data[date_key].append({
                "event_type": "status",
                "time": time_hm,
                "action": curr["status"]
            })
        elif curr["type"] == "world":
            duration_str = "至今 / 停留中"
            if i + 1 < len(events):
                next_dt = events[i + 1]["dt"]
                time_diff_seconds = (next_dt - dt).total_seconds()
                duration_str = format_duration(time_diff_seconds)

            grouped_data[date_key].append({
                "event_type": "world_change",
                "time": time_hm,
                "world": curr["world"],
                "duration": duration_str
            })

    return grouped_data

def update_site_data():
    grouped_data = get_full_activity_data()
    if not grouped_data:
        return

    os.makedirs(os.path.dirname(OUTPUT_JSON), exist_ok=True)
    
    history = []
    for date_key in sorted(grouped_data.keys(), reverse=True):
        history.append({
            "date": date_key,
            "timeline": grouped_data[date_key]
        })

    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(history, f, ensure_ascii=False, indent=2)

    print(f"[{datetime.now()}] JSON 数据刷新成功 -> {OUTPUT_JSON}")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--loop":
        sec = int(sys.argv[2]) if len(sys.argv) > 2 else 10
        print(f"开启后台守护模式，每 {sec} 秒轮询一次...")
        while True:
            update_site_data()
            time.sleep(sec)
    else:
        update_site_data()
EOF

# 将 User ID 写入 Python 脚本
sed -i "s/YOUR_TARGET_USER_ID_HERE/$TARGET_USER_ID/g" /root/vrcx/export_daily.py

# 清理现有的定时任务和后台进程
crontab -l 2>/dev/null | grep -Fv "/root/vrcx/export_daily.py" | crontab - || true
pkill -f "export_daily.py" || true

# 根据用户的频率选项来配置启动模式
if [ "$INTERVAL_TYPE" == "3" ]; then
    # 秒级轮询：使用 nohup 启动后台死循环守护进程
    nohup python3 /root/vrcx/export_daily.py --loop "$INTERVAL_VAL" > /root/vrcx/daemon.log 2>&1 &
    # 添加开机自启
    sed -i -e '$i \nohup python3 /root/vrcx/export_daily.py --loop '$INTERVAL_VAL' > /root/vrcx/daemon.log 2>&1 &\n' /etc/rc.local 2>/dev/null || true
else
    # 分钟/小时级轮询：配置原生 Crontab
    if [ "$INTERVAL_TYPE" == "2" ]; then
        # 小时级 Cron 表达式 (例如: 0 */2 * * *)
        CRON_EXPR="0 */$INTERVAL_VAL * * *"
    else
        # 分钟级 Cron 表达式 (例如: */5 * * * *)
        CRON_EXPR="*/$INTERVAL_VAL * * * *"
    fi
    CRON_JOB="$CRON_EXPR python3 /root/vrcx/export_daily.py"
    (crontab -l 2>/dev/null ; echo "$CRON_JOB") | crontab -
fi

echo "========================================================="
echo " 🎉 部署完成！"
echo " "
echo " 📄 生成的轨迹 JSON 文件路径:"
echo "    /root/vrcx_data/data.json"
echo " "
echo " ⏱️ 当前设置的轮询频率: $ECHO_FREQ"
echo " ⚙️ 登录与运行步骤:"
echo " 1. 使用 RDP 连接 IP，账号: $RDP_USER / 密码: $RDP_PASS"
echo " 2. 打开终端运行: /root/vrcx/squashfs-root/vrcx --no-sandbox"
echo " 3. 登录小号后，数据将按 [$ECHO_FREQ] 自动更新写入！"
echo "========================================================="
