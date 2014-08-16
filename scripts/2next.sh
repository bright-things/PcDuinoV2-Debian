update-rc.d alsa-utils remove
update-rc.d cpufrequtils remove
update-rc.d lirc remove
update-rc.d bootsplash remove
update-rc.d brcm40183-patch remove
update-rc.d disable_led.sh remove
update-rc.d bluetooth remove
update-rc.d loadcpufreq remove
cp /etc/modules.next /etc/modules
mv /boot/boot.scr.disabled /boot/boot.scr
dd if=/boot/uboot-next.bin of=/dev/mmcblk0 bs=1024 seek=8