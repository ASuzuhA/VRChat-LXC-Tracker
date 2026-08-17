#!/bin/bash

# =========================================================
# VRCX 数据解析与 JSON 提取全自动部署脚本 (Debian 12 增强完整版)
# 支持：全参数 SQLite 解析 (地图/上下线/状态/签名/模型/Bio) + 自动环境构建
# =========================================================

set -e

# 预设默认值
DEFAULT_TARGET_ID="usr_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
DEFAULT_RDP_USER="root"
DEFAULT_RDP_PASS="password"
DEFAULT_TIMEZONE="Asia/Shanghai"
DEFAULT_INTERVAL_TYPE="1" # 默认: 分钟
DEFAULT_INTERVAL_VAL="10" # 默认: 10分钟

# ----------------- 交互式配置面板 -----------------
clear
echo "========================================================="
echo "        🚀 VRCX 自动化部署与多维 JSON 数据提取面板        "
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
echo "[1/4] 正在配置系统基础环境、GUI 依赖与时区..."
ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime || timedatectl set-timezone "$TIMEZONE" || true

apt update && apt upgrade -y
apt install -y xfce4 xfce4-terminal xrdp sqlite3 python3 python3-pip wget curl cron jq \
    libfuse2 libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libxkbcommon0 \
    libxcomposite1 libxdamage1 libxrandr2 libgbm1 libasound2

echo "[2/4] 正在创建 RDP 远程桌面用户..."
if ! id "$RDP_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$RDP_USER"
fi
echo "$RDP_USER:$RDP_PASS" | chpasswd
usermod -aG ssl-cert "$RDP_USER" || true
systemctl enable --now xrdp

echo "[3/4] 自动检测系统架构并动态抓取最新 VRCX AppImage..."
RDP_HOME=$(eval echo "~$RDP_USER")
APP_DIR="$RDP_HOME/vrcx"
mkdir -p "$APP_DIR"
cd "$APP_DIR"

if [ ! -d "$APP_DIR/squashfs-root" ]; then
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
    chown -R "$RDP_USER:$RDP_USER" "$APP_DIR"
fi

echo "[4/4] 正在生成全参数 Python JSON 解析脚本与自动定时任务..."
DATA_DIR="$RDP_HOME/vrcx_data"
mkdir -p "$DATA_DIR"
chown -R "$RDP_USER:$RDP_USER" "$DATA_DIR"

TARGET_DB_PATH="$RDP_HOME/.config/VRCX/VRCX.sqlite3"
TARGET_OUTPUT_JSON="$DATA_DIR/data.json"

cat << EOF > "$APP_DIR/export_daily.py"
import sqlite3
import json
import os
import time
import sys
from datetime import datetime, timedelta

TARGET_USER_ID = "$TARGET_USER_ID".strip().lower()
DB_PATH = "$TARGET_DB_PATH"
OUTPUT_JSON = "$TARGET_OUTPUT_JSON"

def parse_iso_dt(time_str):
    try:
        clean_time = str(time_str).split('.')[0].replace('Z', '')
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

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_feed_%';")
    tables = [row['name'] for row in cursor.fetchall()]

    events = []

    for tbl in tables:
        cursor.execute(f"SELECT * FROM {tbl} ORDER BY created_at ASC")
        rows = cursor.fetchall()

        for row in rows:
            item = dict(row)
            if TARGET_USER_ID not in str(item.get("user_id", "")).lower():
                continue

            dt_local = parse_iso_dt(item.get("created_at", ""))

            # 1. 地图 / 实例位置变动 (_feed_gps)
            if "_feed_gps" in tbl:
                world_name = item.get("world_name")
                location = str(item.get("location", ""))
                group_name = item.get("group_name") or ""
                
                if "private" in location.lower() or "hidden" in location.lower() or not world_name or world_name == "Private":
                    display_world = "私人房间 (Private Instance)"
                else:
                    display_world = str(world_name)
                    if group_name:
                        display_world += f" [群组: {group_name}]"

                events.append({
                    "dt": dt_local,
                    "event_type": "world_change",
                    "world": display_world,
                    "raw_location": location
                })

            # 2. 上下线状态 (_feed_online_offline)
            elif "_feed_online_offline" in tbl:
                evt_type = str(item.get("type", "")).lower()
                status_str = "上线" if "online" in evt_type else ("下线" if "offline" in evt_type else evt_type)
                events.append({
                    "dt": dt_local,
                    "event_type": "status_change",
                    "detail": status_str
                })

            # 3. 状态模式与签名变动 (_feed_status)
            elif "_feed_status" in tbl:
                status_mode = str(item.get("status", "")).lower()
                status_desc = item.get("status_description") or ""

                mode_map = {
                    "active": "在线 (Active)",
                    "join me": "请加入我 (Join Me)",
                    "ask me": "请询问我 (Ask Me)",
                    "busy": "请勿打扰 (Busy)"
                }
                mapped_mode = mode_map.get(status_mode, status_mode)
                
                action_text = f"切换状态模式为 [{mapped_mode}]"
                if status_desc:
                    action_text += f" - 签名: \"{status_desc}\""

                events.append({
                    "dt": dt_local,
                    "event_type": "status_change",
                    "detail": action_text
                })

            # 4. 模型 / Avatar 变更 (_feed_avatar)
            elif "_feed_avatar" in tbl:
                avatar_name = item.get("avatar_name") or "未知模型"
                thumbnail = item.get("current_avatar_thumbnail_image_url") or item.get("current_avatar_image_url") or ""
                
                events.append({
                    "dt": dt_local,
                    "event_type": "avatar_change",
                    "avatar_name": str(avatar_name),
                    "thumbnail": str(thumbnail),
                    "detail": f"更换模型为 [{avatar_name}]"
                })

            # 5. Bio 个人简介修改 (_feed_bio)
            elif "_feed_bio" in tbl:
                bio_text = item.get("bio") or ""
                events.append({
                    "dt": dt_local,
                    "event_type": "bio_change",
                    "detail": f"更新个人 Bio 简介: \"{bio_text}\""
                })

    conn.close()

    events.sort(key=lambda x: x["dt"])

    grouped_data = {}
    for i in range(len(events)):
        curr = events[i]
        dt = curr["dt"]
        date_key = dt.strftime("%Y-%m-%d")
        time_hm = dt.strftime("%H:%M:%S")

        if date_key not in grouped_data:
            grouped_data[date_key] = []

        if curr["event_type"] == "world_change":
            duration_str = "至今 / 停留中"
            for j in range(i + 1, len(events)):
                if events[j]["event_type"] == "world_change":
                    next_dt = events[j]["dt"]
                    time_diff_seconds = (next_dt - dt).total_seconds()
                    duration_str = format_duration(time_diff_seconds)
                    break

            grouped_data[date_key].append({
                "time": time_hm,
                "event_type": "world_change",
                "world": curr["world"],
                "duration": duration_str
            })
        elif curr["event_type"] == "avatar_change":
            grouped_data[date_key].append({
                "time": time_hm,
                "event_type": "avatar_change",
                "avatar_name": curr["avatar_name"],
                "thumbnail": curr["thumbnail"],
                "action": curr["detail"]
            })
        else:
            grouped_data[date_key].append({
                "time": time_hm,
                "event_type": curr["event_type"],
                "action": curr["detail"]
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

    print(f"[{datetime.now()}] 多维度轨迹 JSON 刷新成功 -> {OUTPUT_JSON}")

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

chown "$RDP_USER:$RDP_USER" "$APP_DIR/export_daily.py"

# 清理现有的定时任务和后台进程
crontab -l 2>/dev/null | grep -Fv "export_daily.py" | crontab - || true
pkill -f "export_daily.py" || true

# 配置轮询与启动模式
if [ "$INTERVAL_TYPE" == "3" ]; then
    nohup python3 "$APP_DIR/export_daily.py" --loop "$INTERVAL_VAL" > "$APP_DIR/daemon.log" 2>&1 &
    (crontab -l 2>/dev/null ; echo "@reboot nohup /usr/bin/python3 $APP_DIR/export_daily.py --loop $INTERVAL_VAL > $APP_DIR/daemon.log 2>&1 &") | crontab -
else
    if [ "$INTERVAL_TYPE" == "2" ]; then
        CRON_EXPR="0 */$INTERVAL_VAL * * *"
    else
        CRON_EXPR="*/$INTERVAL_VAL * * * *"
    fi
    CRON_JOB="$CRON_EXPR /usr/bin/python3 $APP_DIR/export_daily.py > /dev/null 2>&1"
    (crontab -l 2>/dev/null ; echo "$CRON_JOB") | crontab -
fi

echo "========================================================="
echo " 🎉 部署完成！"
echo " "
echo " 📄 生成的轨迹 JSON 文件路径:"
echo "    $TARGET_OUTPUT_JSON"
echo " "
echo " ⏱️ 当前设置的轮询频率: $ECHO_FREQ"
echo " ⚙️ 登录与运行步骤:"
echo " 1. 使用 RDP 连接 IP，账号: $RDP_USER / 密码: $RDP_PASS"
echo " 2. 打开 Terminal 运行:"
echo "    $APP_DIR/squashfs-root/vrcx --no-sandbox"
echo " 3. 登录账号后，全量动态将按 [$ECHO_FREQ] 自动写入 JSON！"
echo "========================================================="
