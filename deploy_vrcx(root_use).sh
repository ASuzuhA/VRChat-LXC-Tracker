#!/bin/bash

# =========================================================
# VRCX 数据解析与 JSON 提取全自动部署脚本 (Debian 12 CT)
# 运行身份：root 专用版
# 支持：交互式参数面板 + 架构自适应 + root 开机自动登录桌面自启
# =========================================================

set -e

# 确保脚本以 root 身份运行
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 错误：此脚本必须以 root 用户身份运行！"
    exit 1
fi

# 预设默认值
DEFAULT_TARGET_ID="usr_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
DEFAULT_RDP_PASS="password"
DEFAULT_TIMEZONE="Asia/Shanghai"
DEFAULT_INTERVAL_TYPE="1" # 默认: 分钟
DEFAULT_INTERVAL_VAL="10" # 默认: 10分钟

# ----------------- 交互式配置面板 -----------------
clear
echo "========================================================="
echo "   🚀 VRCX 自动化部署与 JSON 数据提取配置面板 (root 版)"
echo "========================================================="
echo ""
echo "💡 提示：按 [Enter] 回车可直接使用 [括号] 中的默认值"
echo ""

# 1. 配置监控目标用户 ID
read -p "1. 请输入要监控的 VRChat 用户 ID [$DEFAULT_TARGET_ID]: " INPUT_TARGET_ID
TARGET_USER_ID=${INPUT_TARGET_ID:-$DEFAULT_TARGET_ID}

# 2. 配置 root 远程桌面密码
read -p "2. 请输入 root 用户的远程桌面 (RDP) 登录密码 [$DEFAULT_RDP_PASS]: " INPUT_RDP_PASS
RDP_PASS=${INPUT_RDP_PASS:-$DEFAULT_RDP_PASS}

# 3. 配置数据刷新轮询频率
echo ""
echo "3. 请选择数据自动刷新的频率类型："
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
echo " 👤 当前运行身份    : root"
echo " 🎯 监控目标 User ID : $TARGET_USER_ID"
echo " 🔑 root RDP 远程密码: $RDP_PASS"
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
echo "[1/5] 正在配置系统基础环境与 root 密码..."
timedatectl set-timezone "$TIMEZONE" || true
apt update && apt upgrade -y
apt install -y xfce4 xfce4-terminal xrdp lightdm sqlite3 python3 python3-pip wget curl cron jq

# 修改 root 的系统/RDP 密码
echo "root:$RDP_PASS" | chpasswd
systemctl enable --now xrdp

echo "[2/5] 正在配置 LightDM 自动跳过密码直接登录 root 桌面..."
# 配置 LightDM 自动登录 root
mkdir -p /etc/lightdm
LIGHTDM_CONF="/etc/lightdm/lightdm.conf"

if [ -f "$LIGHTDM_CONF" ]; then
    sed -i 's/^#*autologin-user=.*/autologin-user=root/' "$LIGHTDM_CONF"
    sed -i 's/^#*autologin-user-timeout=.*/autologin-user-timeout=0/' "$LIGHTDM_CONF"
else
    cat << 'EOF' > "$LIGHTDM_CONF"
[Seat:*]
autologin-user=root
autologin-user-timeout=0
EOF
fi

# 解除 pam 针对 root 自动登录的限制
PAM_FILE="/etc/pam.d/lightdm-autologin"
if [ -f "$PAM_FILE" ]; then
    sed -i 's/.*user != root.*/# &' "$PAM_FILE"
fi

echo "[3/5] 自动检测系统架构并抓取最新的 VRCX AppImage..."
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

echo "[4/5] 设置 root 桌面登录自动启动 VRCX..."
mkdir -p /root/.config/autostart
cat << 'EOF' > /root/.config/autostart/vrcx.desktop
[Desktop Entry]
Type=Application
Name=VRCX AutoStart
Exec=/root/vrcx/squashfs-root/vrcx --no-sandbox
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
chmod +x /root/.config/autostart/vrcx.desktop

echo "[5/5] 正在生成 Python JSON 轨迹解析脚本与定时任务..."
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

sed -i "s/YOUR_TARGET_USER_ID_HERE/$TARGET_USER_ID/g" /root/vrcx/export_daily.py

# 清理定时任务
crontab -l 2>/dev/null | grep -Fv "/root/vrcx/export_daily.py" | crontab - || true
pkill -f "export_daily.py" || true

if [ "$INTERVAL_TYPE" == "3" ]; then
    nohup python3 /root/vrcx/export_daily.py --loop "$INTERVAL_VAL" > /root/vrcx/daemon.log 2>&1 &
    sed -i -e '$i \nohup python3 /root/vrcx/export_daily.py --loop '$INTERVAL_VAL' > /root/vrcx/daemon.log 2>&1 &\n' /etc/rc.local 2>/dev/null || true
else
    if [ "$INTERVAL_TYPE" == "2" ]; then
        CRON_EXPR="0 */$INTERVAL_VAL * * *"
    else
        CRON_EXPR="*/$INTERVAL_VAL * * * *"
    fi
    CRON_JOB="$CRON_EXPR python3 /root/vrcx/export_daily.py"
    (crontab -l 2>/dev/null ; echo "$CRON_JOB") | crontab -
fi

echo "========================================================="
echo " 🎉 root 版全自动部署完成！"
echo " "
echo " 📄 生成的轨迹 JSON 文件路径:"
echo "    /root/vrcx_data/data.json"
echo " "
echo " 🤖 无人值守状态:"
echo "    系统已自动配置 LightDM 免密自动登录 root 桌面，"
echo "    并在登录后自动在后台启动 VRCX！"
echo " "
echo " ⚙️ 首次初始化步骤:"
echo " 1. 使用 RDP 连接 IP (账号: root / 密码: $RDP_PASS)"
echo " 2. 此时 VRCX 应该已经自动弹出了，使用监控小号登录 VRCX 即可。"
echo " 3. 以后哪怕重启容器，也无需连接 RDP，系统会自动登录并在后台挂着 VRCX。"
echo "========================================================="
