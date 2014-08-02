update-rc.d alsa-utils defaults
update-rc.d cpufrequtils defaults
update-rc.d lirc defaults
update-rc.d bootsplash defaults
update-rc.d brcm40183-patch defaults
update-rc.d disable_led.sh defaults
update-rc.d bluetooth defaults
update-rc.d loadcpufreq defaults
cp /etc/modules.current /etc/modules
mv /boot/boot.scr /boot/boot.scr.disabled
dd if=/boot/uboot.bin of=/dev/mmcblk0 bs=1024 seek=8