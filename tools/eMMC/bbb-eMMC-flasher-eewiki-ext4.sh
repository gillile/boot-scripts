#!/bin/bash -e
#
# Copyright (c) 2013-2014 Robert Nelson <robertcnelson@gmail.com>
# Portions copyright (c) 2014 Charles Steinkuehler <charles@steinkuehler.net>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

#This script assumes, these packages are installed, as network may not be setup
#dosfstools initramfs-tools rsync u-boot-tools

if ! id | grep -q root; then
	echo "must be run as root"
	exit
fi

source="/dev/mmcblk0"
destination="/dev/mmcblk1"

flush_cache () {
	sync
	blockdev --flushbufs ${destination}
}

inf_loop () {
	while read MAGIC ; do
		case $MAGIC in
		beagleboard.org)
			echo "Your foo is strong!"
			bash -i
			;;
		*)	echo "Your foo is weak."
			;;
		esac
	done
}

write_failure () {
	echo "writing to [${destination}] failed..."

	[ -e /proc/$CYLON_PID ]  && kill $CYLON_PID > /dev/null 2>&1

	if [ -e /sys/class/leds/beaglebone\:green\:usr0/trigger ] ; then
		echo heartbeat > /sys/class/leds/beaglebone\:green\:usr0/trigger
		echo heartbeat > /sys/class/leds/beaglebone\:green\:usr1/trigger
		echo heartbeat > /sys/class/leds/beaglebone\:green\:usr2/trigger
		echo heartbeat > /sys/class/leds/beaglebone\:green\:usr3/trigger
	fi
	echo "-----------------------------"
	flush_cache
	umount ${destination}p1 > /dev/null 2>&1 || true
	umount ${destination}p2 > /dev/null 2>&1 || true
	inf_loop
}

check_eeprom () {

	eeprom="/sys/bus/i2c/devices/0-0050/eeprom"

	#Flash BeagleBone Black's eeprom:
	eeprom_location=$(ls /sys/devices/ocp.*/44e0b000.i2c/i2c-0/0-0050/eeprom 2> /dev/null)
	eeprom_header=$(hexdump -e '8/1 "%c"' ${eeprom} -s 5 -n 3)
	if [ "x${eeprom_header}" = "x335" ] ; then
		echo "Valid EEPROM header found"
	else
		echo "Invalid EEPROM header detected"
		if [ -f /opt/scripts/device/bone/bbb-eeprom.dump ] ; then
			if [ ! "x${eeprom_location}" = "x" ] ; then
				echo "Adding header to EEPROM"
				dd if=/opt/scripts/device/bone/bbb-eeprom.dump of=${eeprom_location}
				sync

				#We have to reboot, as the kernel only loads the eMMC cape
				# with a valid header
				reboot -f

				#We shouldnt hit this...
				exit
			fi
		fi
	fi
}

check_running_system () {
	echo "-----------------------------"
	echo "debug copying: [${source}] -> [${destination}]"
	lsblk
	echo "-----------------------------"

	if [ ! -b "${destination}" ] ; then
		echo "Error: [${destination}] does not exist"
		write_failure
	fi

	if [ ! -f /boot/config-$(uname -r) ] ; then
		zcat /proc/config.gz > /boot/config-$(uname -r)
	fi

	if [ -f /boot/initrd.img-$(uname -r) ] ; then
		update-initramfs -u -k $(uname -r)
	else
		update-initramfs -c -k $(uname -r)
	fi
	flush_cache
}

cylon_leds () {
	if [ -e /sys/class/leds/beaglebone\:green\:usr0/trigger ] ; then
		BASE=/sys/class/leds/beaglebone\:green\:usr
		echo none > ${BASE}0/trigger
		echo none > ${BASE}1/trigger
		echo none > ${BASE}2/trigger
		echo none > ${BASE}3/trigger

		STATE=1
		while : ; do
			case $STATE in
			1)	echo 255 > ${BASE}0/brightness
				echo 0   > ${BASE}1/brightness
				STATE=2
				;;
			2)	echo 255 > ${BASE}1/brightness
				echo 0   > ${BASE}0/brightness
				STATE=3
				;;
			3)	echo 255 > ${BASE}2/brightness
				echo 0   > ${BASE}1/brightness
				STATE=4
				;;
			4)	echo 255 > ${BASE}3/brightness
				echo 0   > ${BASE}2/brightness
				STATE=5
				;;
			5)	echo 255 > ${BASE}2/brightness
				echo 0   > ${BASE}3/brightness
				STATE=6
				;;
			6)	echo 255 > ${BASE}1/brightness
				echo 0   > ${BASE}2/brightness
				STATE=1
				;;
			*)	echo 255 > ${BASE}0/brightness
				echo 0   > ${BASE}1/brightness
				STATE=2
				;;
			esac
			sleep 0.1
		done
	fi
}

dd_bootloader () {
	echo ""
	echo "Using dd to place bootloader on [${destination}]"
	echo "-----------------------------"

	unset dd_spl_uboot
	if [ ! "x${dd_spl_uboot_count}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}count=${dd_spl_uboot_count} "
	fi

	if [ ! "x${dd_spl_uboot_seek}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}seek=${dd_spl_uboot_seek} "
	fi

	if [ ! "x${dd_spl_uboot_conf}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}conv=${dd_spl_uboot_conf} "
	fi

	if [ ! "x${dd_spl_uboot_bs}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}bs=${dd_spl_uboot_bs}"
	fi

	unset dd_uboot
	if [ ! "x${dd_uboot_count}" = "x" ] ; then
		dd_uboot="${dd_uboot}count=${dd_uboot_count} "
	fi

	if [ ! "x${dd_uboot_seek}" = "x" ] ; then
		dd_uboot="${dd_uboot}seek=${dd_uboot_seek} "
	fi

	if [ ! "x${dd_uboot_conf}" = "x" ] ; then
		dd_uboot="${dd_uboot}conv=${dd_uboot_conf} "
	fi

	if [ ! "x${dd_uboot_bs}" = "x" ] ; then
		dd_uboot="${dd_uboot}bs=${dd_uboot_bs}"
	fi

	echo "dd if=${dd_spl_uboot_backup} of=${destination} ${dd_spl_uboot}"
	echo "-----------------------------"
	dd if=${dd_spl_uboot_backup} of=${destination} ${dd_spl_uboot}
	echo "-----------------------------"
	echo "dd if=${dd_uboot_backup} of=${destination} ${dd_uboot}"
	echo "-----------------------------"
	dd if=${dd_uboot_backup} of=${destination} ${dd_uboot}
}

format_boot () {
	echo "mkfs.vfat -F 16 ${destination}p1 -n BEAGLEBONE"
	echo "-----------------------------"
	mkfs.vfat -F 16 ${destination}p1 -n BEAGLEBONE
	echo "-----------------------------"
	flush_cache
}

format_root () {
	echo "mkfs.ext4 ${destination}p2 -L rootfs"
	echo "-----------------------------"
	mkfs.ext4 ${destination}p2 -L rootfs
	echo "-----------------------------"
	flush_cache
}

format_single_root () {
	echo "mkfs.ext4 ${destination}p1 -L rootfs"
	echo "-----------------------------"
	mkfs.ext4 ${destination}p1 -L rootfs
	echo "-----------------------------"
	flush_cache
}

copy_boot () {
	echo "Copying: ${source}p1 -> ${destination}p1"
	mkdir -p /tmp/boot/ || true
	mount ${destination}p1 /tmp/boot/ -o sync

	if [ -f /boot/uboot/MLO ] ; then
		#Make sure the BootLoader gets copied first:
		cp -v /boot/uboot/MLO /tmp/boot/MLO || write_failure
		flush_cache

		cp -v /boot/uboot/u-boot.img /tmp/boot/u-boot.img || write_failure
		flush_cache
	fi

	echo "rsync: /boot/uboot/ -> /tmp/boot/"
	rsync -aAX /boot/uboot/ /tmp/boot/ --exclude={MLO,u-boot.img,uEnv.txt} || write_failure
	flush_cache

	flush_cache
	umount /tmp/boot/ || umount -l /tmp/boot/ || write_failure
	flush_cache
	umount /boot/uboot/ || umount -l /boot/uboot/
}

copy_rootfs () {
	echo "Copying: ${source}p${media_rootfs} -> ${destination}p${media_rootfs}"
	mkdir -p /tmp/rootfs/ || true
	mount ${destination}p${media_rootfs} /tmp/rootfs/ -o async,noatime

	echo "rsync: / -> /tmp/rootfs/"
	rsync -aAX /* /tmp/rootfs/ --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found,/lib/modules/*} || write_failure
	flush_cache

	if [ -d /tmp/rootfs/etc/ssh/ ] ; then
		#ssh keys will now get regenerated on the next bootup
		touch /tmp/rootfs/etc/ssh/ssh.regenerate
		flush_cache
	fi

	mkdir -p /tmp/rootfs/lib/modules/$(uname -r)/ || true

	echo "Copying: Kernel modules"
	echo "rsync: /lib/modules/$(uname -r)/ -> /tmp/rootfs/lib/modules/$(uname -r)/"
	rsync -aAX /lib/modules/$(uname -r)/* /tmp/rootfs/lib/modules/$(uname -r)/ || write_failure
	flush_cache

	unset root_uuid
	root_uuid=$(/sbin/blkid -c /dev/null -s UUID -o value ${destination}p${media_rootfs})
	if [ "${root_uuid}" ] ; then
		sed -i -e 's:uuid=:#uuid=:g' /tmp/rootfs/boot/uEnv.txt
		echo "uuid=${root_uuid}" >> /tmp/rootfs/boot/uEnv.txt

		root_uuid="UUID=${root_uuid}"
	else
		#really a failure...
		root_uuid="${source}p${media_rootfs}"
	fi

	#echo "/boot/uEnv.txt: disabling flasher script"
	#script="cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3.sh"
	#sed -i -e 's:'$script':#'$script':g' /tmp/rootfs/boot/uEnv.txt
	#cat /tmp/rootfs/boot/uEnv.txt

	echo "Generating: /etc/fstab"
	echo "# /etc/fstab: static file system information." > /tmp/rootfs/etc/fstab
	echo "#" >> /tmp/rootfs/etc/fstab
	echo "${root_uuid}  /  ext4  noatime,errors=remount-ro  0  1" >> /tmp/rootfs/etc/fstab
	echo "debugfs  /sys/kernel/debug  debugfs  defaults  0  0" >> /tmp/rootfs/etc/fstab
	cat /tmp/rootfs/etc/fstab
	flush_cache
	umount /tmp/rootfs/ || umount -l /tmp/rootfs/ || write_failure

	[ -e /proc/$CYLON_PID ]  && kill $CYLON_PID

	echo "Syncing: ${destination}"
	#https://github.com/beagleboard/meta-beagleboard/blob/master/contrib/bone-flash-tool/emmc.sh#L158-L159
	# force writeback of eMMC buffers
	sync
	dd if=${destination} of=/dev/null count=100000

	echo ""
	echo "This script has now completed its task"
	echo "-----------------------------"

	if [ -f /boot/debug.txt ] ; then
		echo "debug: enabled"
		inf_loop
	else
		echo "Shutting Down"
		umount /tmp || umount -l /tmp
		if [ -e /sys/class/leds/beaglebone\:green\:usr0/trigger ] ; then
			echo default-on > /sys/class/leds/beaglebone\:green\:usr0/trigger
			echo default-on > /sys/class/leds/beaglebone\:green\:usr1/trigger
			echo default-on > /sys/class/leds/beaglebone\:green\:usr2/trigger
			echo default-on > /sys/class/leds/beaglebone\:green\:usr3/trigger
		fi
		mount

		echo ""
		echo "-----------------------------"
		echo ""
		echo "eMMC has been flashed, please remove power and microSD card"
		echo ""
		echo "-----------------------------"

		halt -f
	fi
}

partition_drive () {
	echo "Erasing: ${destination}"
	flush_cache
	dd if=/dev/zero of=${destination} bs=1M count=108
	sync
	dd if=${destination} of=/dev/null bs=1M count=108
	sync
	flush_cache

	if [ -f /boot/SOC.sh ] ; then
		. /boot/SOC.sh
	fi

	if [ "x${dd_spl_uboot_backup}" = "x" ] ; then
		spl_uboot_name=MLO
		dd_spl_uboot_count="1"
		dd_spl_uboot_seek="1"
		dd_spl_uboot_conf=""
		dd_spl_uboot_bs="128k"
		dd_spl_uboot_backup=/opt/backup/uboot/MLO

		echo "spl_uboot_name=${spl_uboot_name}" >> /boot/SOC.sh
		echo "dd_spl_uboot_count=1" >> /boot/SOC.sh
		echo "dd_spl_uboot_seek=1" >> /boot/SOC.sh
		echo "dd_spl_uboot_conf=" >> /boot/SOC.sh
		echo "dd_spl_uboot_bs=128k" >> /boot/SOC.sh
		echo "dd_spl_uboot_name=${dd_spl_uboot_name}" >> /boot/SOC.sh
	fi

	if [ ! -f /opt/backup/uboot/MLO ] ; then
		mkdir -p /opt/backup/uboot/
		wget --directory-prefix=/opt/backup/uboot/ http://rcn-ee.net/deb/tools/am335x_evm/MLO-am335x_evm-v2015.01-r7
		mv /opt/backup/uboot/MLO-am335x_evm-v2015.01-r7 /opt/backup/uboot/MLO
	fi

	if [ "x${dd_uboot_backup}" = "x" ] ; then
		uboot_name=u-boot.img
		dd_uboot_count="2"
		dd_uboot_seek="1"
		dd_uboot_conf=""
		dd_uboot_bs="384k"
		dd_uboot_backup=/opt/backup/uboot/u-boot.img

		echo "uboot_name=${uboot_name}" >> /boot/SOC.sh
		echo "dd_uboot_count=2" >> /boot/SOC.sh
		echo "dd_uboot_seek=1" >> /boot/SOC.sh
		echo "dd_uboot_conf=" >> /boot/SOC.sh
		echo "dd_uboot_bs=384k" >> /boot/SOC.sh
		echo "boot_name=u-boot.img" >> /boot/SOC.sh

		echo "dd_uboot_name=${dd_uboot_name}" >> /boot/SOC.sh
	fi

	if [ ! -f /opt/backup/uboot/u-boot.img ] ; then
		mkdir -p /opt/backup/uboot/
		wget --directory-prefix=/opt/backup/uboot/ http://rcn-ee.net/deb/tools/am335x_evm/u-boot-am335x_evm-v2015.01-r7.img
		mv /opt/backup/uboot/u-boot-am335x_evm-v2015.01-r7.img /opt/backup/uboot/u-boot.img
	fi

	dd_bootloader


#	if [ "x${boot_fstype}" = "xfat" ] ; then
#		mount ${source}p1 /boot/uboot -o ro
#
#		conf_boot_startmb=${conf_boot_startmb:-"1"}
#		conf_boot_endmb=${conf_boot_endmb:-"96"}
#		sfdisk_fstype=${sfdisk_fstype:-"0xE"}
#
#		echo "Formatting: ${destination}"
#		LC_ALL=C sfdisk --force --in-order --Linux --unit M "${destination}" <<-__EOF__
#			${conf_boot_startmb},${conf_boot_endmb},${sfdisk_fstype},*
#			,,,-
#		__EOF__
#
#		flush_cache
#		format_boot
#		format_root
#
#		copy_boot
#		media_rootfs="2"
#		copy_rootfs
#	else
		conf_boot_startmb=${conf_boot_startmb:-"1"}
		sfdisk_fstype=${sfdisk_fstype:-"0x83"}

		echo "Formatting: ${destination}"
		LC_ALL=C sfdisk --force --in-order --Linux --unit M "${destination}" <<-__EOF__
			${conf_boot_startmb},,${sfdisk_fstype},*
		__EOF__

		flush_cache
		format_single_root

		media_rootfs="1"
		copy_rootfs
#	fi
}

check_eeprom
check_running_system
cylon_leds & CYLON_PID=$!
partition_drive
#
