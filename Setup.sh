#!/bin/bash
# ==============================================================================
# VRChat Track Logger 一键纯环境部署脚本
# 作用：安装系统依赖、获取 VRCX (预先提供多种下载/放置途径)、生成全部核心脚本
# 说明：仅需在全新的容器/系统上运行一次！
# ==============================================================================

set -e

echo "=================================================="
echo "    VRChat Track Logger 环境部署 (仅首次运行)"
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
apt install -y wget curl unzip xfce4 xrdp python3 python3-pip sqlite3 jq tzdata cron

# 设置系统时区为 Asia/Shanghai (UTC+8)
timedatectl set-timezone Asia/Shanghai || true
systemctl enable --now xrdp 2>/dev/null || true

echo -e "\n📦 2. 选择 VRCX 运行环境获取方式..."
cd "$APP_DIR"

# 获取 CPU 架构匹配正则
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    REGEX="x86_64.*AppImage$"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    REGEX="arm64.*AppImage$"
else
    REGEX=""
fi

download_success=false

while [ "$download_success" = false ]; do
    echo -e "\n请选择 VRCX 安装包获取途径："
    echo " 1) 🌐 [自动推荐] 自动检测系统架构并从 GitHub 官方 Release 获取下载"
    echo " 2) 🔗 [自定义链接] 输入自定义/镜像下载 URL (适合 GitHub 连通性不佳时)"
    echo " 3) 📁 [手动放置] 使用本地已上传/放置好的 VRCX.AppImage"
    echo "--------------------------------------------------"
    read -p "请输入选项 [1-3, 默认 1]: " SOURCE_CHOICE
    SOURCE_CHOICE="${SOURCE_CHOICE:-1}"

    case "$SOURCE_CHOICE" in
        1)
            echo "🔍 正在从 GitHub API 获取最新 Release 链接..."
            if [ -z "$REGEX" ]; then
                echo "❌ 无法自动识别系统架构 ($ARCH)，请使用选项 2 或 3。"
                continue
            fi

            LATEST_URL=$(curl -s https://api.github.com/repos/vrcx-team/VRCX/releases/latest | jq -r ".assets[] | select(.name | test(\"$REGEX\")) | .browser_download_url" 2>/dev/null || echo "")

            if [ -n "$LATEST_URL" ] && [ "$LATEST_URL" != "null" ]; then
                echo "🌐 获取到下载地址: $LATEST_URL"
                echo "⬇️ 正在下载 VRCX.AppImage ..."
                if wget -O VRCX.AppImage "$LATEST_URL"; then
                    download_success=true
                else
                    echo "❌ 自动下载失败！可能是网络受阻，请尝试选项 2 或 3。"
                fi
            else
                echo "❌ 无法从 GitHub 获取下载地址，请检查网络或 GitHub API 限制。"
            fi
            ;;
        2)
            read -p "请输入 VRCX.AppImage 的完整下载 URL: " CUSTOM_URL
            if [ -n "$CUSTOM_URL" ]; then
                echo "⬇️ 正在尝试从自定义链接下载..."
                if wget -O VRCX.AppImage "$CUSTOM_URL"; then
                    download_success=true
                else
                    echo "❌ 从自定义链接下载失败，请检查 URL 是否有效。"
                fi
            else
                echo "⚠️ URL 不能为空。"
            fi
            ;;
        3)
            # 检查当前或根目录下是否已有文件
            if [ -f "$APP_DIR/VRCX.AppImage" ]; then
                echo "✅ 在 $APP_DIR 找到了 VRCX.AppImage！"
                download_success=true
            elif [ -f "$INSTALL_DIR/VRCX.AppImage" ]; then
                mv "$INSTALL_DIR/VRCX.AppImage" "$APP_DIR/VRCX.AppImage"
                echo "✅ 在 $INSTALL_DIR 找到了 VRCX.AppImage 并移至应用目录！"
                download_success=true
            else
                echo -e "\n📌 未检测到文件，请按照以下路径上传："
                echo "   把你的 VRCX 部署包重命名为 'VRCX.AppImage'"
                echo "   并放置到：$APP_DIR/VRCX.AppImage"
                read -p "放置完成后，按 [Enter] 回车键重新检测..."
            fi
            ;;
        *)
            echo "❌ 无效选项，请重新输入。"
            ;;
    esac
done

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
    if not utc_str: return None
    try:
        utc_str = str(utc_str).replace('T', ' ').split('.')[0]
        dt = datetime.strptime(utc_str, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone(timedelta(hours=8)))
    except Exception:
        return None

def find_table(cursor, suffix):
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE ?", (f"%_{suffix}",))
    rows = cursor.fetchall()
    return [r[0] for r in rows]

def format_duration(seconds):
    if seconds < 60:
        return f"{int(seconds)}秒"
    elif seconds < 3600:
        mins = int(seconds // 60)
        return f"{mins}分钟"
    else:
        hours = int(seconds // 3600)
        mins = int((seconds % 3600) // 60)
        return f"{hours}小时{mins}分钟" if mins > 0 else f"{hours}小时"

def process_data():
    cfg = load_config()
    target_user_id = cfg.get("target_user_id", "").strip()

    if not target_user_id or not os.path.exists(DB_PATH):
        return

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    events_by_date = {}

    # 1. 状态变动记录 (feed_status / feed_online_offline)
    if cfg.get("log_status", True):
        for table in find_table(cursor, "feed_status") + find_table(cursor, "feed_online_offline"):
            try:
                cursor.execute(f"PRAGMA table_info('{table}')")
                cols = [c[1] for c in cursor.fetchall()]
                
                user_col = "user_id" if "user_id" in cols else "userId"
                time_col = "created_at" if "created_at" in cols else ("created" if "created" in cols else "timestamp")
                
                if user_col in cols and time_col in cols:
                    cursor.execute(f"SELECT * FROM '{table}' WHERE {user_col} = ?", (target_user_id,))
                    for row in cursor.fetchall():
                        dt = get_beijing_time(row[cols.index(time_col)])
                        if not dt: continue
                        date_str = dt.strftime("%Y-%m-%d")
                        time_str = dt.strftime("%H:%M:%S")

                        status_val = str(row[cols.index("status")]) if "status" in cols else ""
                        desc_val = str(row[cols.index("status_description")]) if "status_description" in cols else ""
                        
                        if status_val in ["None", "null", "NoneType", ""]:
                            status_val = ""
                        if desc_val in ["None", "null", "NoneType", ""]:
                            desc_val = ""

                        # 过滤无状态无签名的冗余日志
                        if not status_val and not desc_val:
                            continue

                        action_text = f"状态变动: {status_val}" if status_val else "状态签名更新"
                        if desc_val:
                            action_text += f" - 签名: \"{desc_val}\""

                        events_by_date.setdefault(date_str, []).append({
                            "raw_time": dt,
                            "time": time_str,
                            "event_type": "status_change",
                            "action": action_text
                        })
            except Exception:
                pass

    # 2. 房间 GPS 位置记录 (feed_gps)
    if cfg.get("log_world", True):
        for table in find_table(cursor, "feed_gps"):
            try:
                cursor.execute(f"PRAGMA table_info('{table}')")
                cols = [c[1] for c in cursor.fetchall()]
                
                user_col = "user_id" if "user_id" in cols else "userId"
                time_col = "created_at" if "created_at" in cols else ("created" if "created" in cols else "timestamp")

                if user_col in cols and time_col in cols:
                    cursor.execute(f"SELECT * FROM '{table}' WHERE {user_col} = ?", (target_user_id,))
                    for row in cursor.fetchall():
                        dt = get_beijing_time(row[cols.index(time_col)])
                        if not dt: continue
                        date_str = dt.strftime("%Y-%m-%d")
                        time_str = dt.strftime("%H:%M:%S")

                        world_name = str(row[cols.index("world_name")]) if "world_name" in cols else "未知房间"
                        
                        events_by_date.setdefault(date_str, []).append({
                            "raw_time": dt,
                            "time": time_str,
                            "event_type": "world_change",
                            "world": world_name
                        })
            except Exception:
                pass

    # 3. 更换 Avatar 模型 (feed_avatar 或 avatar_history)
    if cfg.get("log_avatar", True):
        for table in find_table(cursor, "feed_avatar") + find_table(cursor, "avatar_history"):
            try:
                cursor.execute(f"PRAGMA table_info('{table}')")
                cols = [c[1] for c in cursor.fetchall()]

                user_col = "user_id" if "user_id" in cols else "userId"
                time_col = "created_at" if "created_at" in cols else ("created" if "created" in cols else "timestamp")

                if user_col in cols and time_col in cols:
                    cursor.execute(f"SELECT * FROM '{table}' WHERE {user_col} = ?", (target_user_id,))
                    for row in cursor.fetchall():
                        dt = get_beijing_time(row[cols.index(time_col)])
                        if not dt: continue
                        date_str = dt.strftime("%Y-%m-%d")
                        time_str = dt.strftime("%H:%M:%S")

                        avatar_name = str(row[cols.index("avatar_name")]) if "avatar_name" in cols else "未知 Avatar"
                        thumb = str(row[cols.index("thumbnail_url")]) if "thumbnail_url" in cols else ""

                        events_by_date.setdefault(date_str, []).append({
                            "raw_time": dt,
                            "time": time_str,
                            "event_type": "avatar_change",
                            "avatar_name": avatar_name,
                            "thumbnail": thumb if thumb != "None" else "",
                            "action": f"更换模型为 [{avatar_name}]"
                        })
            except Exception:
                pass

    # 4. 修改 Bio 简介 (feed_bio)
    if cfg.get("log_bio", True):
        for table in find_table(cursor, "feed_bio"):
            try:
                cursor.execute(f"PRAGMA table_info('{table}')")
                cols = [c[1] for c in cursor.fetchall()]

                user_col = "user_id" if "user_id" in cols else "userId"
                time_col = "created_at" if "created_at" in cols else ("created" if "created" in cols else "timestamp")

                if user_col in cols and time_col in cols:
                    cursor.execute(f"SELECT * FROM '{table}' WHERE {user_col} = ?", (target_user_id,))
                    for row in cursor.fetchall():
                        dt = get_beijing_time(row[cols.index(time_col)])
                        if not dt: continue
                        date_str = dt.strftime("%Y-%m-%d")
                        time_str = dt.strftime("%H:%M:%S")

                        bio_text = str(row[cols.index("bio")]) if "bio" in cols else ""

                        events_by_date.setdefault(date_str, []).append({
                            "raw_time": dt,
                            "time": time_str,
                            "event_type": "bio_change",
                            "action": f"修改个人简介 Bio: {bio_text}"
                        })
            except Exception:
                pass

    conn.close()

    # 全局时间排序
    all_events = []
    for d, evts in events_by_date.items():
        all_events.extend(evts)
    all_events.sort(key=lambda x: x["raw_time"])

    # 动态计算停留时长
    world_events = [e for e in all_events if e["event_type"] == "world_change"]
    for i in range(len(world_events)):
        curr_e = world_events[i]
        if i < len(world_events) - 1:
            next_e = world_events[i+1]
            diff_sec = (next_e["raw_time"] - curr_e["raw_time"]).total_seconds()
            curr_e["duration"] = format_duration(diff_sec)
        else:
            curr_e["duration"] = "至今 / 未离场"

    # 按日期分组整理输出
    final_output = []
    grouped_by_date = {}
    for e in all_events:
        d_str = e["raw_time"].strftime("%Y-%m-%d")
        del e["raw_time"]
        grouped_by_date.setdefault(d_str, []).append(e)

    for date_key in sorted(grouped_by_date.keys(), reverse=True):
        final_output.append({
            "date": date_key,
            "timeline": grouped_by_date[date_key]
        })

    os.makedirs(DATA_DIR, exist_ok=True)
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(final_output, f, ensure_ascii=False, indent=2)

if __name__ == "__main__":
    process_data()
PYEOF

# 5. 生成交互式配置脚本 (config_logger.sh)
cat << 'CONFIGEOF' > "$APP_DIR/config_logger.sh"
#!/bin/bash

APP_DIR=$(cd $(dirname $0); pwd)
CONFIG_FILE="$APP_DIR/config.json"

# 读取现有配置
get_cfg() {
    python3 -c "import json; f=open('$CONFIG_FILE'); d=json.load(f); print(d.get('$1', ''))" 2>/dev/null
}

CURR_USER_ID=$(get_cfg "target_user_id")
CURR_CRON=$(get_cfg "cron_minutes")

echo "=========================================="
echo "      VRChat Logger 交互式参数配置"
echo "=========================================="

# 询问用户配置
read -p "请输入追踪的目标 VRChat User ID [$CURR_USER_ID]: " USER_ID
USER_ID="${USER_ID:-$CURR_USER_ID}"

read -p "请输入后台自动导出的时间间隔(分钟) [默认: ${CURR_CRON:-5}]: " CRON_MIN
CRON_MIN="${CRON_MIN:-${CURR_CRON:-5}}"

# 选项开关控制
read -p "是否记录【在线状态/签名】变动? (Y/n): " LOG_STATUS
LOG_STATUS=$(echo "${LOG_STATUS:-Y}" | grep -iq "^y" && echo "true" || echo "false")

read -p "是否记录【更换房间 GPS】位置? (Y/n): " LOG_WORLD
LOG_WORLD=$(echo "${LOG_WORLD:-Y}" | grep -iq "^y" && echo "true" || echo "false")

read -p "是否记录【更换 Avatar 模型】历史? (Y/n): " LOG_LOG_AVATAR
LOG_AVATAR=$(echo "${LOG_LOG_AVATAR:-Y}" | grep -iq "^y" && echo "true" || echo "false")

read -p "是否记录【修改 Bio 简介】记录? (Y/n): " LOG_BIO
LOG_BIO=$(echo "${LOG_BIO:-Y}" | grep -iq "^y" && echo "true" || echo "false")

# 更新 config.json
cat <<JSON > "$CONFIG_FILE"
{
  "target_user_id": "$USER_ID",
  "cron_minutes": $CRON_MIN,
  "log_status": $LOG_STATUS,
  "log_world": $LOG_WORLD,
  "log_avatar": $LOG_AVATAR,
  "log_bio": $LOG_BIO
}
JSON

# 更新 Crontab 定时任务
(crontab -l 2>/dev/null | grep -v "$APP_DIR/export_daily.py" ; echo "*/$CRON_MIN * * * * python3 $APP_DIR/export_daily.py >/dev/null 2>&1") | crontab -

echo "------------------------------------------"
echo "✅ 配置已成功更新！"
echo "📌 当前追踪 Target ID: $USER_ID"
echo "⏱️ 后台 Cron 定时任务: 每 $CRON_MIN 分钟刷新一次"
echo "=========================================="
CONFIGEOF

chmod +x "$APP_DIR/config_logger.sh"

echo -e "\n✅ 基础环境搭建完成！即将自动调用交互式配置脚本..."
sleep 1

# 首次自动启动配置脚本
bash "$APP_DIR/config_logger.sh"
