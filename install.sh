cat > ~/nvinstall/install.sh <<'INSTALL_EOF'
#!/usr/bin/env bash
set -euo pipefail
umask 022

# ============================================================
#  NVazen 安装器 - 核心逻辑
#  环境变量:
#    NV_TARGET_DISK  目标磁盘
#    NV_HOSTNAME     主机名
#    NV_USERNAME     用户名
#    NV_USER_PASS    用户密码
#    NV_ROOT_PASS    root 密码
#    NV_FS_TYPE      文件系统 (ext4 / btrfs)
#    NV_TIMEZONE     时区
#    NV_LOCALE       语言
#    NV_KEYMAP       键盘布局
#    NV_YES          自动确认 (1=跳过确认)
# ============================================================

TARGET_DISK="${NV_TARGET_DISK:-}"
HOSTNAME="${NV_HOSTNAME:-nvazen}"
USERNAME="${NV_USERNAME:-nvazen}"
USER_PASS="${NV_USER_PASS:-}"
ROOT_PASS="${NV_ROOT_PASS:-$USER_PASS}"
FS_TYPE="${NV_FS_TYPE:-ext4}"
TIMEZONE="${NV_TIMEZONE:-UTC}"
LOCALE="${NV_LOCALE:-en_US.UTF-8}"
KEYMAP="${NV_KEYMAP:-us}"
RESOURCE_REPO="https://github.com/AzenDev2026/Azen_sys.resource/archive/refs/heads/main.tar.gz"
LOG_FILE="/tmp/nvazen-install.log"

log()  { echo -e "\e[1;34m[NVazen]\e[0m $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "\e[1;33m[警告]\e[0m $*" | tee -a "$LOG_FILE" >&2; }
die()  { echo -e "\e[1;31m[错误]\e[0m $*" | tee -a "$LOG_FILE" >&2; exit 1; }

exec > >(tee -a "$LOG_FILE") 2>&1

# --- 前置检查 ---
[[ $EUID -eq 0 ]] || die "请用 root 运行。"
[[ -n "$TARGET_DISK" ]] || die "未指定目标磁盘。"
[[ -b "$TARGET_DISK" ]] || die "目标磁盘不存在：$TARGET_DISK"
[[ -n "$USER_PASS" ]] || die "未设置用户密码。"
[[ "$FS_TYPE" == "ext4" || "$FS_TYPE" == "btrfs" ]] || die "不支持的文件系统：$FS_TYPE (仅 ext4/btrfs)"

log "目标磁盘：$TARGET_DISK"
log "文件系统：$FS_TYPE"
log "主机名：$HOSTNAME"
log "用户名：$USERNAME"
lsblk "$TARGET_DISK"

if [[ "${NV_YES:-0}" != "1" ]]; then
  read -rp "确认清空 $TARGET_DISK 并安装？输入 YES：" ans
  [[ "$ans" == "YES" ]] || die "用户取消。"
fi

# --- 分区 ---
log "开始分区..."
umount "${TARGET_DISK}"* 2>/dev/null || true
swapoff -a 2>/dev/null || true

wipefs -a "$TARGET_DISK" 2>/dev/null || true
dd if=/dev/zero of="$TARGET_DISK" bs=1M count=10 conv=fsync status=progress
sync
partprobe "$TARGET_DISK" 2>/dev/null || true
sleep 2
sgdisk --zap-all "$TARGET_DISK" 2>/dev/null || true
partprobe "$TARGET_DISK" 2>/dev/null || true
sleep 2

# 分区前缀
PART_PREFIX="$TARGET_DISK"
case "$TARGET_DISK" in
  *nvme*|*mmcblk*|*loop*) PART_PREFIX="${TARGET_DISK}p" ;;
esac

EFI_PART="${PART_PREFIX}1"

# EFI + SWAP + ROOT
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$TARGET_DISK"
sgdisk -n 2:0:+4G   -t 2:8200 -c 2:"SWAP" "$TARGET_DISK"
sgdisk -n 3:0:0     -t 3:8300 -c 3:"ROOT" "$TARGET_DISK"

ROOT_PART="${PART_PREFIX}3"
SWAP_PART="${PART_PREFIX}2"

partprobe "$TARGET_DISK" 2>/dev/null || true
sleep 3

# --- 格式化 ---
log "格式化 EFI..."
mkfs.fat -F32 -n EFI "$EFI_PART"

if [[ "$FS_TYPE" == "btrfs" ]]; then
  log "格式化 ROOT (btrfs)..."
  mkfs.btrfs -f -L NVROOT "$ROOT_PART"
else
  log "格式化 ROOT (ext4)..."
  mkfs.ext4 -F -L NVROOT "$ROOT_PART"
fi

log "格式化 SWAP..."
mkswap -L NVSWAP "$SWAP_PART"

# --- 挂载 ---
log "挂载..."
if [[ "$FS_TYPE" == "btrfs" ]]; then
  mount "$ROOT_PART" /mnt
  btrfs subvolume create /mnt/@
  btrfs subvolume create /mnt/@home
  umount /mnt
  mount -o subvol=@,compress=zstd:3,noatime "$ROOT_PART" /mnt
  mkdir -p /mnt/home
  mount -o subvol=@home,compress=zstd:3,noatime "$ROOT_PART" /mnt/home
else
  mount "$ROOT_PART" /mnt
fi

mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi
swapon "$SWAP_PART"

# --- 选镜像 ---
log "选择镜像源..."
for i in {1..15}; do ping -c 1 -W 1 archlinux.org &>/dev/null && break; sleep 2; done

MIRRORS=(
  "https://mirrors.ustc.edu.cn/archlinux"
  "https://mirrors.tuna.tsinghua.edu.cn/archlinux"
  "https://mirrors.huaweicloud.com/archlinux"
  "https://mirrors.cloud.tencent.com/archlinux"
)
BEST=""
BEST_TIME=9999
for m in "${MIRRORS[@]}"; do
  t=$(curl -s -o /dev/null -w "%{time_total}" --max-time 10 "$m/core/os/x86_64/core.db" 2>/dev/null || echo 9999)
  log "  $m → ${t}s"
  if awk "BEGIN{exit !($t < $BEST_TIME)}"; then BEST="$m"; BEST_TIME="$t"; fi
done
[[ -n "$BEST" ]] || die "无可用镜像"

cat > /etc/pacman.d/mirrorlist <<EOF
Server = $BEST/\$repo/os/\$arch
Server = https://mirrors.ustc.edu.cn/archlinux/\$repo/os/\$arch
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/\$repo/os/\$arch
EOF

# 并行下载
grep -q '^ParallelDownloads' /etc/pacman.conf && \
  sed -i 's/^ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf || \
  sed -i '/^\[options\]/a ParallelDownloads = 10' /etc/pacman.conf
sed -i '/^XferCommand/d' /etc/pacman.conf

pacman-key --init 2>/dev/null || true
pacman-key --populate archlinux 2>/dev/null || true

# --- pacstrap ---
log "安装基础系统..."
rm -f /mnt/var/lib/pacman/db.lck 2>/dev/null || true

PKGS="base base-devel linux linux-firmware networkmanager sudo grub efibootmgr os-prober"
[[ "$FS_TYPE" == "btrfs" ]] && PKGS="$PKGS btrfs-progs"

yes | pacstrap -K /mnt $PKGS

log "生成 fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# --- 资源下载 ---
log "下载 NVazen 资源..."
TMP=$(mktemp -d)
curl -L --retry 3 --max-time 180 "$RESOURCE_REPO" -o "$TMP/res.tar.gz" || die "资源下载失败"
tar -xzf "$TMP/res.tar.gz" -C "$TMP"
RD=$(find "$TMP" -maxdepth 1 -type d -name 'Azen_sys.resource-*' | head -1)
[[ -n "$RD" ]] || die "资源目录未找到"

[ -d "$RD/etc" ] && cp -a "$RD/etc/." /mnt/etc/
[ -d "$RD/usr" ] && cp -a "$RD/usr/." /mnt/usr/

# --- chroot 配置 ---
log "配置系统..."
arch-chroot /mnt /bin/bash -e <<CHROOT_EOF
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

echo "${LOCALE} UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
HOSTS

echo "root:${ROOT_PASS}" | chpasswd
if ! id "${USERNAME}" &>/dev/null; then
  useradd -m -G wheel,video,audio,storage,optical -s /bin/bash "${USERNAME}"
fi
echo "${USERNAME}:${USER_PASS}" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel

rm -f /etc/machine-id
systemd-machine-id-setup

systemctl enable NetworkManager
systemctl enable sddm

# SDDM Qt6 greeter
if [ -x /usr/bin/sddm-greeter-qt6 ] && [ ! -L /usr/bin/sddm-greeter ]; then
  mv /usr/bin/sddm-greeter /usr/bin/sddm-greeter-qt5.bak 2>/dev/null || true
  ln -sf /usr/bin/sddm-greeter-qt6 /usr/bin/sddm-greeter
fi

# btrfs hook
if [[ "$FS_TYPE" == "btrfs" ]]; then
  sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/' /etc/mkinitcpio.conf
fi

mkinitcpio -P

if [ -d /sys/firmware/efi ]; then
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=NVazen --recheck
else
  grub-install --target=i386-pc --recheck "${TARGET_DISK}"
fi

grep -q '^GRUB_DISABLE_OS_PROBER' /etc/default/grub || \
  echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT_EOF

# --- 收尾 ---
log "清理..."
sync
swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || umount -l /mnt 2>/dev/null || true

log "✅ 安装完成！"
INSTALL_EOF

chmod 755 ~/nvinstall/install.sh
