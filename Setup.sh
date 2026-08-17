#!/bin/bash

# ==============================================================================
# VRChat Track Logger 一键部署脚本
#
# 功能：
# 1. 自动安装系统依赖
# 2. 自动匹配 CPU 架构下载 VRCX
# 3. 支持 GitHub / 自定义 URL / 本地 AppImage
# 4. 自动解压 VRCX
# 5. 自动生成 config.json
# 6. 自动生成最终版 export_daily.py
# 7. 自动生成 config_logger.sh
# 8. 自动配置 Cron
# 9. 自动配置 Xvfb / Systemd Headless
# 10. 支持 Online / Offline
# 11. Offline 自动结束当前房间停留时间
# ==============================================================================

set -e

echo "=================================================="
echo " VRChat Track Logger 一键纯环境部署"
echo "=================================================="


# ==============================================================================
# 1. 安装目录
# ==============================================================================

DEFAULT_INSTALL_DIR="$HOME"

read -p "请输入部署根目录绝对路径 [默认: $DEFAULT_INSTALL_DIR]: " INSTALL_DIR

INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"

INSTALL_DIR=$(eval echo "$INSTALL_DIR")

APP_DIR="$INSTALL_DIR/vrcx"
DATA_DIR="$INSTALL_DIR/vrcx_data"

mkdir -p "$APP_DIR"
mkdir -p "$DATA_DIR"


# ==============================================================================
# 2. 安装系统依赖
# ==============================================================================

echo -e "\n⏳ 1. 正在更新系统软件包并安装基础依赖..."

export DEBIAN_FRONTEND=noninteractive

apt update
apt upgrade -y

apt install -y \
    wget \
    curl \
    unzip \
    xfce4 \
    xrdp \
    xvfb \
    python3 \
    python3-pip \
    sqlite3 \
    jq \
    tzdata \
    cron

# 设置系统时区
timedatectl set-timezone Asia/Shanghai || true

# 启动 xrdp
systemctl enable --now xrdp 2>/dev/null || true


# ==============================================================================
# 3. 获取 VRCX
# ==============================================================================

echo -e "\n📦 2. 选择 VRCX 运行环境获取方式..."

cd "$APP_DIR"

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

    echo
    echo "请选择 VRCX 安装包获取途径："
    echo " 1) 🌐 [自动推荐] 自动检测系统架构并从 GitHub Release 获取"
    echo " 2) 🔗 [自定义链接] 输入自定义/镜像下载 URL"
    echo " 3) 📁 [手动放置] 使用本地已上传的 VRCX.AppImage"
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

            LATEST_URL=$(
                curl -s \
                https://api.github.com/repos/vrcx-team/VRCX/releases/latest |
                jq -r ".assets[] | select(.name | test(\"$REGEX\")) | .browser_download_url" \
                2>/dev/null || echo ""
            )

            if [ -n "$LATEST_URL" ] && [ "$LATEST_URL" != "null" ]; then

                echo "🌐 获取到下载地址："
                echo "$LATEST_URL"

                echo "⬇️ 正在下载 VRCX.AppImage ..."

                if wget -O VRCX.AppImage "$LATEST_URL"; then

                    download_success=true

                else

                    echo "❌ 自动下载失败！"
                    echo "   可以尝试选项 2 或 3。"

                fi

            else

                echo "❌ 无法从 GitHub 获取下载地址。"
                echo "   请检查网络或 GitHub API 限制。"

            fi

            ;;


        2)

            read -p "请输入 VRCX.AppImage 的完整下载 URL: " CUSTOM_URL

            if [ -n "$CUSTOM_URL" ]; then

                echo "⬇️ 正在尝试从自定义链接下载..."

                if wget -O VRCX.AppImage "$CUSTOM_URL"; then

                    download_success=true

                else

                    echo "❌ 从自定义链接下载失败。"

                fi

            else

                echo "⚠️ URL 不能为空。"

            fi

            ;;


        3)

            if [ -f "$APP_DIR/VRCX.AppImage" ]; then

                echo "✅ 在 $APP_DIR 找到了 VRCX.AppImage！"

                download_success=true

            elif [ -f "$INSTALL_DIR/VRCX.AppImage" ]; then

                mv "$INSTALL_DIR/VRCX.AppImage" "$APP_DIR/VRCX.AppImage"

                echo "✅ 已找到 VRCX.AppImage 并移动至应用目录。"

                download_success=true

            else

                echo
                echo "📌 未检测到 VRCX.AppImage。"
                echo
                echo "请将 VRCX 部署包重命名为："
                echo "VRCX.AppImage"
                echo
                echo "并放置到："
                echo "$APP_DIR/VRCX.AppImage"
                echo

                read -p "放置完成后按 Enter 重新检测..."

            fi

            ;;


        *)

            echo "❌ 无效选项，请重新输入。"

            ;;

    esac

done


# ==============================================================================
# 解压 VRCX
# ==============================================================================

chmod +x "$APP_DIR/VRCX.AppImage"

echo
echo "📦 正在解压 VRCX 免安装绿色运行环境..."

cd "$APP_DIR"

rm -rf squashfs-root

./VRCX.AppImage --appimage-extract


# ==============================================================================
# 4. 初始化 config.json
# ==============================================================================

echo
echo "⚙️ 3. 正在初始化配置文件..."

CONFIG_PATH="$APP_DIR/config.json"

if [ ! -f "$CONFIG_PATH" ]; then

    cat <<'JSON' > "$CONFIG_PATH"
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


# ==============================================================================
# 5. 生成最终版 export_daily.py
# ==============================================================================

echo
echo "🐍 4. 正在生成最终版 export_daily.py ..."

cat <<'PYEOF' > "$APP_DIR/export_daily.py"
#!/usr/bin/env python3

import os
import json
import sqlite3

from datetime import datetime, timezone, timedelta


# ============================================================
# 路径
# ============================================================

APP_DIR = os.path.dirname(os.path.abspath(__file__))

CONFIG_PATH = os.path.join(
    APP_DIR,
    "config.json"
)

DATA_DIR = os.path.join(
    os.path.dirname(APP_DIR),
    "vrcx_data"
)

OUTPUT_JSON = os.path.join(
    DATA_DIR,
    "data.json"
)

HOME_DIR = os.path.expanduser("~")

DB_PATH = os.path.join(
    HOME_DIR,
    ".config",
    "VRCX",
    "VRCX.sqlite3"
)


# ============================================================
# 读取配置
# ============================================================

def load_config():

    if not os.path.exists(CONFIG_PATH):
        return {}

    try:

        with open(
            CONFIG_PATH,
            "r",
            encoding="utf-8"
        ) as f:

            return json.load(f)

    except Exception:

        return {}


# ============================================================
# UTC -> 北京时间
# ============================================================

def get_beijing_time(utc_str):

    if not utc_str:
        return None

    try:

        value = str(utc_str).strip()

        value = value.replace(
            "T",
            " "
        )

        value = value.rstrip("Z")

        value = value.split(".")[0]

        dt = datetime.strptime(
            value,
            "%Y-%m-%d %H:%M:%S"
        )

        dt = dt.replace(
            tzinfo=timezone.utc
        )

        return dt.astimezone(
            timezone(timedelta(hours=8))
        )

    except Exception:

        return None


# ============================================================
# 查找表
# ============================================================

def find_table(cursor, suffix):

    try:

        cursor.execute(
            """
            SELECT name
            FROM sqlite_master
            WHERE type='table'
            AND name LIKE ?
            """,
            (f"%_{suffix}",)
        )

        return [
            row[0]
            for row in cursor.fetchall()
        ]

    except Exception:

        return []


# ============================================================
# 安全获取字段
# ============================================================

def get_column_value(
    row,
    cols,
    column_name,
    default=""
):

    if column_name not in cols:
        return default

    try:

        value = row[
            cols.index(column_name)
        ]

        if value is None:
            return default

        return str(value)

    except Exception:

        return default


# ============================================================
# 停留时间格式
# ============================================================

def format_duration(seconds):

    seconds = max(
        0,
        int(seconds)
    )

    if seconds < 60:

        return f"{seconds}秒"

    elif seconds < 3600:

        mins = seconds // 60
        secs = seconds % 60

        if secs:

            return f"{mins}分钟{secs}秒"

        return f"{mins}分钟"

    else:

        hours = seconds // 3600
        mins = (seconds % 3600) // 60

        if mins:

            return f"{hours}小时{mins}分钟"

        return f"{hours}小时"


# ============================================================
# 添加事件
# ============================================================

def add_event(
    events,
    dt,
    event
):

    if not dt:
        return

    event["raw_time"] = dt

    event["time"] = dt.strftime(
        "%H:%M:%S"
    )

    date_str = dt.strftime(
        "%Y-%m-%d"
    )

    events.setdefault(
        date_str,
        []
    ).append(event)


# ============================================================
# Online / Offline
#
# VRCX 实际结构：
#
# id
# created_at
# user_id
# display_name
# type
# location
# world_name
# time
# group_name
# ============================================================

def process_online_offline(
    cursor,
    target_user_id,
    events
):

    tables = find_table(
        cursor,
        "feed_online_offline"
    )

    for table in tables:

        try:

            cursor.execute(
                f"PRAGMA table_info('{table}')"
            )

            cols = [
                c[1]
                for c in cursor.fetchall()
            ]

            user_col = (
                "user_id"
                if "user_id" in cols
                else
                "userId"
                if "userId" in cols
                else None
            )

            time_col = (
                "created_at"
                if "created_at" in cols
                else
                "created"
                if "created" in cols
                else
                "timestamp"
                if "timestamp" in cols
                else None
            )

            type_col = (
                "type"
                if "type" in cols
                else None
            )

            if not user_col:
                continue

            if not time_col:
                continue

            if not type_col:
                continue

            cursor.execute(
                f"""
                SELECT *
                FROM '{table}'
                WHERE {user_col} = ?
                ORDER BY {time_col} ASC
                """,
                (target_user_id,)
            )

            for row in cursor.fetchall():

                dt = get_beijing_time(
                    row[
                        cols.index(time_col)
                    ]
                )

                if not dt:
                    continue

                status_type = get_column_value(
                    row,
                    cols,
                    type_col
                ).strip()

                location = get_column_value(
                    row,
                    cols,
                    "location"
                )

                if status_type.lower() == "online":

                    action = "上线"

                    if location:

                        action += (
                            f"（位置状态: {location}）"
                        )

                    add_event(
                        events,
                        dt,
                        {
                            "event_type": "online",
                            "action": action
                        }
                    )

                elif status_type.lower() == "offline":

                    action = "下线"

                    if location:

                        action += (
                            f"（离线位置: {location}）"
                        )

                    add_event(
                        events,
                        dt,
                        {
                            "event_type": "offline",
                            "action": action
                        }
                    )

        except Exception:

            pass


# ============================================================
# 状态 / 签名
# ============================================================

def process_status(
    cursor,
    target_user_id,
    events
):

    tables = find_table(
        cursor,
        "feed_status"
    )

    for table in tables:

        try:

            cursor.execute(
                f"PRAGMA table_info('{table}')"
            )

            cols = [
                c[1]
                for c in cursor.fetchall()
            ]

            user_col = (
                "user_id"
                if "user_id" in cols
                else
                "userId"
                if "userId" in cols
                else None
            )

            time_col = (
                "created_at"
                if "created_at" in cols
                else
                "created"
                if "created" in cols
                else
                "timestamp"
                if "timestamp" in cols
                else None
            )

            if not user_col or not time_col:
                continue

            cursor.execute(
                f"""
                SELECT *
                FROM '{table}'
                WHERE {user_col} = ?
                ORDER BY {time_col} ASC
                """,
                (target_user_id,)
            )

            for row in cursor.fetchall():

                dt = get_beijing_time(
                    row[
                        cols.index(time_col)
                    ]
                )

                if not dt:
                    continue

                status_val = get_column_value(
                    row,
                    cols,
                    "status"
                )

                desc_val = get_column_value(
                    row,
                    cols,
                    "status_description"
                )

                if status_val in (
                    "None",
                    "null",
                    "NoneType"
                ):
                    status_val = ""

                if desc_val in (
                    "None",
                    "null",
                    "NoneType"
                ):
                    desc_val = ""

                if not status_val and not desc_val:
                    continue

                if status_val:

                    action_text = (
                        f"状态变动: {status_val}"
                    )

                else:

                    action_text = (
                        "状态签名更新"
                    )

                if desc_val:

                    action_text += (
                        f' - 签名: "{desc_val}"'
                    )

                add_event(
                    events,
                    dt,
                    {
                        "event_type":
                            "status_change",
                        "action":
                            action_text
                    }
                )

        except Exception:

            pass


# ============================================================
# 房间 GPS
# ============================================================

def process_world(
    cursor,
    target_user_id,
    events
):

    tables = find_table(
        cursor,
        "feed_gps"
    )

    for table in tables:

        try:

            cursor.execute(
                f"PRAGMA table_info('{table}')"
            )

            cols = [
                c[1]
                for c in cursor.fetchall()
            ]

            user_col = (
                "user_id"
                if "user_id" in cols
                else
                "userId"
                if "userId" in cols
                else None
            )

            time_col = (
                "created_at"
                if "created_at" in cols
                else
                "created"
                if "created" in cols
                else
                "timestamp"
                if "timestamp" in cols
                else None
            )

            if not user_col or not time_col:
                continue

            cursor.execute(
                f"""
                SELECT *
                FROM '{table}'
                WHERE {user_col} = ?
                ORDER BY {time_col} ASC
                """,
                (target_user_id,)
            )

            for row in cursor.fetchall():

                dt = get_beijing_time(
                    row[
                        cols.index(time_col)
                    ]
                )

                if not dt:
                    continue

                world_name = get_column_value(
                    row,
                    cols,
                    "world_name"
                )

                if not world_name:

                    world_name = "未知房间"

                location = get_column_value(
                    row,
                    cols,
                    "location"
                )

                add_event(
                    events,
                    dt,
                    {
                        "event_type":
                            "world_change",
                        "world":
                            world_name,
                        "location":
                            location
                    }
                )

        except Exception:

            pass


# ============================================================
# Avatar
# ============================================================

def process_avatar(
    cursor,
    target_user_id,
    events
):

    tables = (
        find_table(
            cursor,
            "feed_avatar"
        )
        +
        find_table(
            cursor,
            "avatar_history"
        )
    )

    for table in tables:

        try:

            cursor.execute(
                f"PRAGMA table_info('{table}')"
            )

            cols = [
                c[1]
                for c in cursor.fetchall()
            ]

            user_col = (
                "user_id"
                if "user_id" in cols
                else
                "userId"
                if "userId" in cols
                else None
            )

            time_col = (
                "created_at"
                if "created_at" in cols
                else
                "created"
                if "created" in cols
                else
                "timestamp"
                if "timestamp" in cols
                else None
            )

            if not user_col or not time_col:
                continue

            cursor.execute(
                f"""
                SELECT *
                FROM '{table}'
                WHERE {user_col} = ?
                ORDER BY {time_col} ASC
                """,
                (target_user_id,)
            )

            for row in cursor.fetchall():

                dt = get_beijing_time(
                    row[
                        cols.index(time_col)
                    ]
                )

                if not dt:
                    continue

                avatar_name = get_column_value(
                    row,
                    cols,
                    "avatar_name",
                    "未知 Avatar"
                )

                thumbnail = get_column_value(
                    row,
                    cols,
                    "thumbnail_url"
                )

                add_event(
                    events,
                    dt,
                    {
                        "event_type":
                            "avatar_change",

                        "avatar_name":
                            avatar_name,

                        "thumbnail":
                            thumbnail,

                        "action":
                            f"更换模型为 [{avatar_name}]"
                    }
                )

        except Exception:

            pass


# ============================================================
# Bio
# ============================================================

def process_bio(
    cursor,
    target_user_id,
    events
):

    tables = find_table(
        cursor,
        "feed_bio"
    )

    for table in tables:

        try:

            cursor.execute(
                f"PRAGMA table_info('{table}')"
            )

            cols = [
                c[1]
                for c in cursor.fetchall()
            ]

            user_col = (
                "user_id"
                if "user_id" in cols
                else
                "userId"
                if "userId" in cols
                else None
            )

            time_col = (
                "created_at"
                if "created_at" in cols
                else
                "created"
                if "created" in cols
                else
                "timestamp"
                if "timestamp" in cols
                else None
            )

            if not user_col or not time_col:
                continue

            cursor.execute(
                f"""
                SELECT *
                FROM '{table}'
                WHERE {user_col} = ?
                ORDER BY {time_col} ASC
                """,
                (target_user_id,)
            )

            for row in cursor.fetchall():

                dt = get_beijing_time(
                    row[
                        cols.index(time_col)
                    ]
                )

                if not dt:
                    continue

                bio_text = get_column_value(
                    row,
                    cols,
                    "bio"
                )

                add_event(
                    events,
                    dt,
                    {
                        "event_type":
                            "bio_change",

                        "action":
                            f"修改个人简介 Bio: {bio_text}"
                    }
                )

        except Exception:

            pass


# ============================================================
# 计算房间停留时间
#
# 房间 A
#   ↓
# Offline
#
# => 房间 A 在 Offline 时结束
#
# 房间 A
#   ↓
# 房间 B
#
# => 房间 A 在房间 B进入时结束
# ============================================================

def calculate_world_duration(
    all_events
):

    world_events = [
        e
        for e in all_events
        if e["event_type"]
        == "world_change"
    ]

    offline_events = [
        e
        for e in all_events
        if e["event_type"]
        == "offline"
    ]

    world_events.sort(
        key=lambda x: x["raw_time"]
    )

    offline_events.sort(
        key=lambda x: x["raw_time"]
    )

    for index, world_event in enumerate(
        world_events
    ):

        start_time = (
            world_event["raw_time"]
        )

        next_world_time = None

        if index < len(world_events) - 1:

            next_world_time = (
                world_events[
                    index + 1
                ]["raw_time"]
            )

        next_offline_time = None

        for offline_event in offline_events:

            offline_time = (
                offline_event["raw_time"]
            )

            if offline_time > start_time:

                next_offline_time = (
                    offline_time
                )

                break

        end_time = None

        if (
            next_world_time is not None
            and
            next_offline_time is not None
        ):

            end_time = min(
                next_world_time,
                next_offline_time
            )

        elif next_world_time is not None:

            end_time = next_world_time

        elif next_offline_time is not None:

            end_time = next_offline_time

        if end_time is not None:

            seconds = (
                end_time - start_time
            ).total_seconds()

            world_event["duration"] = (
                format_duration(seconds)
            )

        else:

            world_event["duration"] = (
                "至今 / 未离场"
            )


# ============================================================
# 主处理
# ============================================================

def process_data():

    cfg = load_config()

    target_user_id = str(
        cfg.get(
            "target_user_id",
            ""
        )
    ).strip()

    if not target_user_id:
        return

    if not os.path.exists(DB_PATH):
        return

    events_by_date = {}

    conn = None

    try:

        conn = sqlite3.connect(
            DB_PATH
        )

        cursor = conn.cursor()

        # ----------------------------------------------------
        # Online / Offline
        # ----------------------------------------------------

        if cfg.get(
            "log_status",
            True
        ):

            process_online_offline(
                cursor,
                target_user_id,
                events_by_date
            )

        # ----------------------------------------------------
        # 状态 / 签名
        # ----------------------------------------------------

        if cfg.get(
            "log_status",
            True
        ):

            process_status(
                cursor,
                target_user_id,
                events_by_date
            )

        # ----------------------------------------------------
        # 房间
        # ----------------------------------------------------

        if cfg.get(
            "log_world",
            True
        ):

            process_world(
                cursor,
                target_user_id,
                events_by_date
            )

        # ----------------------------------------------------
        # Avatar
        # ----------------------------------------------------

        if cfg.get(
            "log_avatar",
            True
        ):

            process_avatar(
                cursor,
                target_user_id,
                events_by_date
            )

        # ----------------------------------------------------
        # Bio
        # ----------------------------------------------------

        if cfg.get(
            "log_bio",
            True
        ):

            process_bio(
                cursor,
                target_user_id,
                events_by_date
            )

    finally:

        if conn is not None:

            conn.close()

    # ========================================================
    # 合并事件
    # ========================================================

    all_events = []

    for date_events in events_by_date.values():

        all_events.extend(
            date_events
        )

    all_events.sort(
        key=lambda x: x["raw_time"]
    )

    # ========================================================
    # 计算房间停留
    # ========================================================

    calculate_world_duration(
        all_events
    )

    # ========================================================
    # 日期重新分组
    # ========================================================

    grouped_by_date = {}

    for event in all_events:

        date_str = (
            event["raw_time"]
            .strftime("%Y-%m-%d")
        )

        event.pop(
            "raw_time",
            None
        )

        grouped_by_date.setdefault(
            date_str,
            []
        ).append(event)

    # ========================================================
    # 输出
    #
    # data.json 格式保持不变
    # ========================================================

    final_output = []

    for date_key in sorted(
        grouped_by_date.keys(),
        reverse=True
    ):

        final_output.append(
            {
                "date": date_key,
                "timeline":
                    grouped_by_date[
                        date_key
                    ]
            }
        )

    os.makedirs(
        DATA_DIR,
        exist_ok=True
    )

    with open(
        OUTPUT_JSON,
        "w",
        encoding="utf-8"
    ) as f:

        json.dump(
            final_output,
            f,
            ensure_ascii=False,
            indent=2
        )


# ============================================================
# Entry
# ============================================================

if __name__ == "__main__":

    process_data()

PYEOF

chmod +x "$APP_DIR/export_daily.py"


# ==============================================================================
# 6. 生成 config_logger.sh
# ==============================================================================

echo
echo "🛠️ 5. 正在生成 config_logger.sh ..."

cat <<'CONFIGEOF' > "$APP_DIR/config_logger.sh"
#!/bin/bash

APP_DIR=$(cd "$(dirname "$0")" && pwd)

CONFIG_FILE="$APP_DIR/config.json"


# ============================================================
# 读取配置
# ============================================================

get_cfg() {

    python3 -c "
import json
import os

f = open('$CONFIG_FILE') if os.path.exists('$CONFIG_FILE') else None
d = json.load(f) if f else {}

print(d.get('$1', '$2'))
" 2>/dev/null

}


USER_ID=$(get_cfg "target_user_id" "")

CRON_MIN=$(get_cfg "cron_minutes" "5")

LOG_STATUS=$(get_cfg "log_status" "true")

LOG_WORLD=$(get_cfg "log_world" "true")

LOG_AVATAR=$(get_cfg "log_avatar" "true")

LOG_BIO=$(get_cfg "log_bio" "true")


# ============================================================
# 布尔显示
# ============================================================

fmt_bool() {

    if [ "$1" = "true" ]; then

        echo -e "\033[32m[已开启]\033[0m"

    else

        echo -e "\033[31m[已关闭]\033[0m"

    fi

}


toggle_bool() {

    if [ "$1" = "true" ]; then

        echo "false"

    else

        echo "true"

    fi

}


# ============================================================
# 菜单
# ============================================================

render_menu() {

    clear

    echo -e "\033[36m=====================================================\033[0m"

    echo -e "\033[1;36m           VRChat Logger 控制台与配置中心            \033[0m"

    echo -e "\033[36m=====================================================\033[0m"

    echo -e " [ 1 ] 目标 VRChat User ID : \033[33m${USER_ID:-<未设置>}\033[0m"

    echo -e " [ 2 ] 自动导出频率(分钟)   : \033[33m${CRON_MIN} 分钟/次\033[0m"

    echo -e " ---------------------------------------------------"

    echo -e " [ A ] 记录【在线状态/签名】变动 : $(fmt_bool "$LOG_STATUS")"

    echo -e " [ B ] 记录【房间 GPS】位置变动   : $(fmt_bool "$LOG_WORLD")"

    echo -e " [ C ] 记录【Avatar 模型】更换历史 : $(fmt_bool "$LOG_AVATAR")"

    echo -e " [ D ] 记录【个人简介 Bio】修改   : $(fmt_bool "$LOG_BIO")"

    echo -e "\033[36m-----------------------------------------------------\033[0m"

    echo -e " [ S ] \033[32m保存配置并部署/刷新后台服务\033[0m"

    echo -e " [ Q ] 退出 (不保存改动)"

    echo -e "\033[36m=====================================================\033[0m"

}


# ============================================================
# 保存并部署
# ============================================================

save_and_deploy() {

    echo
    echo "💾 正在保存配置至 $CONFIG_FILE ..."

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


    # --------------------------------------------------------
    # 更新 Cron
    # --------------------------------------------------------

    echo "⏱️ 正在更新 Crontab 任务..."

    (
        crontab -l 2>/dev/null |
        grep -v "$APP_DIR/export_daily.py" || true

        echo "*/$CRON_MIN * * * * python3 $APP_DIR/export_daily.py >/dev/null 2>&1"

    ) | crontab -


    # --------------------------------------------------------
    # 立即生成一次 data.json
    # --------------------------------------------------------

    echo "📊 正在立即生成一次 data.json ..."

    python3 "$APP_DIR/export_daily.py" \
        >/dev/null 2>&1 || true


    echo
    echo -e "\033[32m✅ 配置已保存！\033[0m"
    echo -e "\033[32m✅ Cron 已刷新！\033[0m"
    echo -e "\033[32m✅ data.json 已重新生成！\033[0m"

    exit 0

}


# ============================================================
# 主循环
# ============================================================

while true; do

    render_menu

    read -p "请输入指令 [1-2 / A-D / S / Q]: " CHOICE

    case "$(echo "$CHOICE" | tr 'a-z' 'A-Z')" in

        1)

            read -p "请输入新的目标 VRChat User ID: " NEW_ID

            if [ -n "$NEW_ID" ]; then

                USER_ID="$NEW_ID"

            fi

            ;;


        2)

            read -p "请输入新的导出频率(分钟): " NEW_CRON

            if [[ "$NEW_CRON" =~ ^[0-9]+$ ]] &&
               [ "$NEW_CRON" -gt 0 ]; then

                CRON_MIN="$NEW_CRON"

            fi

            ;;


        A)

            LOG_STATUS=$(toggle_bool "$LOG_STATUS")

            ;;


        B)

            LOG_WORLD=$(toggle_bool "$LOG_WORLD")

            ;;


        C)

            LOG_AVATAR=$(toggle_bool "$LOG_AVATAR")

            ;;


        D)

            LOG_BIO=$(toggle_bool "$LOG_BIO")

            ;;


        S)

            save_and_deploy

            ;;


        Q)

            echo
            echo "已取消修改并退出。"

            exit 0

            ;;


        *)

            ;;

    esac

done

CONFIGEOF

chmod +x "$APP_DIR/config_logger.sh"


# ==============================================================================
# 7. PAM / Polkit
# ==============================================================================

echo
echo "⚙️ 6. 正在配置 PAM/Polkit 与开机自启动..."


CURRENT_USER=$(whoami)


if [ "$EUID" -eq 0 ] || [ "$CURRENT_USER" = "root" ]; then

    echo "🔒 检测到 root 用户。"

    # 保持原项目行为
    systemctl stop polkit 2>/dev/null || true

    systemctl disable polkit 2>/dev/null || true

    systemctl mask polkit 2>/dev/null || true


    if [ -f "/etc/pam.d/xrdp-sesman" ]; then

        sed -i \
            's/^.*pam_polkit.so.*$/#&/' \
            /etc/pam.d/xrdp-sesman \
            2>/dev/null || true

    fi


    mkdir -p \
        /etc/polkit-1/localauthority/50-local.d


    cat <<'PKEOF' > \
        /etc/polkit-1/localauthority/50-local.d/45-allow-all.pkla

[Allow All Root Operations]
Identity=unix-user:root
Action=*
ResultAny=yes
ResultInactive=yes
ResultActive=yes

PKEOF

fi


# ==============================================================================
# 8. 图形桌面自动启动 VRCX
# ==============================================================================

echo
echo "🖥️ 正在配置桌面自动启动..."

AUTOSTART_DIR="$HOME/.config/autostart"

mkdir -p "$AUTOSTART_DIR"


cat <<DESKEOF > "$AUTOSTART_DIR/vrcx.desktop"
[Desktop Entry]
Type=Application
Name=VRCX AutoStart
Exec=$APP_DIR/squashfs-root/AppRun --no-sandbox
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
DESKEOF


chmod +x "$AUTOSTART_DIR/vrcx.desktop"


# ==============================================================================
# 9. Systemd Headless
# ==============================================================================

echo
echo "🚀 正在配置 VRCX Headless 后台服务..."


if command -v systemctl >/dev/null 2>&1 &&
   [ "$EUID" -eq 0 ]; then


    cat <<SERVICEEOF > \
        /etc/systemd/system/vrcx-headless.service

[Unit]
Description=VRCX Headless AutoStart Service
After=network.target

[Service]
Type=simple

User=$CURRENT_USER

Environment=DISPLAY=:99

ExecStartPre=/bin/sh -c '/usr/bin/Xvfb :99 -screen 0 1280x1024x24 &'

ExecStart=$APP_DIR/squashfs-root/AppRun --no-sandbox

Restart=always

RestartSec=10

[Install]
WantedBy=multi-user.target

SERVICEEOF


    systemctl daemon-reload

    systemctl enable \
        vrcx-headless.service \
        2>/dev/null || true

    systemctl restart \
        vrcx-headless.service \
        2>/dev/null || true

fi


# ==============================================================================
# 10. 首次执行 export_daily.py
# ==============================================================================

echo
echo "📊 正在测试 export_daily.py ..."


if [ -f "$APP_DIR/export_daily.py" ]; then

    python3 "$APP_DIR/export_daily.py" \
        >/dev/null 2>&1 || true

fi


# ==============================================================================
# 完成
# ==============================================================================

echo
echo "=================================================="
echo " ✅ VRChat Track Logger 部署完成！"
echo "=================================================="
echo
echo "应用目录："
echo " $APP_DIR"
echo
echo "数据库："
echo " ~/.config/VRCX/VRCX.sqlite3"
echo
echo "配置文件："
echo " $APP_DIR/config.json"
echo
echo "配置工具："
echo " $APP_DIR/config_logger.sh"
echo
echo "数据文件："
echo " $DATA_DIR/data.json"
echo
echo "export_daily.py："
echo " $APP_DIR/export_daily.py"
echo
echo "=================================================="
echo "即将进入交互式配置菜单..."
echo "=================================================="

sleep 1

bash "$APP_DIR/config_logger.sh"
