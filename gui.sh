cat > ~/nvinstall/gui.sh <<'GUI_EOF'
#!/usr/bin/env bash
# NVazen 安装器图形界面 (KDialog)
set -uo pipefail

INSTALLER="/usr/local/bin/nvazen-install"
LOG="/tmp/nvazen-install.log"

# 语言
LANG_CHOICE="en"
case "$LANG_CHOICE" in
  en) T_WELCOME="Welcome to NVazen"; T_LANG="Language"; T_NEXT="Next"; T_EXIT="Exit"
      T_DISK="Select target disk (ALL DATA WILL BE LOST)"; T_FS="Select filesystem"
      T_USER="Username"; T_HOST="Hostname"; T_PASS="Password"; T_ROOTPASS="Root password"
      T_CONFIRM="Confirm installation"; T_START="Start Installation"; T_BACK="Back"
      T_INSTALLING="Installing NVazen..."; T_DONE="Installation complete! Reboot now."
      T_FAIL="Installation failed. Check log."; T_VIEWLOG="View Log"; T_CLOSE="Close"
      ;;
  zh) T_WELCOME="欢迎安装 NVazen"; T_LANG="语言"; T_NEXT="下一步"; T_EXIT="退出"
      T_DISK="选择安装磁盘（所有数据将被清空）"; T_FS="选择文件系统"
      T_USER="用户名"; T_HOST="主机名"; T_PASS="密码"; T_ROOTPASS="Root 密码"
      T_CONFIRM="确认安装信息"; T_START="开始安装"; T_BACK="返回"
      T_INSTALLING="正在安装 NVazen..."; T_DONE="安装完成！请重启系统"
      T_FAIL="安装失败，请查看日志"; T_VIEWLOG="查看日志"; T_CLOSE="关闭"
      ;;
esac

# 依赖检查
command -v kdialog >/dev/null || { echo "缺少 kdialog"; exit 1; }
[[ -x "$INSTALLER" ]] || { kdialog --error "找不到 $INSTALLER"; exit 1; }

# --- 1. 欢迎页 + 语言选择 ---
LANG_SEL=$(kdialog --title "NVazen Installer" --radiolist "Select language / 选择语言" \
  "en" "English" on "zh" "中文" off 2>/dev/null) || exit 0
[[ -n "$LANG_SEL" ]] && LANG_CHOICE="$LANG_SEL"

kdialog --title "NVazen Installer" --msgbox \
  "$T_WELCOME\n\nNVazen Linux\n基于 Arch Linux 的轻量桌面系统\n\n安装将清空你选择的整个磁盘。" 2>/dev/null || exit 0

# --- 2. 选择磁盘 ---
DISK_LIST=$(lsblk -dpno NAME,SIZE,MODEL | grep -E '/dev/(sd|nvme|vd|mmcblk)' || true)
[[ -n "$DISK_LIST" ]] || { kdialog --error "未检测到可安装的磁盘"; exit 1; }

DISK_MENU=""
while read -r name size model; do
  DISK_MENU+="$name|$name  ($size) $model\n"
done <<< "$DISK_LIST"

TARGET_DISK=$(echo -e "$DISK_MENU" | kdialog --title "NVazen Installer" --menu "$T_DISK" 2>/dev/null)
[[ -n "$TARGET_DISK" ]] || exit 0
TARGET_DISK="${TARGET_DISK%%|*}"
[[ -b "$TARGET_DISK" ]] || { kdialog --error "无效磁盘: $TARGET_DISK"; exit 1; }

# --- 3. 选择文件系统 ---
FS_TYPE=$(kdialog --title "NVazen Installer" --radiolist "$T_FS" \
  "ext4" "ext4 (稳定，兼容)" on \
  "btrfs" "btrfs (快照，压缩)" off 2>/dev/null) || exit 0
[[ -n "$FS_TYPE" ]] || FS_TYPE="ext4"

# --- 4. 用户信息 ---
HOSTNAME=$(kdialog --title "NVazen Installer" --inputbox "$T_HOST" "nvazen" 2>/dev/null) || exit 0
[[ -n "$HOSTNAME" ]] || exit 0

USERNAME=$(kdialog --title "NVazen Installer" --inputbox "$T_USER" "nvazen" 2>/dev/null) || exit 0
[[ -n "$USERNAME" ]] || exit 0

USER_PASS=$(kdialog --title "NVazen Installer" --password "$T_PASS" 2>/dev/null) || exit 0
[[ -n "$USER_PASS" ]] || { kdialog --error "密码不能为空"; exit 1; }

USER_PASS2=$(kdialog --title "NVazen Installer" --password "确认密码" 2>/dev/null) || exit 0
[[ "$USER_PASS" == "$USER_PASS2" ]] || { kdialog --error "两次密码不一致"; exit 1; }

ROOT_PASS=$(kdialog --title "NVazen Installer" --password "$T_ROOTPASS (留空则与用户密码相同)" 2>/dev/null) || exit 0
: "${ROOT_PASS:=$USER_PASS}"

# --- 5. 确认摘要 ---
kdialog --title "NVazen Installer" --yesno "$T_CONFIRM

磁盘: $TARGET_DISK
文件系统: $FS_TYPE
主机名: $HOSTNAME
用户名: $USERNAME
时区: UTC
语言: $LANG_CHOICE

确认开始安装？" 2>/dev/null || exit 0

# --- 6. 执行安装 ---
export NV_TARGET_DISK="$TARGET_DISK"
export NV_HOSTNAME="$HOSTNAME"
export NV_USERNAME="$USERNAME"
export NV_USER_PASS="$USER_PASS"
export NV_ROOT_PASS="$ROOT_PASS"
export NV_FS_TYPE="$FS_TYPE"
export NV_TIMEZONE="UTC"
export NV_LOCALE="en_US.UTF-8"
export NV_KEYMAP="us"
export NV_YES=1

rm -f "$LOG"
touch "$LOG"

# 后台运行安装
setsid bash -c "\"$INSTALLER\" >\"$LOG\" 2>&1; echo \$? > /tmp/nvazen-install.rc" &

# 进度窗口
(
  while kill -0 $! 2>/dev/null; do
    tail -n 200 "$LOG" 2>/dev/null
    sleep 1
  done
  echo "安装进程已结束"
) | kdialog --title "NVazen Installer" --progressbar "$T_INSTALLING" 0 2>/dev/null &
PROGRESS_PID=$!

wait $!

RC=$(cat /tmp/nvazen-install.rc 2>/dev/null || echo 1)
if [[ "$RC" == "0" ]]; then
  kdialog --title "NVazen Installer" --msgbox "$T_DONE" 2>/dev/null
  reboot -f
else
  kdialog --title "NVazen Installer" --yesno "$T_FAIL\n\n$LOG" --yes-label "$T_VIEWLOG" --no-label "$T_CLOSE" 2>/dev/null && \
    kdialog --textbox "$LOG" 800 600 2>/dev/null
fi
GUI_EOF

chmod 755 ~/nvinstall/gui.sh
