#!/bin/sh

#Make sure this file only be included once
if [ "$__MODULE_ENV__" == "yes" ]; then
	return
else
	__MODULE_ENV__=yes
fi

SOURCE_TAR=$(dirname $PWD)/packages
TOOLS_SRC=$PWD/tools_srcs
SYSTEM_SRC=$PWD/system_srcs
TOOLS_INSTALL=$(dirname $PWD)/tools
SYSTEM_INSTALL=$(dirname $PWD)/system
# BUILD_INSTALL=$(dirname $PWD)/build
BUILD_INSTALL=$PWD
ROOTFS=$SYSTEM_INSTALL

MAKE_DOC=no
MAKE_CHECK=no
MAKE_FLAGS=-j4

LFS_TGT=$(uname -m)-lfs-linux-gnu


#end
