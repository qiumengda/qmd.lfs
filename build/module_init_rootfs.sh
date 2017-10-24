#!/bin/sh

#Make sure this file only be included once
if [ "$__MODULE_INIT_ROOTFS__" == "yes" ]; then
	return
else
	__MODULE_INIT_ROOTFS__=yes
fi

source $PWD/module_env.sh

function rootfs_clean()
{
	echo "rm $ROOTFS"
	rm -rf $ROOTFS
}

function rootfs_init()
{
	if [ ! -d $ROOTFS ]; then
		mkdir -v $ROOTFS
	fi   

	if [ ! -d $ROOTFS/build ]; then 
		mkdir -v $ROOTFS/build
	fi   

	if [ ! -d $ROOTFS/tools ]; then 
		mkdir -v $ROOTFS/tools
	fi 

	cd $ROOTFS

	# root dir
	sudo mkdir -pv bin boot dev etc home lib media mnt opt proc root run sbin srv sys tmp usr var
	sudo mkdir -pv etc/{opt,sysconfig}
	sudo mkdir -pv lib/firmware
	sudo mkdir -pv media/{floppy,cdrom}
	sudo mkdir -pv usr/{,local/}{bin,include,lib,sbin,src}
	sudo mkdir -pv usr/{,local/}share/{color,dict,doc,info,locale,man}
	sudo mkdir -pv usr/{,local/}share/{misc,terminfo,zoneinfo}
	sudo mkdir -pv usr/{,local/}share/man/man{1..8}
	sudo mkdir -pv usr/libexec
	sudo mkdir -pv var/{log,mail,spool}
	sudo mkdir -pv var/{opt,cache,lib/{color,misc,locate},local}
	case $(uname -m) in
	x86_64)
		sudo ln -svf lib lib64
		sudo ln -svf lib usr/lib64
		sudo ln -svf lib usr/local/lib64 
		;;
	esac
	sudo ln -svf /run var/run
	sudo ln -svf /run/lock var/lock
	sudo install -dv -m 0750 root
	sudo install -dv -m 1777 tmp var/tmp

	sudo ln -svf /tools/bin/{bash,cat,echo,pwd,stty} bin
	sudo ln -svf /tools/bin/perl usr/bin
	sudo ln -svf /tools/lib/libgcc_s.so{,.1} usr/lib
	sudo ln -svf /tools/lib/libstdc++.so{,.6} usr/lib
	sudo ln -svf /proc/self/mounts etc/mtab
	sudo ln -svf bash bin/sh

	sudo mknod -m 600 $ROOTFS/dev/console c 5 1
	sudo mknod -m 666 $ROOTFS/dev/null c 1 3

	#exec tools/bin/bash --login +h

	sudo touch var/log/{btmp,lastlog,wtmp}
	sudo chgrp -v utmp var/log/lastlog
	sudo chmod -v 664  var/log/lastlog
	sudo chmod -v 600  var/log/btmp

	filepath=etc/passwd
	echo "Create $filepath"
	sudo bash -c "cat > $filepath" << EOF
root::0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/bin/false
daemon:x:6:6:Daemon User:/dev/null:/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/var/run/dbus:/bin/false
systemd-bus-proxy:x:72:72:systemd Bus Proxy:/:/bin/false
systemd-journal-gateway:x:73:73:systemd Journal Gateway:/:/bin/false
systemd-journal-remote:x:74:74:systemd Journal Remote:/:/bin/false
systemd-journal-upload:x:75:75:systemd Journal Upload:/:/bin/false
systemd-network:x:76:76:systemd Network Management:/:/bin/false
systemd-resolve:x:77:77:systemd Resolver:/:/bin/false
systemd-timesync:x:78:78:systemd Time Synchronization:/:/bin/false
nobody:x:99:99:Unprivileged User:/dev/null:/bin/false
EOF

	filepath=etc/group
	echo "Create $filepath"
	sudo bash -c "cat > $filepath" << EOF
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
mail:x:34:
systemd-bus-proxy:x:72:
systemd-journal-gateway:x:73:
systemd-journal-remote:x:74:
systemd-journal-upload:x:75:
systemd-network:x:76:
systemd-resolve:x:77:
systemd-timesync:x:78:
nogroup:x:99:
users:x:999:
EOF

	cd -
}

function dirs_umount()
{
	for dir in $ROOTFS/build $ROOTFS/tools; do
		if grep -q "$dir" /proc/mounts; then
			printf "%-32s umount\n" $dir
			sudo umount -v $dir
		else
			printf "%-32s already umounted\n" $dir
		fi
	done
}

function dirs_mount()
{
	if [ ! -d $BUILD_INSTALL ]; then
		mkdir -v $BUILD_INSTALL
	fi

	if [ ! -d $TOOLS_INSTALL ]; then
		mkdir -v $TOOLS_INSTALL
	fi

	for dir in $ROOTFS/build $ROOTFS/tools; do
		if grep -q "$dir" /proc/mounts; then
			printf "%-32s already mounted\n" $dir
			continue
		fi

		if [ ! -d $dir ]; then
			echo "$dir not exists"
			continue
		fi

		case "$dir" in
		"$ROOTFS/build")
			sudo mount -v --bind $BUILD_INSTALL $dir
			;;
		"$ROOTFS/tools")
			sudo mount -v --bind $TOOLS_INSTALL $dir
			;;
		esac
	done
}

function mount_memfs()
{
	mount_list="$ROOTFS/dev $ROOTFS/dev/pts $ROOTFS/proc $ROOTFS/sys $ROOTFS/run"
	umount_list="$ROOTFS/dev/pts $ROOTFS/dev $ROOTFS/proc $ROOTFS/sys $ROOTFS/run"

	if [ "$1" == "clean" ]; then
		list=$umount_list
	else
		list=$mount_list
	fi

	for dir in $list;
	do
		if [ "$1" == "clean" ]; then
			if grep -q "$dir" /proc/mounts; then
				sudo umount -v $dir
			else
				printf "%-32s already umounted\n" $dir
			fi
			continue
		fi

		if grep -q "$dir" /proc/mounts; then
			printf "%-32s already mounted\n" $dir
			continue
		fi

		if [ ! -d $dir ]; then
			echo "$dir not exists"
			continue
		fi

		case "$dir" in
		"$ROOTFS/dev")
			sudo mount -v --bind /dev $dir
			;;
		"$ROOTFS/dev/pts")
			sudo mount -vt devpts devpts $dir -o gid=5,mode=620
			;;
		"$ROOTFS/proc")
			sudo mount -vt proc proc $dir
			;;
		"$ROOTFS/sys")
			sudo mount -vt sysfs sysfs $dir
			;;
		"$ROOTFS/run")
			sudo mount -vt tmpfs tmpfs $dir
			;;
		esac
	done

	if [ -h $ROOTFS/dev/shm ]; then
		dir=$ROOTFS/$(readlink $ROOTFS/dev/shm)
		if [ ! -d $dir ]; then
			sudo mkdir -vp $dir
		fi
	fi
}

function change_root()
{
	if [ "$1" == "mount" ]; then
		mount_memfs
		exit
	elif [ "$1" == "umount" ]; then
		mount_memfs clean
		exit
	fi

	sudo chroot "$ROOTFS" /tools/bin/env -i  \
		HOME=/root                    \
		TERM="$TERM"                  \
		PS1='\u:\w\$ '                \
		PATH=/bin:/usr/bin:/sbin:/usr/sbin:/tools/bin \
		/tools/bin/bash --login +h

	# After chroot, we cannot do anything.
}

#end
