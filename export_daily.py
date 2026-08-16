import sqlite3
import json
import os
from datetime import datetime, timedelta

# ================= 配置区 =================
TARGET_USER_ID = "usr_xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx".strip().lower()
DB_PATH = os.path.expanduser("~/.config/VRCX/VRCX.sqlite3")
OUTPUT_JSON = os.path.expanduser("~/vrcx_site/public/data.json")
# ===========================================

def parse_iso_dt(time_str):
    """解析 ISO UTC 时间并转换为北京时间 datetime 对象"""
    try:
        clean_time = time_str.split('.')[0].replace('Z', '')
        dt = datetime.strptime(clean_time, "%Y-%m-%dT%H:%M:%S")
        return dt + timedelta(hours=8)
    except Exception:
        return datetime.now()

def format_duration(seconds):
    """把秒数格式化为易读的时长（如：45分钟 / 2小时10分钟）"""
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
        print(f"Error: 找不到数据库文件 {DB_PATH}")
        return {}

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # 1. 查找带有小号前缀的相关数据表
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_feed_gps';")
    gps_tables = cursor.fetchall()
    
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_feed_online_offline';")
    status_tables = cursor.fetchall()

    if not gps_tables:
        print("Error: 未找到 feed_gps 数据表")
        conn.close()
        return {}

    gps_table = gps_tables[0]['name']
    status_table = status_tables[0]['name'] if status_tables else None

    # 2. 获取所有的 GPS 轨迹记录
    cursor.execute(f"SELECT created_at, user_id, location, world_name FROM {gps_table} ORDER BY created_at ASC")
    gps_rows = cursor.fetchall()

    # 3. 获取所有的上下线记录 (如果有)
    status_rows = []
    if status_table:
        cursor.execute(f"SELECT created_at, user_id, type FROM {status_table} ORDER BY created_at ASC")
        status_rows = cursor.fetchall()

    conn.close()

    # 4. 合并所有事件并按时间排序
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
        event_type = str(item.get("type", "")).lower() # online 或 offline
        
        if "online" in event_type or "offline" in event_type:
            events.append({
                "dt": dt_local,
                "type": "status",
                "status": "上线" if "online" in event_type else "下线"
            })

    # 按时间升序排列所有事件
    events.sort(key=lambda x: x["dt"])

    # 5. 计算停留时长与组织数据
    grouped_data = {}

    for i in range(len(events)):
        curr = events[i]
        dt = curr["dt"]
        date_key = dt.strftime("%Y-%m-%d")
        time_hm = dt.strftime("%H:%M")

        if date_key not in grouped_data:
            grouped_data[date_key] = []

        if curr["type"] == "status":
            # 上线 / 下线节点
            grouped_data[date_key].append({
                "event_type": "status",
                "time": time_hm,
                "action": curr["status"] # "上线" 或 "下线"
            })
        elif curr["type"] == "world":
            # 计算在该房间停留的时长（对比下一个事件的时间点）
            duration_str = "至今 / 停留中"
            if i + 1 < len(events):
                next_dt = events[i + 1]["dt"]
                time_diff_seconds = (next_dt - dt).total_seconds()
                duration_str = format_duration(time_diff_seconds)

            grouped_data[date_key].append({
                "event_type": "world_change",
                "time": time_hm,
                "world": curr["world"],
                "duration": duration_str # 在该房间待的总时长
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

    print(f"[{datetime.now()}] 导出成功！完美提取上线、下线、地图及停留时长。")

if __name__ == "__main__":
    update_site_data()
