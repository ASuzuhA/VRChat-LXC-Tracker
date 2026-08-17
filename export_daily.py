#!/usr/bin/env python3
import os
import sys
import json
import sqlite3
from datetime import datetime, timezone, timedelta

# 获取脚本目录及输出路径
APP_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(APP_DIR, "config.json")
DATA_DIR = os.path.join(os.path.dirname(APP_DIR), "vrcx_data")
OUTPUT_JSON = os.path.join(DATA_DIR, "data.json")

# VRCX 数据库路径
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

    # 1. 状态变动记录
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
                        
                        if status_val in ["None", "null", "NoneType", ""]: status_val = ""
                        if desc_val in ["None", "null", "NoneType", ""]: desc_val = ""

                        if not status_val and not desc_val: continue

                        action_text = f"状态变动: {status_val}" if status_val else "状态签名更新"
                        # 已修复：外层改用单引号，解决双引号冲突语法错误
                        if desc_val: action_text += f' - 签名: "{desc_val}"'

                        events_by_date.setdefault(date_str, []).append({
                            "raw_time": dt,
                            "time": time_str,
                            "event_type": "status_change",
                            "action": action_text
                        })
            except Exception:
                pass

    # 2. 房间 GPS 位置记录
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

    # 3. 更换 Avatar 模型
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

    # 4. 修改 Bio 简介
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

    all_events = []
    for d, evts in events_by_date.items():
        all_events.extend(evts)
    all_events.sort(key=lambda x: x["raw_time"])

    world_events = [e for e in all_events if e["event_type"] == "world_change"]
    for i in range(len(world_events)):
        curr_e = world_events[i]
        if i < len(world_events) - 1:
            next_e = world_events[i+1]
            diff_sec = (next_e["raw_time"] - curr_e["raw_time"]).total_seconds()
            curr_e["duration"] = format_duration(diff_sec)
        else:
            curr_e["duration"] = "至今 / 未离场"

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
