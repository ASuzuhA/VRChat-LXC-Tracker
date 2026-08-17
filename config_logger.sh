#!/bin/bash
# ==============================================================================
# VRChat Track Logger 全局配置控制台
# 作用：随时修改监听的目标 User ID、数据刷新间隔频率以及保留的数据字段
# 说明：无需重新运行部署脚本，运行此脚本即可修改一切配置！
# ==============================================================================

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$APP_DIR/config.json"

# 初始化配置文件（若不存在）
if [ ! -f "$CONFIG_FILE" ]; then
    cat <<JSON > "$CONFIG_FILE"
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

# 从 JSON 配置文件中读取单个属性
read_cfg() {
    python3 -c "
import json
try:
    with open('$CONFIG_FILE', 'r', encoding='utf-8') as f:
        cfg = json.load(f)
        val = cfg.get('$1', '$2')
        if isinstance(val, bool):
            print('ON' if val else 'OFF')
        else:
            print(val)
except Exception:
    print('$2')
"
}

# 写回 JSON 配置文件
write_cfg() {
    python3 -c "
import json
try:
    with open('$CONFIG_FILE', 'r', encoding='utf-8') as f:
        cfg = json.load(f)
except Exception:
    cfg = {}

cfg['target_user_id'] = '$VAL_USER'
cfg['cron_minutes'] = int('$VAL_CRON')
cfg['log_status'] = True if '$VAL_STATUS' == 'ON' else False
cfg['log_world'] = True if '$VAL_WORLD' == 'ON' else False
cfg['log_avatar'] = True if '$VAL_AVATAR' == 'ON' else False
cfg['log_bio'] = True if '$VAL_BIO' == 'ON' else False

with open('$CONFIG_FILE', 'w', encoding='utf-8') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
"
}

# 刷新变量值
load_all_values() {
    VAL_USER=$(read_cfg "target_user_id" "未设置")
    VAL_CRON=$(read_cfg "cron_minutes" "5")
    VAL_STATUS=$(read_cfg "log_status" "ON")
    VAL_WORLD=$(read_cfg "log_world" "ON")
    VAL_AVATAR=$(read_cfg "log_avatar" "ON")
    VAL_BIO=$(read_cfg "log_bio" "ON")
}

# 绘制交互控制台界面
show_menu() {
    load_all_values
    clear
    echo "=================================================="
    echo "       VRChat 轨迹监听全参数配置控制台"
    echo "=================================================="
    echo " 【基础账号与频率设置】"
    echo " [U] 监听的目标 User ID  --> [ $VAL_USER ]"
    echo " [T] 轮询刷新频率 (分钟) --> [ 每 $VAL_CRON 分钟 ]"
    echo "--------------------------------------------------"
    echo " 【数据监听与导出字段】"
    echo " [1] 上下线与状态签名 (Status & Text)  --> [ $VAL_STATUS ]"
    echo " [2] 切换房间与停留时长 (World & Duration) --> [ $VAL_WORLD ]"
    echo " [3] 更换 Avatar 模型与缩略图 (Avatar Change)--> [ $VAL_AVATAR ]"
    echo " [4] 修改 Bio 个人简介 (Bio Change)          --> [ $VAL_BIO ]"
    echo "--------------------------------------------------"
    echo " [S] 保存当前所有设置并立即生效"
    echo " [Q] 退出控制台"
    echo "=================================================="
}

toggle_option() {
    case $1 in
        1) [ "$VAL_STATUS" = "ON" ] && VAL_STATUS="OFF" || VAL_STATUS="ON" ;;
        2) [ "$VAL_WORLD" = "ON" ] && VAL_WORLD="OFF" || VAL_WORLD="ON" ;;
        3) [ "$VAL_AVATAR" = "ON" ] && VAL_AVATAR="OFF" || VAL_AVATAR="ON" ;;
        4) [ "$VAL_BIO" = "ON" ] && VAL_BIO="OFF" || VAL_BIO="ON" ;;
    esac
}

# 保存并更新定时任务和数据提取
save_and_apply() {
    if [ -z "$VAL_USER" ] || [ "$VAL_USER" = "未设置" ]; then
        echo -e "\n❌ 错误: 目标 User ID 不能为空！请输入选项 [U] 进行设置。"
        read -p "按回车键继续..."
        return
    fi

    write_cfg

    # 重新配置 Crontab 计划任务
    CRON_JOB="*/$VAL_CRON * * * * /usr/bin/python3 $APP_DIR/export_daily.py > /dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -v "$APP_DIR/export_daily.py"; echo "$CRON_JOB") | crontab -

    echo -e "\n✅ 配置已保存，并成功更新 Crontab 计划任务（每 $VAL_CRON 分钟）！"
    echo "🔄 正在手动触发一次数据解析提取..."
    python3 "$APP_DIR/export_daily.py" || true
    echo "🎉 操作完成！新过滤规则与设置已生效。"
    exit 0
}

while true; do
    show_menu
    read -p "请输入菜单代号进行修改 (U / T / 1-4 / S / Q): " choice
    case "$choice" in
        [Ut])
            read -p "请输入新的目标 User ID (usr_xxx): " NEW_USER
            if [ -n "$NEW_USER" ]; then VAL_USER="$NEW_USER"; write_cfg; fi
            ;;
        [Tt])
            read -p "请输入新的轮询间隔（分钟，如 5 或 10）: " NEW_CRON
            if [[ "$NEW_CRON" =~ ^[0-9]+$ ]] && [ "$NEW_CRON" -gt 0 ]; then
                VAL_CRON="$NEW_CRON"
                write_cfg
            else
                echo "❌ 输入无效，请输入大于 0 的数字！"; sleep 1
            fi
            ;;
        1|2|3|4) toggle_option "$choice"; write_cfg ;;
        [Ss]) save_and_apply ;;
        [Qq]) exit 0 ;;
        *) echo "无效指令！"; sleep 1 ;;
    esac
done
