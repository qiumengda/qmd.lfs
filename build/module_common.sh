#!/bin/sh

#Make sure this file only be included once
if [ "$__MODULE_COMMON__" == "yes" ]; then
	return
else
	__MODULE_COMMON__=yes
fi

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
