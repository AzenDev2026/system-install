cat > ~/nvinstall/gui.sh <<'GUI_EOF'
#!/usr/bin/env bash
# NVazen 安装器图形界面 (Zenity 版)
# 流程: 欢迎(语言) → 用户数据 → 磁盘操作 → 确认安装
set -uo pipefail

INSTALLER="/usr/local/bin/nvazen-install"
LOG="/tmp/nvazen-install.log"
RC_FILE="/tmp/nvazen-install.rc"

command -v zenity >/dev/null || { echo "缺少 zenity，请安装: pacman -S zenity"; exit 1; }
[[ -x "$INSTALLER" ]] || { zenity --error --text="找不到 $INSTALLER"; exit 1; }

# ---------- 步骤 1: 欢迎 + 语言 ----------
LANG_SEL=$(zenity --list --radiolist \
    --title="NVazen Installer" \
    --text="Welcome to NVazen\n\n选择语言 / Select Language" \
    --column="" --column="Language" \
    TRUE "en" FALSE "zh" \
    --height=220 --width=360 2>/dev/null) || exit 0
LANG_CHOICE="${LANG_SEL:-en}"

if [[ "$LANG_CHOICE" == "zh" ]]; then
    T_WELCOME="欢迎安装 NVazen"
    T_INFO="NVazen Linux\n\n基于 Arch Linux 的轻量桌面系统\n\n安装将清空你选择的整个磁盘。"
    T_HOST="主机名:"
    T_USER="用户名:"
    T_PASS="用户密码:"
    T_PASS2="确认密码:"
    T_ROOTPASS="Root 密码 (留空则与用户密码相同):"
    T_DISK_TITLE="选择安装磁盘 (所有数据将被清空)"
    T_FS_TITLE="选择文件系统"
    T_RES_TITLE="选择资源类型"
    T_CONFIRM_TITLE="确认安装"
    T_START="开始安装"
    T_CANCEL="取消"
    T_INSTALLING="正在安装 NVazen...\n\n请耐心等待，安装完成后窗口会自动关闭。"
    T_DONE="✅ NVazen 安装完成！\n\n系统将在确认后重启。"
    T_FAIL="安装失败，请查看日志。"
else
    T_WELCOME="Welcome to NVazen"
    T_INFO="NVazen Linux\n\nA lightweight desktop based on Arch Linux.\n\nThe installation will erase the entire selected disk."
    T_HOST="Hostname:"
    T_USER="Username:"
    T_PASS="Password:"
    T_PASS2="Confirm password:"
    T_ROOTPASS="Root password (empty = same as user):"
    T_DISK_TITLE="Select target disk (ALL DATA WILL BE LOST)"
    T_FS_TITLE="Select filesystem"
    T_RES_TITLE="Select resource type"
    T_CONFIRM_TITLE="Confirm installation"
    T_START="Start Installation"
    T_CANCEL="Cancel"
    T_INSTALLING="Installing NVazen...\n\nPlease wait, the window will close automatically when done."
    T_DONE="✅ NVazen installation complete!\n\nSystem will reboot after confirmation."
    T_FAIL="Installation failed. Check log."
fi

zenity --info --title="$T_WELCOME" --text="$T_INFO" \
    --width=420 2>/dev/null || exit 0

# ---------- 步骤 2: 用户数据 ----------
HOSTNAME=$(zenity --entry --title="NVazen" \
    --text="$T_HOST" --entry-text="nvazen" 2>/dev/null) || exit 0
[[ -n "$HOSTNAME" ]] || { zenity --error --text="主机名不能为空"; exit 1; }

USERNAME=$(zenity --entry --title="NVazen" \
    --text="$T_USER" --entry-text="nvazen" 2>/dev/null) || exit 0
[[ -n "$USERNAME" ]] || { zenity --error --text="用户名不能为空"; exit 1; }

USER_PASS=$(zenity --password --title="NVazen" \
    --text="$T_PASS" 2>/dev/null) || exit 0
[[ -n "$USER_PASS" ]] || { zenity --error --text="密码不能为空"; exit 1; }

USER_PASS2=$(zenity --password --title="NVazen" \
    --text="$T_PASS2" 2>/dev/null) || exit 0
[[ "$USER_PASS" == "$USER_PASS2" ]] || { zenity --error --text="两次密码不一致"; exit 1; }

ROOT_PASS=$(zenity --password --title="NVazen" \
    --text="$T_ROOTPASS" 2>/dev/null) || exit 0
: "${ROOT_PASS:=$USER_PASS}"

# ---------- 步骤 3: 磁盘操作 ----------
DISK_LIST=$(lsblk -dpno NAME,SIZE,MODEL | grep -E '/dev/(sd|nvme|vd|mmcblk)' || true)
[[ -n "$DISK_LIST" ]] || { zenity --error --text="未检测到可安装的磁盘"; exit 1; }

DISK_CHOICES=()
while read -r name size model; do
    DISK_CHOICES+=("$name" "$name  ($size) $model")
done <<< "$DISK_LIST"

TARGET_DISK=$(zenity --list --title="$T_DISK_TITLE" \
    --column="设备" --column="详情" \
    "${DISK_CHOICES[@]}" \
    --height=320 --width=640 2>/dev/null) || exit 0
[[ -n "$TARGET_DISK" ]] || exit 0
TARGET_DISK="${TARGET_DISK%% *}"
[[ -b "$TARGET_DISK" ]] || { zenity --error --text="无效磁盘: $TARGET_DISK"; exit 1; }

FS_TYPE=$(zenity --list --radiolist \
    --title="$T_FS_TITLE" \
    --text="Filesystem:" \
    --column="" --column="类型" --column="说明" \
    TRUE "ext4" "稳定，兼容" \
    FALSE "btrfs" "快照，压缩" \
    --height=250 --width=420 2>/dev/null) || exit 0
[[ -n "$FS_TYPE" ]] || FS_TYPE="ext4"

RESOURCE_TYPE=$(zenity --list --radiolist \
    --title="$T_RES_TITLE" \
    --text="NVazen Resource:" \
    --column="" --column="类型" --column="说明" \
    TRUE "standard" "标准资源 (Azen_sys.resource)" \
    FALSE "pro" "Pro 系列 (nvpro-rec + plasma-config-backup)" \
    --height=260 --width=480 2>/dev/null) || exit 0
[[ -n "$RESOURCE_TYPE" ]] || RESOURCE_TYPE="standard"

# ---------- 步骤 4: 确认 ----------
zenity --question --title="$T_CONFIRM_TITLE" \
    --text="<b>安装摘要 / Summary</b>\n\n磁盘 Disk: $TARGET_DISK\n文件系统 FS: $FS_TYPE\n资源 Resource: $RESOURCE_TYPE\n主机名 Hostname: $HOSTNAME\n用户名 User: $USERNAME\n时区 Timezone: UTC\n\n<b>确认开始安装？所有数据将被清空。</b>" \
    --width=480 --ok-label="$T_START" --cancel-label="$T_CANCEL" 2>/dev/null || exit 0

# ---------- 执行 ----------
export NV_TARGET_DISK="$TARGET_DISK"
export NV_HOSTNAME="$HOSTNAME"
export NV_USERNAME="$USERNAME"
export NV_USER_PASS="$USER_PASS"
export NV_ROOT_PASS="$ROOT_PASS"
export NV_FS_TYPE="$FS_TYPE"
export NV_RESOURCE_TYPE="$RESOURCE_TYPE"
export NV_TIMEZONE="UTC"
export NV_LOCALE="en_US.UTF-8"
export NV_KEYMAP="us"
export NV_YES=1

rm -f "$LOG" "$RC_FILE"
touch "$LOG"

setsid bash -c "\"$INSTALLER\" >\"$LOG\" 2>&1; echo \$? > \"$RC_FILE\"" &

# 进度窗口: 用 pulsate 循环，直到 RC 文件出现
(
    while [[ ! -f "$RC_FILE" ]]; do
        sleep 2
    done
) | zenity --progress --title="NVazen Installer" \
    --text="$T_INSTALLING" \
    --pulsate --auto-close --no-cancel --width=420 2>/dev/null

# 等待后台进程彻底退出
for _ in {1..30}; do
    [[ -f "$RC_FILE" ]] && break
    sleep 1
done

RC=$(cat "$RC_FILE" 2>/dev/null || echo 1)
if [[ "$RC" == "0" ]]; then
    zenity --info --title="NVazen" --text="$T_DONE" --width=380 2>/dev/null
    reboot -f
else
    zenity --error --title="NVazen" --text="$T_FAIL\n\n$LOG" --width=420 2>/dev/null
    zenity --text-info --title="Log" --filename="$LOG" \
        --width=820 --height=620 2>/dev/null || true
fi
GUI_EOF

chmod 755 ~/nvinstall/gui.sh
