#!/bin/sh


<<EOF
SOURCE_TAR=$PWD/source_tars
TOOLS_SRC=$PWD/tools_srcs
SYSTEM_SRC=$PWD/system_srcs
TOOLS_INSTALL=$(dirname $PWD)/tools
SYSTEM_INSTALL=$(dirname $PWD)/system
#BUILD_INSTALL=$(dirname $PWD)/build
BUILD_INSTALL=$PWD
ROOTFS=$SYSTEM_INSTALL

MAKE_DOC=no
MAKE_CHECK=no
MAKE_FLAGS=-j4

LFS_TGT=$(uname -m)-lfs-linux-gnu
EOF

source $PWD/module_env.sh
source $PWD/module_add_user.sh
source $PWD/module_build_tools.sh
source $PWD/module_init_rootfs.sh

function main()
{
	case "$1" in
	"clean")
		make_tools_clean
		exit
		;;
	"strip")
		make_tools_strip
		exit
		;;
	*)
		echo "Start to make all"
		;;
	esac

	# Stage 1: User is qmd
	if [ ! -d /home/lfs ]; then
		add_user
	fi

	echo "SU lfs"
	su lfs

	# Stage 2: User is lfs
	make_tools
	# init_rootfs
	# mount_dirs
	# mount_memfs
	# change_root

	# Stage 3: User is root


}

main $1

