#!/bin/bash
#Archlinux install script by vdmkenny
#Note this script installs archlinux to my personal preferences, and asks no questions
#It makes lots of assumptions, and may/will not work out of the box for you

#settings
installdisk="/dev/sda"
homesize="3G"
extrapackages="vim htop firefox evolution lvm2 pidgin terminator vagrant vlc wget"
hostname="trappist"
username="vdmkenny"
userpass="supersecretpassword"

echo "Get ready to Arch!!!"
echo ""

#Check for internet connection
echo "Checking internet connection..."
if ! ping -c 1 8.8.8.8 &> /dev/null
then
	echo "You have no internet connection. Can't install without."
	exit 1
fi

#check if install device exists
echo "Checking for disk ${installdisk}"
if ! ls ${installdisk}; then
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
echo "Enabling NTP"
timedatectl set-ntp true

#format disk and partition
echo "Partitioning disk ${installdisk}"
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
echo "Formatting ESP"
mkfs.fat -F32 /dev/sda1

else
fdisk ${installdisk} <<EOF
n
p
1


w
EOF

fi

#create LVM volume
echo "Creating LVM volume 'system'"
if $EFI; then
	pvcreate ${installdisk}2
	vgcreate system ${installdisk}2
else
	pvcreate ${installdisk}1
	vgcreate system ${installdisk}1
fi
echo 'Creating home and root volumes'
lvcreate -L ${homesize} system -n lvm-home
lvcreate -l +100%FREE system -n lvm-root 

#format disks
echo "Formatting root/home LVs to XFS"
mkfs.xfs /dev/mapper/system-lvm--root
mkfs.xfs /dev/mapper/system-lvm--home

#edit mkinitcpio hooks for lvm boot
echo "Editing mkinitcpio hooks for LVM boot"
sed -i "/^HOOKS/c\HOOKS\= \"base udev autodetect modconf block lvm2 filesystems keyboard fsck\"/" /etc/mkinitcpio.conf

#set mirrorlist to kangaroot
echo "Setting mirrorlist to kangaroot"
echo 'Server = http://archlinux.mirror.kangaroot.net/$repo/os/$arch' > /etc/pacman.d/mirrorlist

#create mountpoints
echo "Creating mountpoints"
mkdir -p /mnt /mnt/boot /mnt/home

#mount disks
echo "Mounting disks"
mount /dev/mapper/system-lvm--root /mnt
mount /dev/mapper/system-lvm--home /mnt/home
if $EFI; then
    mount /dev/sda1 /mnt/boot
fi

#pacstrap all the things
echo "Pacstrapping root"
pacstrap /mnt base base-devel gnome gnome-tweak-tool pwgen zsh ${extrapackages}

#generate fstab file
echo "Generating fstab"
genfstab -U /mnt > /mnt/etc/fstab

#chroot into new fs
echo "Chrooting to new root"
arch-chroot /mnt

#set timezone
echo "Setting timezone to Brussels"
ln -sf /usr/share/zoneinfo/Europe/Brussels /etc/localtime

#set hardware clock
echo "Setting hardware clock"
hwclock --systohc

#set locale
echo "Generating locales"
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "nl_BE.UTF-8 UTF-8" >> /etc/locale.gen
echo "fr_BE.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

#set hostname
echo "Setting hostname to ${hostname}"
echo ${hostname} > /etc/hostname

#double tap initramfs to be sure
echo "Re-generating initramfs"
mkinitcpio -p linux

#set rootpw to something random
echo "Randomizing root password"
randompw=$(pwgen -c -n -y | head -n 1)
echo root:${randompw} | chpasswd

#add defined user
echo "Adding user ${username}"
useradd -m -d /home/${username}/ -s /bin/zsh -G wheel ${username}
echo ${username}:${userpass} | chpasswd

#install bootloader, systemdboot for EFI, grub for BIOS.
if $EFI; then
    echo "Installing systemdboot"
    bootctl --path=/boot install
    bootfile="default  arch
timeout  4
editor   0"
    touch /boot/loader/loader.conf
    echo ${bootfile} > /boot/loader/loader.conf
    
    archloader="title          Arch Linux
linux          /vmlinuz-linux
initrd         /initramfs-linux.img
options        root=/dev/mapper/system-lvm--root rw"
    touch /boot/loader/entries/arch.conf
    echo ${archloader} > /boot/loader/entries/arch.conf

   
else
    echo "Installing GRUB"
    pacman -S grub --noconfirm
    grub-install --target=i386-pc ${installdisk}
    grub-mkconfig -o /boot/grub/grub.cfg
fi

echo "Enabling GDM"
systemctl enable gdm

echo "Exiting chroot environment"
exit

echo "Unmounting partitions"
umount -R /mnt

echo "Rebooting NOW"
reboot now
