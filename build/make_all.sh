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

function _env()
{
	install_build_tools
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

	if [ `whoami` != lfs ]; then
		echo "> Please su to lfs and run"
		echo "> Use $0 create_lfs_user to add lfs user"
		# su lfs -c "$0 $1"
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
	"env")
		_env
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

start=`date`
time main $1
end=`date`

echo -e "$start Start"
echo -e "$end End"
