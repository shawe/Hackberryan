#!/bin/bash

sudo dd if=sunxi-spl-1GB.bin of=/dev/mmcblk0 bs=1024 seek=8
sudo dd if=u-boot-1GB.bin of=/dev/mmcblk0 bs=1024 seek=32
sudo sync
