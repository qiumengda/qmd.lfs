#!/bin/sh

#Make sure this file only be included once
if [ "$__MODULE_ENV__" == "yes" ]; then
	return
else
	__MODULE_ENV__=yes
fi

TOP=$(dirname $PWD)
SOURCE_TAR=$TOP/packages
BUILD_INSTALL=$TOP/build
SYSTEM_INSTALL=$TOP/system
TOOLS_INSTALL=$TOP/tools
TOOLS_SRC=$BUILD_INSTALL/tools_srcs
SYSTEM_SRC=$BUILD_INSTALL/system_srcs
ROOTFS=$SYSTEM_INSTALL

MAKE_DOC=no
MAKE_CHECK=no
MAKE_FLAGS=-j4

LFS_TGT=$(uname -m)-lfs-linux-gnu


#end
