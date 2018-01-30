#!/bin/sh

source $PWD/module_env.sh
source $PWD/module_user.sh
source $PWD/module_rootfs.sh
source $PWD/module_build_tools.sh
source $PWD/module_build_system.sh

function _clean()
{
	umount_dirs
	umount_memfs
	clean_system
	clean_tools
}

function _env()
{
	install_build_tools
}

function _init()
{
	init_rootfs
	mount_dirs
	mount_memfs
}

function _tools()
{
	make_tools
}

function _chroot()
{
	change_root
}

function _system()
{
	make_system
}

function _strip()
{
	make_tools_strip
}

function _usage()
{
	cmd=$1
	echo -e "Usage:"
	echo -e "\tStage 1: User qmd"
	echo -e "\t\t$cmd create_lfs_user"
	echo -e "\t\tsu lfs"
	echo -e "\tStage 2: User lfs"
	echo -e "\t\t$cmd init"
	echo -e "\t\t$cmd tools"
	echo -e "\tStage 3: User root"
	echo -e "\t\t$cmd chroot"
	echo -e "\t\t$cmd system"
	
	print_env
}

function main()
{
	if [ "$1" == "create_lfs_user" ]; then
		if [ `whoami` == lfs ]; then
			echo "You are lfs already"
			return
		fi

		del_lfs_user
		add_lfs_user
		chown_lfs_user
		return
	fi

	case "$1" in
	"clean")
		check_user lfs
		_clean
		;;
	"env")
		check_user lfs
		_env
		;;
	"init")
		check_user lfs
		_init
		;;
	"tools")
		check_user lfs
		_tools
		;;
	"chroot")
		check_user lfs
		_chroot
		;;
	"system")
		check_user root
		_system
		;;
	*)
		_usage $0
		;;
	esac

	return
	# Stage 1: User is qmd
	# Stage 2: User is lfs
	# Stage 3: User is root
}

start=`date`
time main $1
end=`date`

echo -e "$start Start"
echo -e "$end End"
