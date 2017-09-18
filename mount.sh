#!/bin/sh


case "$1" in
"mount")
	sudo mount -v --bind /dev dev
	sudo mount -vt devpts devpts dev/pts -o gid=5,mode=620
	sudo mount -vt proc proc proc
	sudo mount -vt sysfs sysfs sys
	sudo mount -vt tmpfs tmpfs run
	;;
"umount")
	sudo umount -v dev/pts dev proc sys run
	;;
esac
