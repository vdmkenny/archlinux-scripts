#!/bin/bash
#Archlinux install script by vdmkenny
#Note this script installs archlinux to my personal preferences, and asks no questions
#It makes lots of assumptions, and may/will not work out of the box for you

#settings
installdisk="/dev/sda"
homesize="10G"
extrapackages="vim htop firefox evolution lvm2 pidgin terminator vagrant vlc wget"
hostname="trappist"
username="vdmkenny"
userpass="supersecretpassword"

#Check for internet connection
echo * Checking internet connection...
if ! ping -c 1 8.8.8.8 &> /dev/null
then
	echo "You have no internet connection. Can't install without."
	exit 1
fi

#check if install device exists
if [ ! -f ${installdisk} ]; then
    echo "${installdisk} not found. Exiting."
    exit 1
fi

#Check if we are on an EFI system

if [ -f /sys/firmware/efi/efivars ]; then
    echo "EFI system detected."
    EFI=true
else
    echo "Legacy system detected."
    EFI=false
fi

#Enable NTP
timedatectl set-ntp true

#format disk and partition
if $EFI; then
fdisk ${installdisk} <<EOF
g
n
1
2048
+256M
t
1
n
2


w
EOF
mkfs.fat -F32 /dev/sda1
else
fdisk ${installdisk} <<EOF
g
n
1


w
EOF
fi

#create LVM volume
if $EFI; then
	pvcreate ${installdisk}2
	vgcreate system ${installdisk}2
else
	pvcreate ${installdisk}1
	vgcreate system ${installdisk}1
fi
lvcreate -L ${homesize} system -n lvm-home
lvcreate -l +100%FREE system -n lvm-root 

#partition disks
mkfs.xfs /dev/mapper/system-lvm--root
mkfs.xfs /dev/mapper/system-lvm--home

#edit mkinitcpio hooks for lvm boot
sed -i "/^HOOKS/c\HOOKS\= \"base udev autodetect modconf block lvm2 filesystems keyboard fsck\"/" /etc/mkinitcpio.conf

#set mirrorlist to kangaroot
echo "Server = http://archlinux.mirror.kangaroot.net/$repo/os/$arch" > /etc/pacman.d/mirrorlist

#create mountpoints
mkdir -p /mnt /mnt/boot /mnt/home

#mount disks
mount /dev/mapper/system-lvm--root /mnt
mount /dev/mapper/system-lvm--home /mnt/home
mount /dev/sda1 /mnt/boot

#pacstrap all the things
pacstrap /mnt base base-devel gnome gnome-tweak-tool pwgen zsh ${extrapackages}

#generate fstab file
genfstab -U /mnt > /mnt/etc/fstab

#chroot into new fs
arch-chroot /mnt

#set timezone
ln -sf /usr/share/zoneinfo/Europe/Brussels /etc/localtime

#set hardware clock
hwclock --systohc

#set locale
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "nl_BE.UTF-8 UTF-8" >> /etc/locale.gen
echo "fr_BE.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

#set hostname
echo ${hostname} > /etc/hostname

#double tap initramfs to be sure
mkinitcpio -p linux

#set rootpw to something random
randompw=$(pwgen -c -n -y | head -n 1)
echo root:${randompw} | chpasswd

useradd -m -d /home/${username}/ -s /bin/zsh -g wheel ${username}
