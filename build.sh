#!/bin/bash

# --- Configuration -------------------------------------------------------------
VERSION="CTDebian 1.3"
DEST_LANG="en_US"
DEST_LANGUAGE="en"
DEST=/tmp/Cubie
DISPLAY=3  # "0:none; 1:lcd; 2:tv; 3:hdmi; 4:vga"
# --- End -----------------------------------------------------------------------
SRC=$(pwd)
set -e

#Requires root ..
if [ "$UID" -ne 0 ]
  then echo "Please run as root"
  exit
fi
echo "Building Cubietruck-Debian in $DEST from $SRC"
sleep 3
#--------------------------------------------------------------------------------
# Downloading necessary files
#--------------------------------------------------------------------------------
echo "------ Downloading necessary files"
apt-get -qq -y install binfmt-support bison build-essential ccache debootstrap flex gawk gcc-arm-linux-gnueabi gcc-arm-linux-gnueabihf gettext git linux-headers-generic linux-image-generic lvm2 qemu-user-static texinfo texlive u-boot-tools uuid-dev zlib1g-dev unzip libncurses5-dev pkg-config libusb-1.0-0-dev

#--------------------------------------------------------------------------------
# Preparing output / destination files
#--------------------------------------------------------------------------------

echo "------ Fetching files from github"
mkdir -p $DEST/output
cp output/uEnv.txt $DEST/output

if [ -d "$DEST/u-boot-sunxi" ]
then
	cd $DEST/u-boot-sunxi ; git pull; cd $SRC
else
	git clone https://github.com/cubieboard/u-boot-sunxi $DEST/u-boot-sunxi # Boot loader
fi
if [ -d "$DEST/sunxi-tools" ]
then
	cd $DEST/sunxi-tools; git pull; cd $SRC
else
	git clone https://github.com/linux-sunxi/sunxi-tools.git $DEST/sunxi-tools # Allwinner tools
fi
if [ -d "$DEST/cubie_configs" ]
then
	cd $DEST/cubie_configs; git pull; cd $SRC
else
	git clone https://github.com/cubieboard/cubie_configs $DEST/cubie_configs # Hardware configurations
fi
if [ -d "$DEST/linux-sunxi" ]
then
	cd $DEST/linux-sunxi; git pull -f; cd $SRC
else
	git clone https://github.com/cubieboard/linux-sunxi/ $DEST/linux-sunxi # Kernel 3.4.61+
fi

# Applying Patch for 2gb memory
patch -f $DEST/u-boot-sunxi/include/configs/sunxi-common.h < patch/memory.patch || true
# Applying Patch for gpio
patch -f $DEST/linux-sunxi/drivers/gpio/gpio-sunxi.c < patch/gpio.patch || true

#Change Video output ( TODO add a param so the user can choose that ?)
sed -e 's/output_type = [0-9]*/output_type = '$DISPLAY'/g' $DEST/cubie_configs/sysconfig/linux/cubietruck.fex > $DEST/cubie_configs/sysconfig/linux/cubietruck-vga.fex

# Copying Kernel config
cp $SRC/config/kernel.config $DEST/linux-sunxi/

#--------------------------------------------------------------------------------
# Compiling everything
#--------------------------------------------------------------------------------
#if false; then
echo "------ Compiling kernel boot loaderb"
cd $DEST/u-boot-sunxi
# boot loader
make clean && make -j2 'cubietruck' CROSS_COMPILE=arm-linux-gnueabihf-
echo "------ Compiling sunxi tools"
cd $DEST/sunxi-tools
# sunxi-tools
make clean && make fex2bin
cp fex2bin /usr/bin/
# hardware configuration
fex2bin $DEST/cubie_configs/sysconfig/linux/cubietruck-vga.fex $DEST/output/script.bin
fex2bin $DEST/cubie_configs/sysconfig/linux/cubietruck.fex $DEST/output/script-hdmi.bin

# kernel image
echo "------ Compiling kernel"
cd $DEST/linux-sunxi
make clean
make -j2 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- sun7i_defconfig
# get proven config
cp $DEST/linux-sunxi/kernel.config $DEST/linux-sunxi/.config
make -j2 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- uImage modules
make -j2 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_MOD_PATH=output modules_install
#fi

#--------------------------------------------------------------------------------
# Creating SD Images
#--------------------------------------------------------------------------------
echo "------ Creating SD Images"
cd $DEST/output
# create 1Gb image and mount image to /dev/loop0
dd if=/dev/zero of=debian_rootfs.raw bs=1M count=1000
umount -l /dev/loop0 || true
umount -l /dev/loop1 || true
losetup -d /dev/loop0 || true
losetup -d /dev/loop1 || true
losetup /dev/loop0 debian_rootfs.raw 

echo "------ Partitionning and mounting filesystem"
# make image bootable
dd if=$DEST/u-boot-sunxi/u-boot-sunxi-with-spl.bin of=/dev/loop0 bs=1024 seek=8

# create one partition starting at 2048 which is default
(echo n; echo p; echo 1; echo; echo; echo w) | fdisk /dev/loop0 >> /dev/null || true
# just to make sure
partprobe

# 2048 (start) x 512 (block size) = where to mount partition
losetup -o 1048576 /dev/loop1  /dev/loop0
# create filesystem
mkfs.ext4 /dev/loop1
# create mount point and mount image 
mkdir -p $DEST/output/sdcard/
mount /dev/loop1 $DEST/output/sdcard/



echo "------ Install basic filesystem"
# install base system
debootstrap --no-check-gpg --arch=armhf --foreign wheezy $DEST/output/sdcard/
# we need this
cp /usr/bin/qemu-arm-static $DEST/output/sdcard/usr/bin/
# second stage
chroot $DEST/output/sdcard /bin/bash -c "/debootstrap/debootstrap --second-stage"

# update /etc/issue
cat <<EOT > $DEST/output/sdcard/etc/issue
Debian GNU/Linux 7 $VERSION \n \l
EOT

# apt list
cat <<EOT > $DEST/output/sdcard/etc/apt/sources.list
deb http://http.debian.net/debian wheezy main contrib non-free
deb-src http://http.debian.net/debian wheezy main contrib non-free
deb http://http.debian.net/debian wheezy-updates main contrib non-free
deb-src http://http.debian.net/debian wheezy-updates main contrib non-free
deb http://security.debian.org/debian-security wheezy/updates main contrib non-free
deb-src http://security.debian.org/debian-security wheezy/updates main contrib non-free
EOT

# update
chroot $DEST/output/sdcard /bin/bash -c "apt-get update"
chroot $DEST/output/sdcard /bin/bash -c "export LANG=C"    

# set up 'apt
cat <<END > $DEST/output/sdcard/etc/apt/apt.conf.d/71-no-recommends
APT::Install-Recommends "0";
APT::Install-Suggests "0";
END

# script to turn off the LED blinking
cp $SRC/scripts/disable_led.sh $DEST/output/sdcard/etc/init.d/disable_led.sh

# make it executable
chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/disable_led.sh"
# and startable on boot
chroot $DEST/output/sdcard /bin/bash -c "update-rc.d disable_led.sh defaults" 

# scripts for autoresize at first boot from cubian
cd $DEST/output/sdcard/etc/init.d
cp $SRC/scripts/cubian-resize2fs $DEST/output/sdcard/etc/init.d
cp $SRC/scripts/cubian-firstrun $DEST/output/sdcard/etc/init.d

# make it executable
chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/cubian-*"
# and startable on boot
chroot $DEST/output/sdcard /bin/bash -c "update-rc.d cubian-firstrun defaults" 
# install and configure locales
chroot $DEST/output/sdcard /bin/bash -c "apt-get -qq -y install locales"
# reconfigure locales
echo -e $DEST_LANG'.UTF-8 UTF-8\n' > $DEST/output/sdcard/etc/locale.gen 
chroot $DEST/output/sdcard /bin/bash -c "locale-gen"
echo -e 'LANG="'$DEST_LANG'.UTF-8"\nLANGUAGE="'$DEST_LANG':'$DEST_LANGUAGE'"\n' > $DEST/output/sdcard/etc/default/locale
chroot $DEST/output/sdcard /bin/bash -c "export LANG=$DEST_LANG.UTF-8"
chroot $DEST/output/sdcard /bin/bash -c "apt-get -qq -y install openssh-server ca-certificates module-init-tools dhcp3-client udev ifupdown iproute dropbear iputils-ping ntpdate usbutils uboot-envtools pciutils wireless-tools wpasupplicant procps libnl-dev parted cpufreqd cpufrequtils console-setup unzip bridge-utils" 
chroot $DEST/output/sdcard /bin/bash -c "apt-get -qq -y upgrade"

# configure MIN / MAX Speed for cpufrequtils
sed -e 's/MIN_SPEED="0"/MIN_SPEED="30000"/g' -i $DEST/output/sdcard/etc/init.d/cpufrequtils
sed -e 's/MAX_SPEED="0"/MAX_SPEED="1000000"/g' -i $DEST/output/sdcard/etc/init.d/cpufrequtils

# set password to 1234
chroot $DEST/output/sdcard /bin/bash -c "(echo 1234;echo 1234;) | passwd root" 

# set hostname 
echo cubie > $DEST/output/sdcard/etc/hostname

# load modules
cat <<EOT >> $DEST/output/sdcard/etc/modules
gpio_sunxi
bcmdhd
sunxi_gmac
EOT

# create interfaces configuration
cat <<EOT >> $DEST/output/sdcard/etc/network/interfaces
auto eth0 wlan0
allow-hotplug eth0
iface eth0 inet dhcp
        hwaddress ether AE:50:30:27:5A:CF # change this
        pre-up /sbin/ifconfig eth0 mtu 3838 # setting MTU for DHCP, static just: mtu 3838
allow-hotplug wlan0
iface wlan0 inet dhcp
    wpa-ssid SSID 
    wpa-psk xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# to generate proper encrypted key: wpa_passphrase yourSSID yourpassword
EOT

# enable serial console (Debian/sysvinit way)
echo T0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100 >> $DEST/output/sdcard/etc/inittab

cp $DEST/output/uEnv.txt $DEST/output/sdcard/boot/
cp $DEST/output/script.bin $DEST/output/sdcard/boot/
cp $DEST/linux-sunxi/arch/arm/boot/uImage $DEST/output/sdcard/boot/

cp -R $DEST/linux-sunxi/output/lib/modules $DEST/output/sdcard/lib/
cp -R $DEST/linux-sunxi/output/lib/firmware/ $DEST/output/sdcard/lib/

cd $DEST/output/sdcard/lib/firmware
wget https://www.dropbox.com/s/o3evaiuidtg6xb5/ap6210.zip
unzip ap6210.zip
rm ap6210.zip
cd $DEST/

# sunxi tools 
#cd $DEST/output/sdcard/usr/sbin
#wget https://www.dropbox.com/s/ns4h1ddmta1h6i9/tools-arm-bin.zip
#unzip tools-arm-bin.zip
#rm tools-arm-bin.zip
#cd $DEST/
# sunxi-tools
cd $DEST/sunxi-tools
make clean && make -j2 'fex2bin' CC=arm-linux-gnueabihf-gcc && make -j2 'bin2fex' CC=arm-linux-gnueabihf-gcc
cp fex2bin $DEST/output/sdcard/usr/bin/ 
cp bin2fex $DEST/output/sdcard/usr/bin/

# cleanup 
rm $DEST/output/sdcard/usr/bin/qemu-arm-static 
# umount images 
umount $DEST/output/sdcard/ 
losetup -d /dev/loop1 
losetup -d /dev/loop0
# compress image 
gzip $DEST/output/*.raw
