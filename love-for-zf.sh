#!/usr/bin/env bash

_PACKAGES="fvwm xf86-video-qxl xterm xorg-server xorg-fonts-75dpi ttf-dejavu xorg-xinit"
_USER="arch"
_HOSTNAME="vm"
_LANG="en_US.UTF-8"
_KEYMAP="us"
_TIMEZONE="UTC"

printf "\nArch VM bootstrapping script for zf (written out of pure love)\n(close to 0 checks so you better not fuck up)\n"

if [[ -z ${1} ]]; then
    printf "Usage:\t${0} <blockdev>\ne.g.\t${0} /dev/sda\n"
    lsblk -p
    exit 1
fi

if [[ ! -b ${1} ]]; then
    printf "ERROR: ${1} is not a block device" >&2
    lsblk -p
    exit 2
fi

# Update the system clock
timedatectl set-ntp true

# Partition the disks
fdisk -w always ${1} <<EOF
o
n
p
1


a
w
EOF

# Just to be sure
partprobe ${1}
sleep 1

# Format the partitions
yes | mkfs.ext4 ${1}1

# Just to be sure
partprobe ${1}
sleep 1

# UUID
_UUID=$(lsblk -n -o UUID ${1} | tr -d "[:space:]")

# Mount the file systems
mount /dev/disk/by-uuid/${_UUID} /mnt

# Install the base packages
pacstrap /mnt base base-devel syslinux ${_PACKAGES}

# Fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot
arch-chroot /mnt <<EOF
# Time zone
ln -sf /usr/share/zoneinfo/${_TIMEZONE} /etc/localtime
hwclock --systohc
# Localization
sed -i "s/#${_LANG}/${_LANG}/g" /etc/locale.gen
printf "LANG=${_LANG}\n" > /etc/locale.conf
locale-gen
# Network configuration
printf "${_HOSTNAME}" > /etc/hostname
printf "127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t${_HOSTNAME}.localdomain\t${_HOSTNAME}\n" >> /mnt/etc/hosts
systemctl enable dhcpcd
# Boot loader
syslinux-install_update -i -a -m
sed -i "s/\/dev\/sda3/UUID=${_UUID}/g" /boot/syslinux/syslinux.cfg
# User
useradd -m -g wheel ${_USER}
# Sudo
printf "%%wheel ALL=(ALL) NOPASSWD: ALL\n" > /etc/sudoers.d/01_wheel
# Start X on login (tty1)
printf "exec fvwm\n" > /home/${_USER}/.xinitrc
chown ${_USER}:wheel /home/${_USER}/.xinitrc
printf 'if [[ ! \$DISPLAY && \$XDG_VTNR -le 1 ]]; then\n    startx\nfi\n' >> /home/${_USER}/.bash_profile
# Autologin
mkdir /etc/systemd/system/getty@tty1.service.d/
printf "[Service]\nType=simple\nExecStart=\nExecStart=-/usr/bin/agetty --autologin ${_USER} --noclear %%I \$TERM\n" > /etc/systemd/system/getty@tty1.service.d/override.conf
EOF

# Root Password
printf "Change password for user \'root\'\n"
arch-chroot /mnt bash -i -c "passwd root"
printf "Change password for user \'${_USER}\'\n"
arch-chroot /mnt bash -i -c "passwd ${_USER}"

umount -R /mnt

printf "Done! Hit the reboot boi!\n"
