#!/bin/sh

source $PWD/module_env.sh
source $PWD/module_add_user.sh
source $PWD/module_build_tools.sh
source $PWD/module_init_rootfs.sh

function _clean()
{
	make_tools_clean

}

function _build()
{
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
	if [ `whoami` != lfs ]; then
		if [ "$1" == "adduser" ]; then
			if [ -d /home/lfs ]; then
				echo "Delete user lfs"
				del_user
			fi
			
			echo "Add user lfs"			
			add_user
		fi

		if [ -d /home/lfs ]; then
			echo "Please su lfs and build"
		else
			echo "Please adduser lfs and build"
		fi

		exit
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

	exit
	# Stage 1: User is qmd
	# Stage 2: User is lfs
	# Stage 3: User is root
}

main $1

