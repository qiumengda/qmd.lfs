#!/bin/sh

#Make sure this file only be included once
if [ "$__MODULE_BUILD_TOOLS__" == "yes" ]; then
	return
else
	__MODULE_BUILD_TOOLS__=yes
fi

source $PWD/module_env.sh

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
EOF

LFS_TGT=$(uname -m)-lfs-linux-gnu

function make_tools_binutils_1st()
{
	app=binutils-2.25
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$TOOLS_SRC/$app-1st
	build=$TOOLS_SRC/$app-1st-build

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
		mv -v $TOOLS_SRC/$app $src 
	fi

	if [ ! -d $build ]; then
		mkdir -v $build
	fi

	cd $build
	../$app-1st/configure              \
		--prefix=/tools            \
		--with-sysroot=$ROOTFS     \
		--with-lib-path=/tools/lib \
		--target=$LFS_TGT          \
		--disable-nls              \
		--disable-werror
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make $MAKE_FLAGS
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_binutils_2nd()
{
	app=binutils-2.25
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$TOOLS_SRC/$app-2nd
	build=$TOOLS_SRC/$app-2nd-build

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
		mv -v $TOOLS_SRC/$app $src
	fi

	if [ ! -d $build ]; then
		mkdir -v $build
	fi

	cd $build

	CC=$LFS_TGT-gcc                    \
	AR=$LFS_TGT-ar                     \
	RANLIB=$LFS_TGT-ranlib             \
	../$app-2nd/configure              \
		--prefix=/tools            \
		--disable-nls              \
		--disable-werror           \
		--with-lib-path=/tools/lib \
		--with-sysroot             
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make $MAKE_FLAGS
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi

	make -C ld clean
	make -C ld LIB_PATH=/usr/lib:/lib
	cp -v ld/ld-new /tools/bin

	cd -
}

function make_tools_gcc_1st()
{
	app=gcc-4.9.2
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$TOOLS_SRC/$app-1st
	build=$TOOLS_SRC/$app-1st-build

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
		mv -v $TOOLS_SRC/$app $src

		cd $src

		tar -xvf $SOURCE_TAR/mpfr-3.1.2.tar.xz
		mv -v mpfr-3.1.2 mpfr
		tar -xvf $SOURCE_TAR/gmp-6.0.0a.tar.xz
		mv -v gmp-6.0.0 gmp
		tar -xvf $SOURCE_TAR/mpc-1.0.2.tar.gz
		mv -v mpc-1.0.2 mpc

		for file in \
			$(find gcc/config -name linux64.h -o -name linux.h -o -name sysv4.h)
		do
			cp -uv $file{,.orig}
			sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' \
				-e 's@/usr@/tools@g' $file.orig > $file
			echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
			touch $file.orig
		done

		sed -i '/k prot/agcc_cv_libc_provides_ssp=yes' gcc/configure

		cd -
	fi

	if [ ! -d $build ]; then
		mkdir -v $build
	fi

	cd $build
	../$app-1st/configure                                  \
		--target=$LFS_TGT                              \
		--prefix=/tools                                \
		--with-sysroot=$ROOTFS                         \
		--with-newlib                                  \
		--without-headers                              \
		--with-local-prefix=/tools                     \
		--with-native-system-header-dir=/tools/include \
		--disable-nls                                  \
		--disable-shared                               \
		--disable-multilib                             \
		--disable-decimal-float                        \
		--disable-threads                              \
		--disable-libatomic                            \
		--disable-libgomp                              \
		--disable-libitm                               \
		--disable-libquadmath                          \
		--disable-libsanitizer                         \
		--disable-libssp                               \
		--disable-libvtv                               \
		--disable-libcilkrts                           \
		--disable-libstdc++-v3                         \
		--enable-languages=c,c++
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make $MAKE_FLAGS
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_gcc_2nd()
{
	app=gcc-4.9.2
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$TOOLS_SRC/$app-2nd
	build=$TOOLS_SRC/$app-2nd-build

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
		mv -v $TOOLS_SRC/$app $src

		cd $src

		cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
			`dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include-fixed/limits.h

		for file in \
			$(find gcc/config -name linux64.h -o -name linux.h -o -name sysv4.h)
		do
			cp -uv $file{,.orig}
			sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' \
				-e 's@/usr@/tools@g' $file.orig > $file
			echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
			touch $file.orig
		done

		tar -xvf $SOURCE_TAR/mpfr-3.1.2.tar.xz
		mv -v mpfr-3.1.2 mpfr
		tar -xvf $SOURCE_TAR/gmp-6.0.0a.tar.xz
		mv -v gmp-6.0.0 gmp
		tar -xvf $SOURCE_TAR/mpc-1.0.2.tar.gz
		mv -v mpc-1.0.2 mpc

		cd -
	fi

	if [ ! -d $build ]; then
		mkdir -v $build
	fi

	cd $build

	CC=$LFS_TGT-gcc                                        \
	CXX=$LFS_TGT-g++                                       \
	AR=$LFS_TGT-ar                                         \
	RANLIB=$LFS_TGT-ranlib                                 \
	../$app-2nd/configure                                  \
		--prefix=/tools                                \
		--with-local-prefix=/tools                     \
		--with-native-system-header-dir=/tools/include \
		--enable-languages=c,c++                       \
		--disable-libstdcxx-pch                        \
		--disable-multilib                             \
		--disable-bootstrap                            \
		--disable-libgomp
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make $MAKE_FLAGS
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	sudo bash -c "sed 's/tools/usr/' /tools/lib/libstdc++.la > $ROOTFS/usr/lib/libstdc++.la"
	ln -sv gcc /tools/bin/cc
	# Test
	echo 'main(){}' > dummy.c
	cc dummy.c
	readelf -l a.out | grep ': /tools'
	rm -v dummy.c a.out
	cd -
}

function make_tools_libstdcxx()
{
	app=gcc-4.9.2
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$TOOLS_SRC/$app-libstdcxx
	build=$TOOLS_SRC/$app-libstdcxx-build

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
		mv -v $TOOLS_SRC/$app $src
	fi

	if [ ! -d $build ]; then
		mkdir -v $build
	fi

	cd $build
	../$app-libstdcxx/libstdc++-v3/configure  \
		--host=$LFS_TGT                  \
		--prefix=/tools                  \
		--disable-multilib               \
		--disable-shared                 \
		--disable-nls                    \
		--disable-libstdcxx-threads      \
		--disable-libstdcxx-pch          \
		--with-gxx-include-dir=/tools/$LFS_TGT/include/c++/4.9.2
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make $MAKE_FLAGS
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_kernel_headers()
{
	app=linux-3.19
	tar=$SOURCE_TAR/$app.tar.xz
	src=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $src
	make mrproper
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make INSTALL_HDR_PATH=dest headers_install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	mv -v dest/include/* /tools/include
	cd -
}

function make_tools_glibc()
{
	app=glibc-2.21
	tar=$SOURCE_TAR/$app.tar.xz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app-build

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC

		cd $src
		if [ ! -r /usr/include/rpc/types.h ]; then
			su -c 'mkdir -pv /usr/include/rpc'
			su -c 'cp -v sunrpc/rpc/*.h /usr/include/rpc'
		fi
		echo "sed ..."
		sed -e '/ia32/s/^/1:/' -e '/SSE2/s/^1://' -i sysdeps/i386/i686/multiarch/mempcpy_chk.S
		cd -
	fi

	if [ ! -d $build ]; then
		mkdir -v $build
	fi

	cd $build
	../$app/configure                                     \
		--prefix=/tools                               \
		--host=$LFS_TGT                               \
		--build=$(../$app/scripts/config.guess)       \
		--disable-profile                             \
		--enable-kernel=2.6.32                        \
		--with-headers=/tools/include                 \
		libc_cv_forced_unwind=yes                     \
		libc_cv_ctors_header=yes                      \
		libc_cv_c_cleanup=yes
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make $MAKE_FLAGS
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
	
	# For test ld-linux.so
	echo 'main(){}' > dummy.c
	$LFS_TGT-gcc dummy.c
	readelf -l a.out | grep ': /tools'
	rm -v dummy.c a.out
}

function make_tools_tcl()
{
	app=tcl8.6.3
	tar=$SOURCE_TAR/$app-src.tar.gz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app/unix

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		TZ=UTC make test
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	#sudo chmod -v u+w /tools/lib/libtcl8.6.so
	make install-private-headers
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	ln -sv tclsh8.6 /tools/bin/tclsh
	cd -
}

function make_tools_expect()
{
	app=expect5.45
	tar=$SOURCE_TAR/$app.tar.gz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
		cd $src
		cp -v configure{,.orig}
		sed 's:/usr/local/bin:/bin:' configure.orig > configure
		cd -
	fi

	cd $build
	./configure --prefix=/tools \
		--with-tcl=/tools/lib \
		--with-tclinclude=/tools/include
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make test
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make SCRIPTS="" install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_dejagnu()
{
	app=dejagnu-1.5.2
	tar=$SOURCE_TAR/$app.tar.gz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	cd -
}

function make_tools_check()
{
	app=check-0.9.14
	tar=$SOURCE_TAR/$app.tar.gz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	PKG_CONFIG= ./configure --prefix=/tools
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check # use very long time
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_ncurses()
{
	app=ncurses-5.9
	tar=$SOURCE_TAR/$app.tar.gz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools \
		--with-shared   \
		--without-debug \
		--without-ada   \
		--enable-widec  \
		--enable-overwrite
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_bash()
{
	app=bash-4.3.30
	tar=$SOURCE_TAR/$app.tar.gz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools --without-bash-malloc
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make tests
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	ln -sv bash /tools/bin/sh
	cd -
}

function make_tools_bzip2()
{
	app=bzip2-1.0.6
	tar=$SOURCE_TAR/$app.tar.gz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make PREFIX=/tools install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_coreutils()
{
	app=coreutils-8.23
	tar=$SOURCE_TAR/$app.tar.xz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools --enable-install-program=hostname
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make RUN_EXPENSIVE_TESTS=yes check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_diffutils()
{
	app=diffutils-3.3
	tar=$SOURCE_TAR/$app.tar.xz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_file()
{
	app=file-5.22
	tar=$SOURCE_TAR/$app.tar.gz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_findutils()
{
	app=findutils-4.4.2
	tar=$SOURCE_TAR/$app.tar.gz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_gawk()
{
	app=gawk-4.1.1
	tar=$SOURCE_TAR/$app.tar.xz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_gettext()
{
	app=gettext-0.19.4
	tar=$SOURCE_TAR/$app.tar.xz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build/gettext-tools
	EMACS="no" ./configure --prefix=/tools --disable-shared
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make -C gnulib-lib
	make -C intl pluralx.c
	make -C src msgfmt
	make -C src msgmerge
	make -C src xgettext
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cp -v src/{msgfmt,msgmerge,xgettext} /tools/bin
	cd -
}

function make_tools_grep()
{
	app=grep-2.21
	tar=$SOURCE_TAR/$app.tar.xz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_gzip()
{
	app=gzip-1.6
	tar=$SOURCE_TAR/$app.tar.xz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_m4()
{
	app=m4-1.4.17
	tar=$SOURCE_TAR/$app.tar.xz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_make()
{
	app=make-4.1
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools --without-guile
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_patch()
{
	app=patch-2.7.4
	tar=$SOURCE_TAR/$app.tar.xz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools --without-guile
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_perl()
{
	app=perl-5.20.2
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	sh Configure -des -Dprefix=/tools -Dlibs=-lm
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cp -v perl cpan/podlators/pod2man /tools/bin
	mkdir -pv /tools/lib/perl5/5.20.2
	cp -Rv lib/* /tools/lib/perl5/5.20.2
	cd -
}

function make_tools_sed()
{
	app=sed-4.2.2
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_tar()
{
	app=tar-1.28
	tar=$SOURCE_TAR/$app.tar.xz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_texinfo()
{
	app=texinfo-5.2
	tar=$SOURCE_TAR/$app.tar.xz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_util_linux()
{
	app=util-linux-2.26
	tar=$SOURCE_TAR/$app.tar.xz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools            \
		--without-python               \
		--disable-makeinstall-chown    \
		--without-systemdsystemunitdir \
		PKG_CONFIG=""
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools_xz()
{
	app=xz-5.2.0
	tar=$SOURCE_TAR/$app.tar.xz
	src=$TOOLS_SRC/$app
	build=$TOOLS_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $TOOLS_SRC
	fi

	cd $build
	./configure --prefix=/tools
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes"]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_tools()
{
	make_tools_binutils_1st
	make_tools_gcc_1st
	make_tools_kernel_headers
	make_tools_glibc
	make_tools_libstdcxx

	make_tools_binutils_2nd
	make_tools_gcc_2nd
	make_tools_tcl
	make_tools_expect
	make_tools_dejagnu
	make_tools_check
	make_tools_ncurses
	make_tools_bash
	make_tools_bzip2
	make_tools_coreutils
	make_tools_diffutils
	make_tools_file
	make_tools_findutils
	make_tools_gawk
	make_tools_gettext
	make_tools_grep
	make_tools_gzip
	make_tools_m4
	make_tools_make
	make_tools_patch
	make_tools_perl
	make_tools_sed
	make_tools_tar
	make_tools_texinfo
	make_tools_util_linux
	make_tools_xz
}

function make_tools_strip()
{
<<EOF
	strip --strip-debug /tools/lib/*
	/usr/bin/strip --strip-unneeded /tools/{,s}bin/*
	rm -rf /tools/{,share}/{info,man,doc}
EOF

	files=$(/usr/bin/find /tools/{bin,lib,sbin})
	for file in $files;
	do
		echo "Check $file"
		if echo "$file" | grep -E "*\.a$|*\.ko$|*\.o$" ; then
			echo "Skip $file"
			continue
		fi
		if /usr/bin/file $file | /bin/grep "not stripped" ; then
			echo "strip $file"
			/usr/bin/strip $file
		else
			echo "Can not strip $(/usr/bin/file $file)"
		fi
	done
}

function make_tools_init()
{
        if [ ! -d $TOOLS_SRC ]; then
                mkdir -v $TOOLS_SRC
        fi

        if [ ! -d $TOOLS_INSTALL ]; then
                mkdir -v $TOOLS_INSTALL
        fi

        if [ ! -d $TOOLS_INSTALL/lib ]; then
                mkdir -v $TOOLS_INSTALL/lib
        fi
	
        case $(uname -m) in
        x86_64)
                if [ ! -L $TOOLS_INSTALL/lib64 ]; then
                        ln -sv lib $TOOLS_INSTALL/lib64 
                fi
                ;;
        esac

        if [ ! -L /tools ]; then
                sudo ln -sv $TOOLS_INSTALL /tools
        fi

}

function make_tools_clean()                                                                                                                                                      
{
        rm -vrf $TOOLS_SRC
	rm -vrf $TOOLS_INSTALL
	rm -vrf /tools
}

