#!/bin/sh

source $PWD/module_env.sh
source $PWD/module_user.sh
source $PWD/module_build_tools.sh
source $PWD/module_init_rootfs.sh

function _clean()
{
	make_tools_clean
	dirs_umount
	rootfs_clean
}

function _build()
{
	rootfs_init
	dirs_mount

	make_tools
	# init_rootfs
	# mount_dirs
	# mount_memfs
	# change_root
}

function _strip()
{
	make_tools_strip

}

function main()
{
	if [ "$1" == "adduser" ]; then
		if [ `whoami` == lfs ]; then
			echo "lfs is already running"
			return
		fi

		del_user
		add_user
	fi

	if [ `whoami` != lfs ]; then
		# su - lfs 
		echo "su lfs -c $0 $1"
		su lfs -c "$0 $1"
		return
	fi

	case "$1" in
	"clean")
		_clean
		;;
	"build")
		_build
		;;
	"strip")
		_strip
		;;
	*)
		echo "$0 clean|build|strip"
		;;
	esac

	return
	# Stage 1: User is qmd
	# Stage 2: User is lfs
	# Stage 3: User is root
}

date
time main $1
date
