#!/bin/sh

#Make sure this file only be included once
if [ "$__MODULE_ENV__" == "yes" ]; then
	return
else
	__MODULE_ENV__=yes
fi

TOP=$(dirname $PWD)
SOURCE_INSTALL=$TOP/packages
BUILD_INSTALL=$TOP/build
SYSTEM_INSTALL=$TOP/system
TOOLS_INSTALL=$TOP/tools

SOURCE_TAR=$SOURCE_INSTALL
TOOLS_SRC=$BUILD_INSTALL/tools_srcs
SYSTEM_SRC=$BUILD_INSTALL/system_srcs

ROOTFS=$SYSTEM_INSTALL

MAKE_DOC=no
MAKE_CHECK=no
MAKE_FLAGS=-j4

LFS_TGT=$(uname -m)-lfs-linux-gnu


function print_env()
{
	echo -e "Env status:"
}

function print_title()
{
	echo -e "#####################################"
	echo -e "## $1"
	echo -e "#####################################"
}

function install_build_tools()
{
	sudo apt-get install texinfo #For makeinfo
	sudo apt-get install build-essential #For g++
	sudo apt-get install gawk #For gawk
}

function check_user()
{
	if [ `whoami` != $1 ]; then
		echo "Error: Please su to $1 and run"
		echo "Error: Use $0 create_lfs_user to add lfs user"
		# su lfs -c "$0 $1"
		return
	fi 
}

function check_build_done()
{
	$src=$1
	$build=$2

	if [ ! -d $src ]; then
		echo "$src is not vaild dir"
		exit 1
	fi

	if [ ! -d $build ]; then
		echo "$build is not vaild dir"
		exit 1
	fi

	if [ -f $build/$build-done ]; then
		echo "$build already build"
		sleep 1
		return 0
	else
		rm -vrf $src
		rm -vrf $build
		return 1
	fi
}

function set_build_done()
{
	$build=$1

	if [ ! -d $build ]; then
		echo "$build is not vaild dir"
		exit 1
	fi

	touch $build/$build-done
}

#end
