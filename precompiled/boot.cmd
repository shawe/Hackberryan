setenv bootargs console=tyS0,115200 root=/dev/mmcblk0p2 rootwait panic=10 
fatload mmc 0 0x43000000 script.bin
fatload mmc 0 0x48000000 uImage
bootm 0x48000000
