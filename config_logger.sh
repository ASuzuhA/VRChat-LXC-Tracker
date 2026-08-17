#!/bin/bash

APP_DIR=$(cd $(dirname $0); pwd)
CONFIG_FILE="$APP_DIR/config.json"

# --- 1. 读取当前配置或赋默认值 ---
get_cfg() {
    python3 -c "import json, os; f=open('$CONFIG_FILE') if os.path.exists('$CONFIG_FILE') else None; d=json.load(f) if f else {}; print(d.get('$1', '$2'))" 2>/dev/null
}

USER_ID=$(get_cfg "target_user_id" "")
CRON_MIN=$(get_cfg "cron_minutes" "5")
LOG_STATUS=$(get_cfg "log_status" "true")
LOG_WORLD=$(get_cfg "log_world" "true")
LOG_AVATAR=$(get_cfg "log_avatar" "true")
LOG_BIO=$(get_cfg "log_bio" "true")

# 格式化布尔值为可读状态标识
fmt_bool() {
    if [ "$1" = "true" ]; then echo -e "\033[32m[已开启]\033[0m"; else echo -e "\033[31m[已关闭]\033[0m"; fi
}

toggle_bool() {
    if [ "$1" = "true" ]; then echo "false"; else echo "true"; fi
}

# --- 2. 渲染交互主面板 ---
render_menu() {
    clear
    echo -e "\033[36m=====================================================\033[0m"
    echo -e "\033[1;36m           VRChat Logger 控制台与配置中心            \033[0m"
    echo -e "\033[36m=====================================================\033[0m"
    echo -e " [ 1 ] 目标 VRChat User ID : \033[33m${USER_ID:-<未设置>}\033[0m"
    echo -e " [ 2 ] 自动导出频率(分钟)   : \033[33m${CRON_MIN} 分钟/次\033[0m"
    echo -e " ---------------------------------------------------"
    echo -e " [ A ] 记录【在线状态/签名】变动 : $(fmt_bool $LOG_STATUS)"
    echo -e " [ B ] 记录【房间 GPS】位置变动   : $(fmt_bool $LOG_WORLD)"
    echo -e " [ C ] 记录【Avatar 模型】更换历史 : $(fmt_bool $LOG_AVATAR)"
    echo -e " [ D ] 记录【个人简介 Bio】修改   : $(fmt_bool $LOG_BIO)"
    echo -e "\033[36m-----------------------------------------------------\033[0m"
    echo -e " [ S ] \033[32m保存配置并部署/刷新后台服务\033[0m"
    echo -e " [ Q ] 退出 (不保存改动)"
    echo -e "\033[36m=====================================================\033[0m"
}

# --- 3. 保存与自动化部署操作 ---
save_and_deploy() {
    echo -e "\n💾 正在保存配置至 $CONFIG_FILE ..."
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

    echo "⏱️ 正在更新 Crontab 任务..."
    (crontab -l 2>/dev/null | grep -v "$APP_DIR/export_daily.py" ; echo "*/$CRON_MIN * * * * python3 $APP_DIR/export_daily.py >/dev/null 2>&1") | crontab -

    echo "⚙️ 正在配置 PAM/Polkit 策略与开机自启动服务..."
    CURRENT_USER=$(whoami)

    if [ "$EUID" -eq 0 ] || [ "$CURRENT_USER" = "root" ]; then
        systemctl stop polkit 2>/dev/null || true
        systemctl disable polkit 2>/dev/null || true
        systemctl mask polkit 2>/dev/null || true

        if [ -f "/etc/pam.d/xrdp-sesman" ]; then
            sed -i 's/^.*pam_polkit.so.*$/#&/' /etc/pam.d/xrdp-sesman 2>/dev/null || true
        fi

        mkdir -p /etc/polkit-1/localauthority/50-local.d
        cat <<PKEOF > /etc/polkit-1/localauthority/50-local.d/45-allow-all.pkla
[Allow All Root Operations]
Identity=unix-user:root
Action=*
ResultAny=yes
ResultInactive=yes
ResultActive=yes
PKEOF
    fi

    # 1. 桌面环境自启动 (.desktop)
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

    # 2. Systemd 开机 Headless 后台服务
    if command -v systemctl >/dev/null 2>&1 && [ "$EUID" -eq 0 ]; then
        cat <<SERVICEEOF > /etc/systemd/system/vrcx-headless.service
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
        systemctl enable vrcx-headless.service 2>/dev/null || true
        systemctl restart vrcx-headless.service 2>/dev/null || true
    fi

    echo -e "\n\033[32m✅ 全部配置与后台服务已成功更新并部署！\033[0m"
    exit 0
}

# --- 4. 主循环事件监听 ---
while true; do
    render_menu
    read -p "请输入指令 [1-2 / A-D / S / Q]: " CHOICE
    case "$(echo $CHOICE | tr 'a-z' 'A-Z')" in
        1)
            read -p "请输入新的目标 VRChat User ID: " NEW_ID
            [ -n "$NEW_ID" ] && USER_ID="$NEW_ID"
            ;;
        2)
            read -p "请输入新的导出频率(分钟): " NEW_CRON
            if [[ "$NEW_CRON" =~ ^[0-9]+$ ]]; then
                CRON_MIN="$NEW_CRON"
            fi
            ;;
        A) LOG_STATUS=$(toggle_bool $LOG_STATUS) ;;
        B) LOG_WORLD=$(toggle_bool $LOG_WORLD) ;;
        C) LOG_AVATAR=$(toggle_bool $LOG_AVATAR) ;;
        D) LOG_BIO=$(toggle_bool $LOG_BIO) ;;
        S)
            save_and_deploy
            ;;
        Q)
            echo "已取消修改并退出。"
            exit 0
            ;;
        *)
            ;;
    esac
done
