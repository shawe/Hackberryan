#!/bin/bash
###

# Using sources from:
# https://github.com/linux-sunxi
# http://rhombus-tech.net/allwinner_a10/hacking_the_mele_a1000/Building_Debian_From_Source_Code_for_Mele/
# http://rhombus-tech.net/allwinner_a10/hacking_the_mele_a1000/script_for_installing_debian_on_sdcard/
# http://www.cnx-software.com/2012/04/28/how-to-create-your-own-debian-ubuntu-image-for-mele-a1000-allwinner-a10-based-stb/#ixzz1xf1zQ2u6
# https://github.com/cnxsoft/a10-bin/tree/master/armhf/lib
# http://library.gnome.org/users/zenity/stable/question.html.es

# If can't umount some mountpoint path use:
# sudo fuser -km /your/mountpoint/path

# For enable/disable debug messages
DEBUG=true
#DEBUG=false

YELLOW="\033[1;33m"
GREEN="\033[1;32m"
RED="\033[1;31m"
BLUE="\033[1;34m"
BLUEs="\033[1;36m"
WHITE="\033[1;37m"
ENDCOLOR="\033[0m"
ECHO="echo -e"

msgErr(){
	$ECHO $RED"$1"$ENDCOLOR
	}
msgWarn(){
	if [ "$DEBUG" == "true" ]; then
		$ECHO $BLUE"$1"$ENDCOLOR
	fi
	}
msgOK(){
	$ECHO $GREEN"$1"$ENDCOLOR
	}
msgInfo(){
	$ECHO $WHITE"$1"$ENDCOLOR
	}
msgStatus(){
	$ECHO $YELLOW"$1"$ENDCOLOR
	}
msgList(){
	$ECHO $YELLOW"$1: "$GREEN"$2"$ENDCOLOR
}

# Initialize vars
LANGUAGE=""
LICENSE=""
DEVICE=""
HOSTNAME=""
MAC_ADDRESS=""
WORK_DIR=""
ARM_COMPILER_VERSION=""
IMG_LANG=""
ROOT_PASS=""
WIFI_NETWORK_NAME=""

# Warning user that debug is enabled
if [ "$DEBUG" == "true" ]; then
	msgInfo "WARNING: Debug mode is enabled!"
fi

# Auto-choose sudo command
if [ `which gksu | wc -w` -ge 1 ] ; then
	SUDOTOOL="gksu -u root"
elif [ `which sudo | wc -w` -ge 1 ] ; then
	SUDOTOOL="sudo"
fi
msgWarn "DEBUG: SUDO: ${SUDOTOOL}"
$SUDOTOOL "echo"

# Checking packages dependencies
if [ "`dpkg -al zenity | wc -w`" != "0" ] ; then
	msgInfo "zenity already installed"
else
	$SUDOTOOL "apt-get install zenity"
fi

if [ "`dpkg -al debootstrap | wc -w`" != "0" ] ; then
	msgInfo "debootstrap already installed"
else
	$SUDOTOOL "apt-get install debootstrap"
fi

if [ "`dpkg -al qemu-user-static | wc -w`" != "0" ] ; then
	msgInfo "qemu-user-static already installed"
else
	$SUDOTOOL "apt-get install qemu-user-static"
fi

if [ "`dpkg -al binfmt-support | wc -w`" != "0" ] ; then
	msgInfo "binfmt-support already installed"
else
	$SUDOTOOL "apt-get install binfmt-support"
fi

if [ "`lsmod | grep binfmt_misc | wc -l`" == "1" ] ; then
	msgInfo "Module binfmt_misc already loaded"
else
	$SUDOTOOL "modprobe binfmt_misc"
fi

if [ "`dpkg -al libusb-1.0-0-dev | wc -w`" != "0" ] ; then
	msgInfo "libusb-1.0-0-dev already installed"
else
	$SUDOTOOL "apt-get install libusb-1.0-0-dev"
fi

if [ "`dpkg -al qemu-kvm-extras-static | wc -w`" != "0" ] ; then
	msgInfo "qemu-kvm-extras-static already installed"
else
	$SUDOTOOL "apt-get install qemu-kvm-extras-static"
fi

if [ "`dpkg -al build-essential | wc -w`" != "0" ] ; then
	msgInfo "build-essential already installed"
else
	$SUDOTOOL "apt-get install build-essential"
fi

if [ "`dpkg -al git | wc -w`" != "0" ] ; then
	msgInfo "git already installed"
else
	$SUDOTOOL "apt-get install git"
fi

# Load predefined values if config file exists
if [ -f config ]; then
	msgInfo "File 'config' exists, loading configuration..."
	source config
else
	msgInfo "File 'config' not exists."
fi

# Language selector
while [ "${LANGUAGE}" == "" ]
do
	LANGUAGE=`zenity --list \
				--title="Choose your language" \
				--column="LANG" --column="Language" \
					"es_ES" "Español" \
					"en_US" "English"`
done
		
msgWarn "DEBUG: LANGUAGE: ${LANGUAGE}"
case $LANGUAGE in
	"es_ES")
		source languages/es_ES
		;;
	"en_US")
		source languages/en_US
		;;
	"")
		msgErr "ERROR: No language selected. Exiting..."
		exit 1
	;;
esac
msgWarn "DEBUG: ${STRING_LOADING_LANG}"

# License agreement
if [ "$LICENSE" == "" ]; then
	FILE=`dirname $0`/LICENSE

	zenity --text-info \
			--title="${STRING_LICENSE}" \
			--filename=$FILE \
			--checkbox="${STRING_AGREE}" \
			--width="550" \
			--height="450"

	LICENSE=$?
fi

msgWarn "DEBUG: LICENSE: ${LICENSE}"

case $LICENSE in
	0)
		msgWarn "DEBUG: ${STRING_LICENSE_ACCEPTED}"
		# Starting process
		
		# Select a device
		while [ "${DEVICE}" == "" ]
		do
			msgWarn "DEBUG: ${STRING_NO_DEVICE}"
			DEVICE=`ls /dev/sd* /dev/mmc* | zenity --list --title "${STRING_SELECT_DEVICE}" --text "${STRING_DEVICES_PLUGGED}" --column "${STRING_DEVICES}"`
		done
		msgWarn "DEBUG: DEVICE: ${DEVICE}"
		
		PART=""
		if [ `echo $DEVICE|grep mmc` ]; then
			PART="p"
		#else
			#PART="`echo $DEVICE | grep sd | sed 's/\/dev\/sd//g'`"
			# Explicitly specified, only need to include the partition number
		fi

		UBOOT_PART=$DEVICE$PART"1"
		ROOTFS_PART=$DEVICE$PART"2"
		
		msgWarn "DEBUG: DEVICE PART 1: ${UBOOT_PART}"
		msgWarn "DEBUG: DEVICE PART 2: ${ROOTFS_PART}"
		
		msgInfo "Forcing to umount any /dev/mmc* device..."
		sudo umount `mount | grep mmc | awk '{print $3}'` &> /dev/null
		# Falta añadir /dev/null para la salida estandar, sino hay nada montado no es necesario ver errores
		
		# Select a hostname
		while [ "${HOSTNAME}" == "" ]
		do
			msgWarn "DEBUG: ${STRING_NO_HOSTNAME}"
			HOSTNAME=`zenity --entry --title="${STRING_SPECIFY_HOSTNAME}" --text="${STRING_INPUT_HOSTNAME}" --entry-text "${STRING_HOSTNAME_DEFAULT}"`
		done
		msgWarn "DEBUG: HOSTNAME: ${HOSTNAME}"
		
		# Select a mac address
		while [ "${MAC_ADDRESS}" == "" ]
		do
			msgWarn "DEBUG: ${STRING_NO_MAC_ADDR}"
			MAC_ADDRESS=`zenity --entry --title="${STRING_SPECIFY_MAC_ADDR}" --text="${STRING_INPUT_MAC_ADDR}" --entry-text "${STRING_MAC_ADDR_DEFAULT}"`
		done
		msgWarn "DEBUG: MAC_ADDRESS: ${MAC_ADDRESS}"
		MACADDRESS=`echo $MAC_ADDRESS|cut -c 1-2,4-5,7-8,10-11,13-14,16-17,19-20`
		msgWarn "DEBUG: MACADDRESS: ${MACADDRESS}"
		
		# Select working directory
		while [ "${WORK_DIR}" == "" ]
		do
			msgWarn "DEBUG: ${STRING_NO_WORK_DIR}"
			WORK_DIR=`zenity --entry --title="${STRING_SPECIFY_WORK_DIR}" --text="${STRING_INPUT_WORK_DIR}" --entry-text "${STRING_WORK_DIR_DEFAULT}"`
		done
		msgWarn "DEBUG: WORK_DIR: ${WORK_DIR}"
		
		if [ ! -d "${WORK_DIR}" ]; then
			msgInfo "Creating ${WORK_DIR}..."
			mkdir -p "${WORK_DIR}"
		else
			msgWarn "DEBUG: ${WORK_DIR} already exists"
		fi
		
		# Select ARM compiler version
		if [ "${ARM_COMPILER_VERSION}" != "" ]; then
			if [ "`apt-cache search gcc-*.*-arm-linux-gnueabihf | awk '{print $1}' | grep -v 'base' | grep -v 'multilib' | grep ${ARM_COMPILER_VERSION} | wc -l`" != "1" ] ; then
				msgWarn "DEBUG: ARM_COMPILER_VERSION: ${ARM_COMPILER_VERSION} erroneous version defined"
				ARM_COMPILER_VERSION=""
			fi
		fi
		
		while [ "${ARM_COMPILER_VERSION}" == "" ]
		do
			msgWarn "DEBUG: ${STRING_NO_ARM_COMPILER_VERSION}"
			ARM_COMPILER_VERSION=`apt-cache search gcc-*.*-arm-linux-gnueabihf | awk '{print $1}' | grep -v 'base' | grep -v 'multilib' | zenity --list --title="${STRING_SPECIFY_ARM_COMPILER_VERSION}" --text="${STRING_INPUT_ARM_COMPILER_VERSION}" --column="${STRING_ARM_COMPILER_VERSION_COLUMN}"`
		done
		msgWarn "DEBUG: ARM_COMPILER_VERSION: ${ARM_COMPILER_VERSION}"
		
		CROSS_COMPILER_SYSTEM="arm-linux-gnueabihf-"
		COMPILER_VERSION="${CROSS_COMPILER_SYSTEM}gcc-`echo $ARM_COMPILER_VERSION | sed 's/-/ /g' | awk '{print $2}'`"
		msgWarn "DEBUG: COMPILER_VERSION: ${COMPILER_VERSION}"
		msgWarn "DEBUG: CROSS_COMPILER_SYSTEM: ${CROSS_COMPILER_SYSTEM}"
		
		if [ "`dpkg -al ${COMPILER_VERSION} | wc -w`" != "0" ] ; then
			msgInfo "${ARM_COMPILER_VERSION} already installed"
		else
			$SUDOTOOL "apt-get install ${ARM_COMPILER_VERSION}"
		fi
		
		$SUDOTOOL "rm /usr/bin/arm-linux-gnueabi-gcc"
		$SUDOTOOL "rm /usr/bin/arm-linux-gnueabihf-gcc"
		$SUDOTOOL "ln -s /usr/bin/$COMPILER_VERSION /usr/bin/arm-linux-gnueabi-gcc"
		$SUDOTOOL "ln -s /usr/bin/$COMPILER_VERSION /usr/bin/arm-linux-gnueabihf-gcc"
		
		# Select Image Language
		while [ "${IMG_LANG}" == "" ]
		do
			msgWarn "DEBUG: ${STRING_NO_IMG_LANG}"
			IMG_LANG=`zenity --list \
						--title="${STRING_SPECIFY_IMG_LANG}" \
						--column="${STRING_IMG_LANG_COLUMN_1}" --column="${STRING_IMG_LANG_COLUMN_2}" \
							"${STRING_IMG_LANG_CODE_1_1}" "${STRING_IMG_LANG_CODE_1_2}" \
							"${STRING_IMG_LANG_CODE_2_1}" "${STRING_IMG_LANG_CODE_2_2}"`
		done
		msgWarn "DEBUG: IMG_LANG: ${IMG_LANG}"

		# Select Image Root Password
		while [ "${ROOT_PASS}" == "" ]
		do
			msgWarn "DEBUG: ${STRING_NO_ROOT_PASS}"
			ROOT_PASS=`zenity --entry --title="${STRING_SPECIFY_ROOT_PASS}" --text="${STRING_INPUT_ROOT_PASS}" --entry-text "${STRING_ROOT_PASS_DEFAULT}"`
		done
		msgWarn "DEBUG: ROOT_PASS: ${ROOT_PASS}"

		# Wireless Network Name
		while [ "${WIFI_NETWORK_NAME}" == "" ]
		do
			msgWarn "DEBUG: ${STRING_NO_WIFI_NETWORK_NAME}"
			WIFI_NETWORK_NAME=`zenity --entry --title="${STRING_SPECIFY_WIFI_NETWORK_NAME}" --text="${STRING_INPUT_WIFI_NETWORK_NAME}"`
		done
		msgWarn "DEBUG: WIFI_NETWORK_NAME: ${WIFI_NETWORK_NAME}"

		# Wireless Password
		while [ "${WIFI_NETWORK_PASS}" == "" ]
		do
			msgWarn "DEBUG: ${STRING_NO_WIFI_NETWORK_PASS}"
			WIFI_NETWORK_PASS=`zenity --entry --title="${STRING_SPECIFY_WIFI_NETWORK_PASS}" --text="${STRING_INPUT_WIFI_NETWORK_PASS}"`
		done
		msgWarn "DEBUG: WIFI_NETWORK_PASS: ${WIFI_NETWORK_PASS}"
		
		# Select the SD size
		while [ "${SD_SPACE}" == "" ]
		do
			msgWarn "DEBUG: ${STRING_NO_SD_SPACE}"
			SD_SPACE=`zenity --list \
						--title="Indica el tamaño de la SD" \
						--column="KB" --column="Espacio" \
						"4096" "4GB" \
						"8192" "8GB" \
						"16384" "16GB" \
						"32768" "32GB" \
						65536"" "64GB"`
		done
		msgWarn "DEBUG: SD_SPACE: ${SD_SPACE}MB ($[${SD_SPACE}/1024]GB)"
		msgWarn "DEBUG: SD_SPACE (${WORK_DIR}/${HOSTNAME}-ubootfs.img): 17MB"
		msgWarn "DEBUG: SD_SPACE (${WORK_DIR}/${HOSTNAME}-rootfs.img): $[(${SD_SPACE}-17)]MB"
		
		if [ `mount | grep UBOOT_FS | wc -l` -ge 1 ] ; then
			msgWarn "DEBUG: UBOOT_FS already mounted, umounting it..."
			$SUDOTOOL "umount ${WORK_DIR}/mountpoints/UBOOT_FS"
		else
			msgWarn "DEBUG: UBOOT_FS not mounted"
		fi
		
		if [ ! -e "${WORK_DIR}/${HOSTNAME}-ubootfs.img" ]; then
			msgInfo "Creating ${WORK_DIR}/${HOSTNAME}-ubootfs.img file of 17MB..."
			$SUDOTOOL "dd if=/dev/zero of=${WORK_DIR}/${HOSTNAME}-ubootfs.img bs=1M count=17"
			msgInfo "Formatting ${WORK_DIR}/${HOSTNAME}-ubootfs.img ..."
			$SUDOTOOL "mkfs.vfat -F 16 -n BOOT_FS ${WORK_DIR}/${HOSTNAME}-ubootfs.img"
		else
			msgWarn "File ${WORK_DIR}/${HOSTNAME}-ubootfs.img already exists"
			zenity --question \
				--text="File ${WORK_DIR}/${HOSTNAME}-ubootfs.img already exists.\n\nDo you want re-create it anyway?"

			FORMAT_UBOOTFS_FILE=$?
			
			case $FORMAT_UBOOTFS_FILE in
				0)
					msgInfo "Creating ${WORK_DIR}/${HOSTNAME}-ubootfs.img file of 17MB..."
					$SUDOTOOL "dd if=/dev/zero of=${WORK_DIR}/${HOSTNAME}-ubootfs.img bs=1M count=17"
					msgInfo "Formatting ${WORK_DIR}/${HOSTNAME}-ubootfs.img ..."
					$SUDOTOOL "mkfs.vfat -F 16 -n BOOT_FS ${WORK_DIR}/${HOSTNAME}-ubootfs.img"
					;;
				1)
					msgWarn "Not re-creating ${WORK_DIR}/${HOSTNAME}-ubootfs.img file."
					;;
				-1)
					msgErr "ERROR: Unexpected error. Exiting..."
					exit 1
				;;
			esac
		fi
		
		if [ `mount | grep ROOT_FS | wc -l` -ge 1 ] ; then			
			msgWarn "DEBUG: ROOT_FS already mounted, umounting it..."
			$SUDOTOOL "umount ${WORK_DIR}/mountpoints/ROOT_FS"
		else
			msgWarn "DEBUG: ROOT_FS not mounted"
		fi
		
		if [ ! -e "${WORK_DIR}/${HOSTNAME}-rootfs.img" ]; then
			msgInfo "Creating ${WORK_DIR}/${HOSTNAME}-rootfs.img file of $[(${SD_SPACE}-17)]MB..."
			$SUDOTOOL "dd if=/dev/zero of=${WORK_DIR}/${HOSTNAME}-rootfs.img bs=1M count=$[${SD_SPACE}-17]"
			msgInfo "Formatting ${WORK_DIR}/${HOSTNAME}-rootfs.img ..."
			$SUDOTOOL "mkfs.ext4 -L ROOT_FS -F ${WORK_DIR}/${HOSTNAME}-rootfs.img"
		else
			msgWarn "File ${WORK_DIR}/${HOSTNAME}-rootfs.img already exists"
			zenity --question \
				--text="File ${WORK_DIR}/${HOSTNAME}-rootfs.img already exists.\n\nDo you want re-create it anyway?"

			FORMAT_UBOOTFS_FILE=$?
			
			case $FORMAT_UBOOTFS_FILE in
				0)
					msgInfo "Creating ${WORK_DIR}/${HOSTNAME}-rootfs.img file of $[(${SD_SPACE}-17)]MB..."
					$SUDOTOOL "dd if=/dev/zero of=${WORK_DIR}/${HOSTNAME}-rootfs.img bs=1M count=$[${SD_SPACE}-17]"
					msgInfo "Formatting ${WORK_DIR}/${HOSTNAME}-rootfs.img ..."
					$SUDOTOOL "mkfs.ext4 -L ROOT_FS -F ${WORK_DIR}/${HOSTNAME}-rootfs.img"
					;;
				1)
					msgWarn "Not re-creating ${WORK_DIR}/${HOSTNAME}-rootfs.img file."
					;;
				-1)
					msgErr "ERROR: Unexpected error. Exiting..."
					exit 1
				;;
			esac
		fi
		
		if [ ! -d "${WORK_DIR}/mountpoints" ]; then
			msgInfo "Creating ${WORK_DIR}/mountpoints ..."
			mkdir -p "${WORK_DIR}/mountpoints"
			mkdir -p "${WORK_DIR}/mountpoints/UBOOT_FS"
			mkdir -p "${WORK_DIR}/mountpoints/ROOT_FS"
			mkdir -p "${WORK_DIR}/mountpoints/SD_UBOOT_FS"
			mkdir -p "${WORK_DIR}/mountpoints/SD_ROOT_FS"
		else
			msgWarn "DEBUG: ${WORK_DIR}/mountpoints already exists"
			if [ ! -d "${WORK_DIR}/mountpoints/UBOOT_FS" ]; then
				msgInfo "Re-creating ${WORK_DIR}/mountpoints/UBOOT_FS deleted..."
				mkdir -p "${WORK_DIR}/mountpoints/UBOOT_FS"
			fi
			if [ ! -d "${WORK_DIR}/mountpoints/ROOT_FS" ]; then
				msgInfo "Re-creating ${WORK_DIR}/mountpoints/ROOT_FS deleted..."
				mkdir -p "${WORK_DIR}/mountpoints/ROOT_FS"
			fi
			if [ ! -d "${WORK_DIR}/mountpoints/SD_UBOOT_FS" ]; then
				msgInfo "Re-creating ${WORK_DIR}/mountpoints/SD_UBOOT_FS deleted..."
				mkdir -p "${WORK_DIR}/mountpoints/SD_UBOOT_FS"
			fi
			if [ ! -d "${WORK_DIR}/mountpoints/SD_ROOT_FS" ]; then
				msgInfo "Re-creating ${WORK_DIR}/mountpoints/SD_ROOT_FS deleted..."
				mkdir -p "${WORK_DIR}/mountpoints/SD_ROOT_FS"
			fi
		fi
		
		msgInfo "Mounting UBOOT_FS to ${WORK_DIR}/mountpoints/UBOOT_FS"
		$SUDOTOOL "mount -o loop ${WORK_DIR}/${HOSTNAME}-ubootfs.img ${WORK_DIR}/mountpoints/UBOOT_FS"
		
		msgInfo "Mounting ROOT_FS to ${WORK_DIR}/mountpoints/ROOT_FS"
		$SUDOTOOL "mount -o loop ${WORK_DIR}/${HOSTNAME}-rootfs.img ${WORK_DIR}/mountpoints/ROOT_FS"
		
		msgInfo "Creating debootstrap on ROOT_FS..."
		$SUDOTOOL "debootstrap --verbose --arch armhf --variant=minbase --foreign wheezy ${WORK_DIR}/mountpoints/ROOT_FS http://ftp.debian.org/debian"
		
		msgInfo "Adding support for chrooting ARM architecture"
		$SUDOTOOL "cp `which qemu-arm-static` ${WORK_DIR}/mountpoints/ROOT_FS/usr/bin/"
		$SUDOTOOL "mkdir -p ${WORK_DIR}/mountpoints/ROOT_FS/dev/pts"

		if [ `mount | grep ROOT_FS/dev/pts | wc -l` -ge 1 ] ; then
			msgWarn "DEBUG: ROOT_FS/dev/pts already mounted"
		else
			msgWarn "DEBUG: ROOT_FS/dev/pts not mounted"
			msgInfo "Mounting /dev/pts to chroot environtment"
			$SUDOTOOL "mount -t devpts devpts ${WORK_DIR}/mountpoints/ROOT_FS/dev/pts"
		fi

		if [ `mount | grep ROOT_FS/proc | wc -l` -ge 1 ] ; then
			msgWarn "DEBUG: ROOT_FS/proc already mounted"
		else
			msgWarn "DEBUG: ROOT_FS/proc not mounted"
			msgInfo "Mounting /proc to chroot environtment"
			$SUDOTOOL "mount -t proc proc ${WORK_DIR}/mountpoints/ROOT_FS/proc"
		fi

		msgInfo "Installing on chroot environtment"
		sudo chroot ${WORK_DIR}/mountpoints/ROOT_FS/ /bin/bash <<CHROOTEOF
# You should see "I have no name!@hostname:/#"
/debootstrap/debootstrap --second-stage
wait

echo "###################################################################################"
echo "# 'I: Base system installed successfully.' means that initial debootstrap ends ;) #"
echo "###################################################################################"

echo "##################################"
echo "# Adding sources to sources.list #"
echo "##################################"
cd /root
cat <<END > /etc/apt/sources.list
deb http://ftp.debian.org/debian/ wheezy main contrib non-free
deb http://security.debian.org/ wheezy/updates main contrib non-free
END
echo "######################################"
echo "# Showing /etc/apt/sources.list file #"
echo "######################################"
cat /etc/apt/sources.list
echo "######################################"
apt-get update

export LANG=C
apt-get -y install apt-utils
wait
apt-get -y install dialog
wait
apt-get -y install locales
wait

cat <<END > /etc/apt/apt.conf.d/71hackberry
APT::Install-Recommends "0";
APT::Install-Suggests "0";
END

echo "####################"
echo "# Setting language #"
echo "####################"
sed -i 's/# $IMG_LANG UTF-8/$IMG_LANG UTF-8/g' //etc/locale.gen
export LANG=$IMG_LANG
locale-gen
#dpkg-reconfigure locales

echo "###############################"
echo "# Installing minimal packages #"
echo "###############################"
apt-get -y install isc-dhcp-common udev netbase ifupdown iproute openssh-server iputils-ping \
wget net-tools ntpdate ntp vim nano less tzdata console-tools mount dhcpcd5 module-init-tools \
uboot-mkimage uboot-envtools module-init-tools wpasupplicant dbus perl-modules
wait

echo "###########################################"
echo "# Installing Linux Standard Base packages #"
echo "###########################################"
apt-get -y install lsb-base lsb-core lsb-cxx lsb-languages lsb-release lsb-security lsb-rpm
wait



#echo "###########################################"
#echo "##  Here we can add more extra packages  ##"
#echo "###########################################"

#echo "###########################################"
#echo "## LXDE desktop by default               ##"
#echo "###########################################"
#apt-get -y lxde lxde-core lxde-common lxde-icon-theme lxappearance lxdm lxscreenshot lxfind lxterminal lxsession lx-session-edit lxrandr lxmusic lxmenu-data lxinput
#wait

#echo "###########################################"
#echo "## TCOS client support (need help)       ##"
#echo "###########################################"
#apt-get -y ...
#wait

#echo "###########################################"
#echo "## LTSP client support (need help)       ##"
#echo "###########################################"
#apt-get -y ...
#wait



echo "##############################"
echo "# Setting network interfaces #"
echo "##############################"
### Set up network
cat <<END > /etc/network/interfaces
auto lo eth0 wlan0
iface lo inet loopback
iface eth0 inet dhcp
hwaddress ether $MACADDRESS
iface wlan0 inet dhcp
wpa-essid $WIFI_NETWORK_NAME
wpa-psk $WIFI_NETWORK_PASS
END
echo "########################################"
echo "# Showing /etc/network/interfaces file #"
echo "########################################"
cat /etc/network/interfaces
echo "########################################"

echo "####################"
echo "# Setting hostname #"
echo "####################"
echo $HOSTNAME > //etc/hostname

echo "##################################"
echo "# Setting file system partitions #"
echo "##################################"
cat <<END > //etc/fstab
# /etc/fstab: static file system information.
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/root      /               ext4    noatime,errors=remount-ro 0 1
tmpfs          /tmp            tmpfs   defaults          0       0
END

echo "#############################"
echo "# Activating remote console #"
echo "#############################"
echo 'T0:2345:respawn:/sbin/getty -L ttyS0 115200 linux' >> //etc/inittab
#sed -i 's/^\([1-6]:.* tty[1-6]\)/#\1/' //etc/inittab

echo "######################################################"
echo "# Enabling modules for disp, lcd and hdmi by default #"
echo "######################################################"
cat << END >> /etc/modules
8192cu
lcd
hdmi
ump
disp
#mali
#mali_drm
END

echo "##########################"
echo "# Changing root password #"
echo "##########################"
echo root:$ROOT_PASS|chpasswd

wait
CHROOTEOF

		msgInfo "Umounting /proc from chroot environtment"
		$SUDOTOOL "umount ${WORK_DIR}/mountpoints/ROOT_FS/proc"
		
		msgInfo "Umounting /dev/pts from chroot environtment"
		$SUDOTOOL "umount ${WORK_DIR}/mountpoints/ROOT_FS/dev/pts"
		
		msgInfo "Umounting /dev/pts from chroot environtment"
		
		if [ ! -d "${WORK_DIR}/source" ]; then
			msgInfo "Creating ${WORK_DIR}/source..."
			mkdir -p "${WORK_DIR}/source"
		else
			msgWarn "DEBUG: ${WORK_DIR}/source already exists"
		fi
		
		if [ ! -d "${WORK_DIR}/compiled" ]; then
			msgInfo "Creating ${WORK_DIR}/compiled..."
			mkdir -p "${WORK_DIR}/compiled"
		else
			msgWarn "DEBUG: ${WORK_DIR}/compiled already exists"
		fi
		
		cd ${WORK_DIR}/source
		
		if [ ! -d "${WORK_DIR}/source/u-boot-sunxi" ]; then
			msgInfo "Downloading source for u-boot-sunxi"
			git clone git://github.com/linux-sunxi/u-boot-sunxi.git
			cd u-boot-sunxi
		else
			msgInfo "Checking updates for source u-boot-sunxi"
			cd u-boot-sunxi
			git pull
		fi
		
		make hackberry CROSS_COMPILE=${CROSS_COMPILER_SYSTEM} || { msgErr "Compilation of u-boot-sunxi failed" ; exit 1; }
		cd ..
		
		if [ -e "${WORK_DIR}/source/u-boot-sunxi/spl/u-boot-spl.bin" ]; then
			msgInfo "Copying compiled u-boot-spl.bin to ${WORK_DIR}/compiled"
			cp ${WORK_DIR}/source/u-boot-sunxi/spl/u-boot-spl.bin ${WORK_DIR}/compiled/
		else
			msgErr "File u-boot-spl.bin not exists"
			exit 1
		fi
		
		if [ -e "${WORK_DIR}/source/u-boot-sunxi/spl/sunxi-spl.bin" ]; then
			msgInfo "Copying compiled sunxi-spl.bin to ${WORK_DIR}/compiled"
			cp ${WORK_DIR}/source/u-boot-sunxi/spl/sunxi-spl.bin ${WORK_DIR}/compiled/
		else
			msgErr "File sunxi-spl.bin not exists"
			exit 1
		fi
		
		if [ ! -d "${WORK_DIR}/source/linux-sunxi" ]; then
			msgInfo "Downloading source for linux-sunxi"
			git clone git://github.com/linux-sunxi/linux-sunxi.git
			cd linux-sunxi
		else
			msgInfo "Checking updates for source linux-sunxi"
			cd linux-sunxi
			git pull
		fi
		
		make mrproper
		make ARCH=arm CROSS_COMPILE=${CROSS_COMPILER_SYSTEM} sun4i_defconfig || { msgErr "Compilation of linux-sunxi failed" ; exit 1; }
		make ARCH=arm CROSS_COMPILE=${CROSS_COMPILER_SYSTEM} -j16 uImage modules || { msgErr "Compilation of linux-sunxi modules failed" ; exit 1; }
		make ARCH=arm CROSS_COMPILE=${CROSS_COMPILER_SYSTEM} INSTALL_MOD_PATH=output modules_install || { msgErr "Generation of output modules failed" ; exit 1; }
		cd ..
		
		if [ -e "${WORK_DIR}/source/linux-sunxi/arch/arm/boot/uImage" ]; then
			msgInfo "Copying compiled uImage to ${WORK_DIR}/compiled"
			cp ${WORK_DIR}/source/linux-sunxi/arch/arm/boot/uImage ${WORK_DIR}/compiled/
			msgInfo "Copying compiled uImage to ${WORK_DIR}/mountpoints/UBOOT_FS/"
			$SUDOTOOL "cp ${WORK_DIR}/source/linux-sunxi/arch/arm/boot/uImage ${WORK_DIR}/mountpoints/UBOOT_FS/"
		else
			msgErr "File uImage not exists"
			exit 1
		fi
		
		if [ -d "${WORK_DIR}/source/linux-sunxi/output" ]; then
			msgInfo "Copying folder output to ${WORK_DIR}/compiled"
			cp -R ${WORK_DIR}/source/linux-sunxi/output ${WORK_DIR}/compiled/
			msgInfo "Copying compiled libs to ${WORK_DIR}/mountpoints/ROOT_FS/"
			$SUDOTOOL "cp -R ${WORK_DIR}/source/linux-sunxi/output/* ${WORK_DIR}/mountpoints/ROOT_FS/"
		else
			msgErr "Folder output not exists"
			exit 1
		fi
		
		if [ ! -d "${WORK_DIR}/source/sunxi-tools" ]; then
			msgInfo "Downloading source for sunxi-tools"
			git clone https://github.com/linux-sunxi/sunxi-tools
			cd sunxi-tools
		else
			msgInfo "Checking updates for source sunxi-tools"
			cd sunxi-tools
			git pull
		fi
		
		make clean
		make || { msgErr "Compilation of sunxi-tools failed" ; exit 1; }
		cd ..
		
		msgInfo "Creating boot.cmd"
		cat <<END > ${WORK_DIR}/compiled/boot.cmd
setenv bootargs console=tyS0 root=/dev/mmcblk0p2 rootwait panic=10 ${extra}
fatload mmc 0 0x43000000 script.bin
fatload mmc 0 0x48000000 uImage
bootm 0x48000000
END
		mkimage -C none -A arm -T script -d ${WORK_DIR}/compiled/boot.cmd ${WORK_DIR}/compiled/boot.scr || { msgErr "Compilation of boot.scr failed" ; exit 1; }
		msgInfo "Copying compiled boot.scr to ${WORK_DIR}/mountpoints/UBOOT_FS/"
		$SUDOTOOL "cp ${WORK_DIR}/compiled/boot.scr ${WORK_DIR}/mountpoints/UBOOT_FS/"
		
		msgInfo "Downloading script.bin for HackBerry"
		if [ ! -f "${WORK_DIR}/source/script.bin" ]; then
			msgInfo "Downloading script.bin for HackBerry"
			wget -c https://github.com/linux-sunxi/sunxi-bin-archive/raw/master/hackberry/stock-nanda-1gb/script.bin || { msgErr "Download failed" ; exit 1; }
		else
			msgWarn "script.bin already downloaded"
		fi
		msgInfo "bin2fex script.bin"
		sunxi-tools/bin2fex script.bin script.fex
		msgInfo "Editing MAC-Address on script.fex"
		sed s/000000000000/$MACADDRESS/ script.fex >scriptmac.fex
		msgInfo "fex2bin script.fex"
		sunxi-tools/fex2bin scriptmac.fex scriptmac.bin
		msgInfo "Replacing script.bin"
		cp scriptmac.bin ${WORK_DIR}/compiled/script.bin
		msgInfo "Copying compiled script.bin to ${WORK_DIR}/mountpoints/UBOOT_FS/"
		$SUDOTOOL "cp ${WORK_DIR}/compiled/script.bin ${WORK_DIR}/mountpoints/UBOOT_FS/"
		
		msgInfo "Formatting partition table on device ${DEVICE}"
		$SUDOTOOL "dd if=/dev/zero of=${DEVICE} bs=512 count=2047"

#		(echo n;echo;echo;echo;echo "+17M";echo n;echo ;echo;echo;echo;echo w) | $SUDOTOOL "fdisk ${DEVICE}"
		msgInfo "Creating partitions on device ${DEVICE}..."
		cat <<EOF | sudo fdisk ${DEVICE}
n
p
1

+17M
n
p
2


w
EOF
		
		msgInfo "Formatting ${UBOOT_PART}..."
		sudo mkfs.vfat -F 16 -n BOOT_FS ${UBOOT_PART}
		msgInfo "Formatting ${ROOTFS_PART}..."
		sudo mkfs.ext4 -L ROOT_FS ${ROOTFS_PART}
		
		msgInfo "Reloading device ${DEVICE}..."
		partprobe
		
		msgInfo "Mounting ${UBOOTFS_PART} to ${WORK_DIR}/mountpoints/SD_UBOOT_FS..."
		$SUDOTOOL "mount -t vfat ${UBOOT_PART} ${WORK_DIR}/mountpoints/SD_UBOOT_FS"
		msgInfo "Copying files to SD_UBOOT_FS ..."
		sudo cp -a ${WORK_DIR}/mountpoints/UBOOT_FS/* ${WORK_DIR}/mountpoints/SD_UBOOT_FS/
		sync
		msgInfo "Umounting all UBOOT_FS mountpoints..."
		$SUDOTOOL "umount ${WORK_DIR}/mountpoints/UBOOT_FS"
		$SUDOTOOL "umount ${WORK_DIR}/mountpoints/SD_UBOOT_FS"
		
		msgInfo "Mounting ${ROOTFS_PART} to ${WORK_DIR}/mountpoints/SD_ROOT_FS..."
		$SUDOTOOL "mount -t ext4 ${ROOTFS_PART} ${WORK_DIR}/mountpoints/SD_ROOT_FS"
		msgInfo "Copying files to ROOT_FS ..."
		sudo cp -a ${WORK_DIR}/mountpoints/ROOT_FS/* ${WORK_DIR}/mountpoints/SD_ROOT_FS/
		sync
		msgInfo "Umounting all ROOT_FS mountpoints..."
		$SUDOTOOL "umount ${WORK_DIR}/mountpoints/ROOT_FS"
		$SUDOTOOL "umount ${WORK_DIR}/mountpoints/SD_ROOT_FS"
		
		msgInfo "Flashing sunxi-spl.bin to ${DEVICE}"
		$SUDOTOOL "dd if=${WORK_DIR}/source/u-boot-sunxi/spl/sunxi-spl.bin of=${DEVICE} bs=1024 seek=8"
		msgInfo "Flashing u-boot-spl.bin to ${DEVICE}"
		$SUDOTOOL "dd if=${WORK_DIR}/source/u-boot-sunxi/spl/u-boot-spl.bin of=${DEVICE} bs=1024 seek=32"
		
		msgInfo "Checking filesystem on SD_UBOOT_FS"
		sudo fsck.vfat -a ${UBOOT_PART}
		
		msgInfo "Checking filesystem on SD_ROOT_FS"
		sudo fsck.ext4 -p ${ROOTFS_PART}

		
		msgInfo "############################################################"
		msgInfo "## Created Debian armhf image for HackBerry AllWinner A10 ##"
		msgInfo "## Put the SD in the HackBerry and power on to try it ;)  ##"
		msgInfo "############################################################"

		;;
    1)
        msgErr "DEBUG: ${STRING_LICENSE_REJECTED}"
        exit 1
		;;
    -1)
        msgErr "DEBUG: ${STRING_LICENSE_ERROR}"
		;;
esac
