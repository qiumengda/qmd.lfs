#!/bin/sh

# /dev/sdb1 - lfs
# /dev/sdb2 - swap

SOURCE_TAR=$PWD/source_tars
TOOLS_SRC=$PWD/tools_srcs
SYSTEM_SRC=$PWD/system_srcs
MAKE_SKIP_CHECK=yes
MAKE_FLAGS=-j4

export LFS=/mnt/lfs

function create_disk()
{
<< "EOF"
sudo fdisk /dev/sdb

# sdb1
n
p
1
100GB
a
1

# sdb2
n
e
2
xxxGB (Left all)

# sdb5
n
l
2GB
t
5
82

# sdb6
n
l
xxxGB (Left all)

w

sudo mkfs -v -t ext4 /dev/sdb1
sudo mkswap /dev/sdb5
sudo mkfs -v -t ext4 /dev/sdb6
EOF

	if [ ! -d $LFS ]; then
		mkdir -vp $LFS
	fi

	sudo mount -v -t ext4 /dev/sda1 $LFS

}

function create_user()
{
	groupadd lfs
	useradd -s /bin/bash -g lfs -m -k /dev/null lfs
	passwd lfs

	cat > /home/lfs/.bash_profile << "EOF"
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF

	cat > /home/lfs/.bashrc << "EOF"
set +h
umask 022
LFS=/mnt/lfs
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/tools/bin:/bin:/usr/bin
export LFS LC_ALL LFS_TGT PATH
EOF

	su - lfs
	#source /home/lfs/.bash_profile
	#sudo swapon -v /dev/sdb2
	#sudo chmod -v a+wt $LFS/sources

	if [ ! -d $LFS/tools ]; then
		mkdir -vp $LFS/tools
	fi

	if [ ! -f /tools ]; then
		ln -sv $LFS/tools /
	fi

	case $(uname -m) in
		x86_64)
			mkdir -v /tools/lib
			ln -sv lib /tools/lib64 
		;;
	esac

	#sudo chown -vR $LFS
}

function create_srcs()
{
	if [ -d $SOURCE_TAR ]; then
		rm -vrf $SOURCE_TAR
	fi
	mkdir -v $SOURCE_TAR

	if [ -d $TOOLS_SRC ]; then
		rm -vrf $TOOLS_SRC
	fi
	mkdir -v $TOOLS_SRC

	if [ -d $SYSTEM_SRC ]; then
		rm -vrf $SYSTEM_SRC
	fi
	mkdir -v $SYSTEM_SRC

	tar -xvf lfs-packages-7.7-systemd.tar -C $SOURCE_TAR
	#wget --input-file=wget-list --continue --directory-prefix=$LFS/sources
	#pushd $LFS/sources
	#md5sum -c md5sums
	#popd

	#sudo chown -vR $SOURCE_TAR
}

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
		--with-sysroot=$LFS        \
		--with-lib-path=/tools/lib \
		--target=$LFS_TGT          \
		--disable-nls              \
		--disable-werror
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
	make
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
		--with-sysroot=$LFS                            \
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
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi

	ln -sv gcc /tools/bin/cc

	cd -

	echo 'main(){}' > dummy.c
	cc dummy.c
	readelf -l a.out | grep ': /tools'
	rm -v dummy.c a.out
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
	make
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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
	if [ "$MAKE_SKIP_CHECK" != "yes"]; then
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

function make_tools_clean()
{
	rm -vrf $TOOLS_SRC
	mkdir -v $TOOLS_SRC

	sudo rm -vrf $LFS/tools
	mkdir -v $LFS/tools

	case $(uname -m) in
		x86_64)
			mkdir -v /tools/lib
			ln -sv lib /tools/lib64 
		;;
	esac
}

function make_tools()
{
	if [ "$1" == "clean" ]; then
		make_tools_clean
		exit
	fi

	if [ ! -d $TOOLS_SRC ]; then
		mkdir -vp $TOOLS_SRC
	fi

	if [ ! -d $LFS/tools ]; then
		mkdir -vp $LFS/tools
		case $(uname -m) in
			x86_64)
				mkdir -v /tools/lib
				ln -sv lib /tools/lib64 
			;;
		esac
	fi

	if [ ! -f /tools ]; then
		sudo ln -sv $LFS/tools /tools
	fi

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

function memfs_mount()
{
	mkdir -pv $LFS/{dev,proc,sys,run}
	sudo mknod -m 600 $LFS/dev/console c 5 1
	sudo mknod -m 666 $LFS/dev/null c 1 3
	sudo mount -v --bind /dev $LFS/dev
	sudo mount -vt devpts devpts $LFS/dev/pts -o gid=5,mode=620
	if [ -h $LFS/dev/shm ]; then
		sudo mkdir -vp $LFS/$(readlink $LFS/dev/shm)
	fi
	sudo mount -vt proc proc $LFS/proc
	sudo mount -vt sysfs sysfs $LFS/sys
	sudo mount -vt tmpfs tmpfs $LFS/run
}

function memfs_umount()
{
	sudo umount -v $LFS/{dev/pts,dev,proc,sys,run}
}

function make_rootfs_clean()
{
	if [ -d /qmd ]; then
		echo  "You must be host"
		exit
	fi

	cd $LFS
	sudo umount -v dev/pts dev proc sys run
	sudo rm -vrf bin boot dev etc home lib media mnt opt proc root run sbin srv sys tmp usr var
	case $(uname -m) in
	x86_64)
		sudo rm -vrf lib64
		;;
	esac
	cd -
}

function make_rootfs()
{
	if [ -d /qmd ]; then
		echo  "You must be host"
		exit
	fi

	if [ "$1" == "clean" ]; then
		make_rootfs_clean
		exit
	elif [ "$1" == "mount" ]; then
		memfs_mount
		exit
	elif [ "$1" == "umount" ]; then
		memfs_umount
		exit
	fi

	echo "make rootfs FHS"

	cd $LFS
	# root dir
	sudo mkdir -pv bin boot dev etc home lib media mnt opt proc root run sbin srv sys tmp usr var
	sudo mkdir -pv etc/{opt,sysconfig}
	sudo mkdir -pv lib/firmware
	sudo mkdir -pv media/{floppy,cdrom}
	sudo mkdir -pv usr/{,local/}{bin,include,lib,sbin,src}
	sudo mkdir -pv usr/{,local/}share/{color,dict,doc,info,locale,man}
	sudo mkdir -pv usr/{,local/}share/{misc,terminfo,zoneinfo}
	sudo mkdir -pv usr/{,local/}share/man/man{1..8}
	sudo mkdir -pv usr/libexec
	sudo mkdir -pv var/{log,mail,spool}
	sudo mkdir -pv var/{opt,cache,lib/{color,misc,locate},local}
	case $(uname -m) in
	x86_64)
		sudo ln -sv lib lib64
		sudo ln -sv lib usr/lib64
		sudo ln -sv lib usr/local/lib64 
		;;
	esac
	sudo ln -sv /run var/run
	sudo ln -sv /run/lock var/lock
	sudo install -dv -m 0750 root
	sudo install -dv -m 1777 tmp var/tmp

	sudo ln -sv /tools/bin/{bash,cat,echo,pwd,stty} bin
	sudo ln -sv /tools/bin/perl usr/bin
	sudo ln -sv /tools/lib/libgcc_s.so{,.1} usr/lib
	sudo ln -sv /tools/lib/libstdc++.so{,.6} usr/lib
	sudo ln -sv /proc/self/mounts etc/mtab
	sudo ln -sv bash bin/sh
	sudo bash -c "sed 's/tools/usr/' tools/lib/libstdc++.la > usr/lib/libstdc++.la"

	sudo bash -c "cat > etc/passwd << EOF
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/bin/false
daemon:x:6:6:Daemon User:/dev/null:/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/var/run/dbus:/bin/false
systemd-bus-proxy:x:72:72:systemd Bus Proxy:/:/bin/false
systemd-journal-gateway:x:73:73:systemd Journal Gateway:/:/bin/false
systemd-journal-remote:x:74:74:systemd Journal Remote:/:/bin/false
systemd-journal-upload:x:75:75:systemd Journal Upload:/:/bin/false
systemd-network:x:76:76:systemd Network Management:/:/bin/false
systemd-resolve:x:77:77:systemd Resolver:/:/bin/false
systemd-timesync:x:78:78:systemd Time Synchronization:/:/bin/false
nobody:x:99:99:Unprivileged User:/dev/null:/bin/false
EOF"

	sudo bash -c "cat > etc/group << EOF
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
mail:x:34:
systemd-bus-proxy:x:72:
systemd-journal-gateway:x:73:
systemd-journal-remote:x:74:
systemd-journal-upload:x:75:
systemd-network:x:76:
systemd-resolve:x:77:
systemd-timesync:x:78:
nogroup:x:99:
users:x:999:
EOF"

	#exec tools/bin/bash --login +h

	sudo touch var/log/{btmp,lastlog,wtmp}
	sudo chgrp -v utmp var/log/lastlog
	sudo chmod -v 664  var/log/lastlog
	sudo chmod -v 600  var/log/btmp

	cd -
}

function change_root()
{
	if [ "$1" == "umount" ]; then
		echo "umount"
		memfs_umount
	elif [ "$1" == "mount" ]; then
		echo "mount"
		memfs_mount	
	fi
	
	sudo chroot "$LFS" /tools/bin/env -i  \
		HOME=/root                    \
		TERM="$TERM"                  \
		PS1='\u:\w\$ '                \
		PATH=/bin:/usr/bin:/sbin:/usr/sbin:/tools/bin \
		/tools/bin/bash --login +h

	# After chroot, we cannot do anything.
}

function make_system_clean()
{
	echo "system clean"
}

function make_system_kernel_headers()
{
	app=linux-3.19
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	make mrproper
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make INSTALL_HDR_PATH=dest headers_install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	find dest/include \( -name .install -o -name ..install.cmd \) -delete
	mv -v dest/include/* /usr/include
	cd -
}

function make_system_manpages()
{
	app=man-pages-3.79
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_system_glibc()
{
	app=glibc-2.21
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app-build

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC

		cd $src
		patch -Np1 -i $SOURCE_TAR/glibc-2.21-fhs-1.patch
		sed -e '/ia32/s/^/1:/' \
		    -e '/SSE2/s/^1://' \
		    -i  sysdeps/i386/i686/multiarch/mempcpy_chk.S
		cd -
	fi

	if [ ! -d $build ]; then
		mkdir -v $build
	fi

	cd $build
#<< "EOF"
	../glibc-2.21/configure        \
		--prefix=/usr          \
		--disable-profile      \
		--enable-kernel=2.6.32 \
		--enable-obsolete-rpc
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make $MAKE_FLAGS
	if [ $? != 0 ]; then
		echo fail; exit
	fi
#EOF
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make -i $MAKE_FLAGS check   # Ignore some fail
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	touch /etc/ld.so.conf
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi

	# Install language
	cp -v ../glibc-2.21/nscd/nscd.conf /etc/nscd.conf
	mkdir -pv /var/cache/nscd
	install -v -Dm644 ../glibc-2.21/nscd/nscd.tmpfiles /usr/lib/tmpfiles.d/nscd.conf
	install -v -Dm644 ../glibc-2.21/nscd/nscd.service /lib/systemd/system/nscd.service
	mkdir -pv /usr/lib/locale
	localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8
	localedef -i de_DE -f ISO-8859-1 de_DE
	localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro
	localedef -i de_DE -f UTF-8 de_DE.UTF-8
	localedef -i en_GB -f UTF-8 en_GB.UTF-8
	localedef -i en_HK -f ISO-8859-1 en_HK
	localedef -i en_PH -f ISO-8859-1 en_PH
	localedef -i en_US -f ISO-8859-1 en_US
	localedef -i en_US -f UTF-8 en_US.UTF-8
	localedef -i es_MX -f ISO-8859-1 es_MX
	localedef -i fa_IR -f UTF-8 fa_IR
	localedef -i fr_FR -f ISO-8859-1 fr_FR
	localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
	localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
	localedef -i it_IT -f ISO-8859-1 it_IT
	localedef -i it_IT -f UTF-8 it_IT.UTF-8
	localedef -i ja_JP -f EUC-JP ja_JP
	localedef -i ru_RU -f KOI8-R ru_RU.KOI8-R
	localedef -i ru_RU -f UTF-8 ru_RU.UTF-8
	localedef -i tr_TR -f UTF-8 tr_TR.UTF-8
	localedef -i zh_CN -f GB18030 zh_CN.GB18030

	# Configure glibc

	# 
	cat > /etc/nsswitch.conf << "EOF"
# Begin /etc/nsswitch.conf

passwd: files
group: files
shadow: files

hosts: files dns myhostname
networks: files

protocols: files
services: files
ethers: files
rpc: files

# End /etc/nsswitch.conf
EOF

	# Timezone
	tar -xf $SOURCE_TAR/tzdata2015a.tar.gz
	ZONEINFO=/usr/share/zoneinfo
	mkdir -pv $ZONEINFO/{posix,right}
	for tz in etcetera southamerica northamerica europe africa antarctica  \
		asia australasia backward pacificnew systemv; do
		zic -L /dev/null   -d $ZONEINFO       -y "sh yearistype.sh" ${tz}
		zic -L /dev/null   -d $ZONEINFO/posix -y "sh yearistype.sh" ${tz}
		zic -L leapseconds -d $ZONEINFO/right -y "sh yearistype.sh" ${tz}
	done
	cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO
	zic -d $ZONEINFO -p America/New_York
	unset ZONEINFO
	#tzselect
	#ln -sfv /usr/share/zoneinfo/<xxx> /etc/localtime

	# so loader
	cat > /etc/ld.so.conf << "EOF"
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib

# Add an include directory
include /etc/ld.so.conf.d/*.conf

EOF
	mkdir -pv /etc/ld.so.conf.d
	cd -
}

function make_system_toolchain()
{
	if [ -f /tools/bin/ld-new ]; then
		mv -v /tools/bin/{ld,ld-old}
		mv -v /tools/$(gcc -dumpmachine)/bin/{ld,ld-old}
		mv -v /tools/bin/{ld-new,ld}
		ln -sv /tools/bin/ld /tools/$(gcc -dumpmachine)/bin/ld
	fi

	gcc -dumpspecs | sed -e 's@/tools@@g'                       \
		-e '/\*startfile_prefix_spec:/{n;s@.*@/usr/lib/ @}' \
		-e '/\*cpp:/{n;s@$@ -isystem /usr/include@}' >      \
		`dirname $(gcc --print-libgcc-file-name)`/specs

	# Test
	echo 'main(){}' > dummy.c
	cc dummy.c -v -Wl,--verbose &> dummy.log
	readelf -l a.out | grep ': /lib'                    # [Requesting program interpreter: /lib/ld-linux.so.2]
	grep -o '/usr/lib.*/crt[1in].*succeeded' dummy.log  # /usr/lib/{crt1.o,crti.o,crtn.o} succeeded
	grep -B1 '^ /usr/include' dummy.log                 # #include <...> search starts here: /usr/include
	grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'  # SEARCH_DIR("/usr/lib") SEARCH_DIR("/lib")
	grep "/lib.*/libc.so.6 " dummy.log                  # attempt to open /lib/libc.so.6 succeeded
	grep found dummy.log                                # found ld-linux.so.2 at /lib/ld-linux.so.2
	rm -v dummy.c a.out dummy.log
}

function make_system_zlib()
{
	app=zlib-1.2.8
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	mv -v /usr/lib/libz.so.* /lib
	ln -sfv /lib/$(readlink /usr/lib/libz.so) /usr/lib/libz.so
	cd -
}

function make_system_file()
{
	app=file-5.22
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
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

function make_system_binutils()
{
	app=binutils-2.25
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app-build

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	if [ ! -d $build ]; then
		mkdir -v $build
	fi

	expect -c "spawn ls"              # spawn ls

	cd $build
	../$app/configure --prefix=/usr   \
	                  --enable-shared    \
	                  --disable-werror
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make tooldir=/usr $MAKE_FLAGS
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make -k $MAKE_FLAGS check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make tooldir=/usr install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_system_gmp()
{
	app=gmp-6.0.0
	tar=$SOURCE_TAR/${app}a.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr   \
		--enable-cxx        \
		--docdir=/usr/share/doc/gmp-6.0.0a
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make html
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check 2>&1 | tee gmp-check-log
		if [ $? != 0 ]; then
			echo fail; exit
		fi
		awk '/tests passed/{total+=$2} ; END{print total}' gmp-check-log
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install-html
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_system_mpfr()
{
	app=mpfr-3.1.2
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC

		cd $src
		patch -Np1 -i $SOURCE_TAR/mpfr-3.1.2-upstream_fixes-3.patch
		cd -
	fi

	cd $build
	./configure --prefix=/usr        \
        	    --enable-thread-safe \
        	    --docdir=/usr/share/doc/mpfr-3.1.2
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make html
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install-html
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_system_mpc()
{
	app=mpc-1.0.2
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr --docdir=/usr/share/doc/mpc-1.0.2
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make html
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install-html
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_system_gcc()
{
	app=gcc-4.9.2
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app-build

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	if [ ! -d $build ]; then
		mkdir -v $build
	fi

	cd $build
#<< "EOF"
	SED=sed                       \
	../$app/configure             \
	     --prefix=/usr            \
	     --enable-languages=c,c++ \
	     --disable-multilib       \
	     --disable-bootstrap      \
	     --with-system-zlib
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make $MAKE_FLAGS
	if [ $? != 0 ]; then
		echo fail; exit
	fi
#EOF
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		ulimit -s 32768
		#make -k check
		make -i $MAKE_FLAGS check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
		#../$app/contrib/test_summary | grep -A7 Summ
		../$app/contrib/test_summary
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	ln -sv /usr/bin/cpp /lib
	ln -sv gcc /usr/bin/cc
	install -v -dm755 /usr/lib/bfd-plugins
	ln -sfv /usr/libexec/gcc/$(gcc -dumpmachine)/4.9.2/liblto_plugin.so /usr/lib/bfd-plugins/

	# Test
	echo 'main(){}' > dummy.c
	cc dummy.c -v -Wl,--verbose &> dummy.log
	readelf -l a.out | grep ': /lib' 			
	#Output: 
	# [Requesting program interpreter: /lib/ld-linux.so.2]
	grep -o '/usr/lib.*/crt[1in].*succeeded' dummy.log 	
	#Output:
	# /usr/lib/gcc/i686-pc-linux-gnu/4.9.2/../../../crt1.o succeeded
	# /usr/lib/gcc/i686-pc-linux-gnu/4.9.2/../../../crti.o succeeded
	# /usr/lib/gcc/i686-pc-linux-gnu/4.9.2/../../../crtn.o succeeded
	grep -B4 '^ /usr/include' dummy.log			
	#Output:
	# #include <...> search starts here:
	#  /usr/lib/gcc/i686-pc-linux-gnu/4.9.2/include
	#  /usr/local/include
	#  /usr/lib/gcc/i686-pc-linux-gnu/4.9.2/include-fixed
	#  /usr/include 
	grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
	#Output
	# SEARCH_DIR("/usr/x86_64-unknown-linux-gnu/lib64")
	# SEARCH_DIR("/usr/local/lib64")
	# SEARCH_DIR("/lib64")
	# SEARCH_DIR("/usr/lib64")
	# SEARCH_DIR("/usr/x86_64-unknown-linux-gnu/lib")
	# SEARCH_DIR("/usr/local/lib")
	# SEARCH_DIR("/lib")
	# SEARCH_DIR("/usr/lib");
	grep "/lib.*/libc.so.6 " dummy.log
	#Output:
	# attempt to open /lib/libc.so.6 succeeded
	grep found dummy.log
	#Output:
	# found ld-linux.so.2 at /lib/ld-linux.so.2
	rm -v dummy.c a.out dummy.log
	mkdir -pv /usr/share/gdb/auto-load/usr/lib
	mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
	cd -
}

function make_system_bzip2()
{
	app=bzip2-1.0.6
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		patch -Np1 -i $SOURCE_TAR/bzip2-1.0.6-install_docs-1.patch	
		sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
		sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
		cd -
	fi

	cd $build
	make -f Makefile-libbz2_so
	make clean
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make PREFIX=/usr install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cp -v bzip2-shared /bin/bzip2
	cp -av libbz2.so* /lib
	ln -sv /lib/libbz2.so.1.0 /usr/lib/libbz2.so
	rm -v /usr/bin/{bunzip2,bzcat,bzip2}
	ln -sv bzip2 /bin/bunzip2
	ln -sv bzip2 /bin/bzcat
	cd -
}

function make_system_pkgconfig()
{
	app=pkg-config-0.28
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr        \
		    --with-internal-glib \
		    --disable-host-tool  \
		    --docdir=/usr/share/doc/pkg-config-0.28
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
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

function make_system_ncurses()
{
	app=ncurses-5.9
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr           \
		    --mandir=/usr/share/man \
		    --with-shared           \
		    --without-debug         \
		    --enable-pc-files       \
		    --enable-widec
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
	# To /lib
	mv -v /usr/lib/libncursesw.so.5* /lib
	ln -sfv /lib/$(readlink /usr/lib/libncursesw.so) /usr/lib/libncursesw.so
	#
	for lib in ncurses form panel menu ; do
		rm -vf                    /usr/lib/lib${lib}.so
		echo "INPUT(-l${lib}w)" > /usr/lib/lib${lib}.so
		ln -sfv lib${lib}w.a      /usr/lib/lib${lib}.a
		ln -sfv ${lib}w.pc        /usr/lib/pkgconfig/${lib}.pc
	done
	ln -sfv libncurses++w.a /usr/lib/libncurses++.a
	#
	rm -vf                     /usr/lib/libcursesw.so
	echo "INPUT(-lncursesw)" > /usr/lib/libcursesw.so
	ln -sfv libncurses.so      /usr/lib/libcurses.so
	ln -sfv libncursesw.a      /usr/lib/libcursesw.a
	ln -sfv libncurses.a       /usr/lib/libcurses.a
	# doc
	mkdir -v       /usr/share/doc/ncurses-5.9
	cp -v -R doc/* /usr/share/doc/ncurses-5.9
	cd -
}

function make_system_attr()
{
	app=attr-2.4.47
	tar=$SOURCE_TAR/$app.src.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		sed -i -e 's|/@pkg_name@|&-@pkg_version@|' include/builddefs.in
		sed -i -e "/SUBDIRS/s|man2||" man/Makefile
		cd -
	fi

	cd $build
	./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make -j1 tests root-tests
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install install-dev install-lib
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	chmod -v 755 /usr/lib/libattr.so
	mv -v /usr/lib/libattr.so.* /lib
	ln -sfv /lib/$(readlink /usr/lib/libattr.so) /usr/lib/libattr.so
	cd -
}

function make_system_acl()
{
	app=acl-2.2.52
	tar=$SOURCE_TAR/$app.src.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		sed -i -e 's|/@pkg_name@|&-@pkg_version@|' include/builddefs.in
		sed -i "s:| sed.*::g" test/{sbits-restore,cp,misc}.test
		sed -i -e "/TABS-1;/a if (x > (TABS-1)) x = (TABS-1);" libacl/__acl_to_any_text.c
		cd -
	fi

	cd $build
	./configure --prefix=/usr --libexecdir=/usr/lib
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install install-dev install-lib
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	chmod -v 755 /usr/lib/libacl.so
	mv -v /usr/lib/libacl.so.* /lib
	ln -sfv /lib/$(readlink /usr/lib/libacl.so) /usr/lib/libacl.so
	cd -
}

function make_system_libcap()
{
	app=libcap-2.24
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make RAISE_SETFCAP=no prefix=/usr install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	chmod -v 755 /usr/lib/libcap.so
	mv -v /usr/lib/libcap.so.* /lib
	ln -sfv /lib/$(readlink /usr/lib/libcap.so) /usr/lib/libcap.so
	cd -
}

function make_system_sed()
{
	app=sed-4.2.2
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr --bindir=/bin --htmldir=/usr/share/doc/sed-4.2.2
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make html
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make -C doc install-html
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_system_shadow()
{
	app=shadow-4.2.1
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		sed -i 's/groups$(EXEEXT) //' src/Makefile.in
		find man -name Makefile.in -exec sed -i 's/groups\.1 / /' {} \;
		sed -i -e 's@#ENCRYPT_METHOD DES@ENCRYPT_METHOD SHA512@' \
		       -e 's@/var/spool/mail@/var/mail@' etc/login.defs
		sed -i 's/1000/999/' etc/useradd
		cd -
	fi

	cd $build
	./configure --sysconfdir=/etc --with-group-name-max-length=32
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
	mv -v /usr/bin/passwd /bin
	# Configure shadow
	pwconv
	grpconv
	#passwd root
	cd -
}

function make_system_psmisc()
{
	app=psmisc-22.21
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr
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
	mv -v /usr/bin/fuser   /bin
	mv -v /usr/bin/killall /bin
	cd -
}

function make_system_procpsng()
{
	app=procps-ng-3.3.10
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr                            \
		    --exec-prefix=                           \
		    --libdir=/usr/lib                        \
		    --docdir=/usr/share/doc/procps-ng-3.3.10 \
		    --disable-static                         \
		    --disable-kill
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		sed -i -r 's|(pmap_initname)\\\$|\1|' testsuite/pmap.test/pmap.exp
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	mv -v /usr/bin/pidof /bin
	mv -v /usr/lib/libprocps.so.* /lib
	ln -sfv /lib/$(readlink /usr/lib/libprocps.so) /usr/lib/libprocps.so
	cd -
}

function make_system_e2fsprogs()
{
	app=e2fsprogs-1.42.12
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app/build

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		sed -e '/int.*old_desc_blocks/s/int/blk64_t/' \
		    -e '/if (old_desc_blocks/s/super->s_first_meta_bg/desc_blocks/' \
		    -i lib/ext2fs/closefs.c
		cd -
	fi

	if [ ! -d $build ]; then
		mkdir -v $build
	fi

	cd $build
	LIBS=-L/tools/lib                    \
	CFLAGS=-I/tools/include              \
	PKG_CONFIG_PATH=/tools/lib/pkgconfig \
	../configure --prefix=/usr           \
		     --bindir=/bin           \
		     --with-root-prefix=""   \
		     --enable-elf-shlibs     \
		     --disable-libblkid      \
		     --disable-libuuid       \
		     --disable-uuidd         \
		     --disable-fsck
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		ln -sfv /tools/lib/lib{blk,uu}id.so.1 lib
		make LD_LIBRARY_PATH=/tools/lib check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make install-libs
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	chmod -v u+w /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
	# doc
	gunzip -v /usr/share/info/libext2fs.info.gz
	install-info --dir-file=/usr/share/info/dir /usr/share/info/libext2fs.info
	makeinfo -o doc/com_err.info ../lib/et/com_err.texinfo
	install -v -m644 doc/com_err.info /usr/share/info
	install-info --dir-file=/usr/share/info/dir /usr/share/info/com_err.info
	cd -
}

function make_system_coreutils()
{
	app=coreutils-8.23
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		patch -Np1 -i $SOURCE_TAR/coreutils-8.23-i18n-1.patch
		touch Makefile.in
		cd -
	fi

	cd $build
	FORCE_UNSAFE_CONFIGURE=1 ./configure \
		    --prefix=/usr            \
		    --enable-no-install-program=kill,uptime
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make NON_ROOT_USERNAME=nobody check-root
		if [ $? != 0 ]; then
			echo fail; exit
		fi
		# Temp user nobody test
		echo "dummy:x:1000:nobody" >> /etc/group
		chown -Rv nobody .
		su nobody -s /bin/bash -c "PATH=$PATH make RUN_EXPENSIVE_TESTS=yes check"
		sed -i '/dummy/d' /etc/group
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	# FHS
	mv -v /usr/bin/{cat,chgrp,chmod,chown,cp,date,dd,df,echo} /bin
	mv -v /usr/bin/{false,ln,ls,mkdir,mknod,mv,pwd,rm} /bin
	mv -v /usr/bin/{rmdir,stty,sync,true,uname} /bin
	mv -v /usr/bin/chroot /usr/sbin
	mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
	sed -i s/\"1\"/\"8\"/1 /usr/share/man/man8/chroot.8
	# BLFS
	mv -v /usr/bin/{head,sleep,nice,test,[} /bin
	cd -
}

function make_system_iana()
{
	app=iana-etc-2.30
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
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

function make_system_m4()
{
	app=m4-1.4.17
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
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

function make_system_flex()
{
	app=flex-2.5.39
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		sed -i -e '/test-bison/d' tests/Makefile.in
		cd -
	fi

	cd $build
	./configure --prefix=/usr --docdir=/usr/share/doc/flex-2.5.39
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	ln -sv flex /usr/bin/lex
	cd -
}

function make_system_bison()
{
	app=bison-3.0.4
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.0.4
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
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

function make_system_grep()
{
	app=grep-2.21
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		sed -i -e '/tp++/a  if (ep <= tp) break;' src/kwset.c
		cd -
	fi

	cd $build
	./configure --prefix=/usr --bindir=/bin
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
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

function make_system_readline()
{
	app=readline-6.3
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		patch -Np1 -i $SOURCE_TAR/readline-6.3-upstream_fixes-3.patch
		sed -i '/MV.*old/d' Makefile.in
		sed -i '/{OLDSUFF}/c:' support/shlib-install
		cd -
	fi

	cd $build
	./configure --prefix=/usr --docdir=/usr/share/doc/readline-6.3
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make SHLIB_LIBS=-lncurses
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make SHLIB_LIBS=-lncurses install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	#
	mv -v /usr/lib/lib{readline,history}.so.* /lib
	ln -sfv /lib/$(readlink /usr/lib/libreadline.so) /usr/lib/libreadline.so
	ln -sfv /lib/$(readlink /usr/lib/libhistory.so ) /usr/lib/libhistory.so
	install -v -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-6.3
	cd -
}

function make_system_bash()
{
	app=bash-4.3.30
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		patch -Np1 -i $SOURCE_TAR/bash-4.3.30-upstream_fixes-1.patch
		cd -
	fi

	cd $build
	./configure --prefix=/usr                       \
		    --bindir=/bin                       \
		    --docdir=/usr/share/doc/bash-4.3.30 \
		    --without-bash-malloc               \
		    --with-installed-readline
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		chown -Rv nobody .
		su nobody -s /bin/bash -c "PATH=$PATH make $MAKE_FLAGS tests"
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	#exec /bin/bash --login +h
	cd -
}

function make_system_bc()
{
	app=bc-1.06.95
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		patch -Np1 -i $SOURCE_TAR/bc-1.06.95-memory_leak-1.patch
		cd -
	fi

	cd $build
	./configure --prefix=/usr           \
		    --with-readline         \
		    --mandir=/usr/share/man \
		    --infodir=/usr/share/info
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	echo "quit" | ./bc/bc -l Test/checklib.b
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_system_libtool()
{
	app=libtool-2.4.6
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make -i $MAKE_FLAGS check
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

function make_system_gdbm()
{
	app=gdbm-1.11
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr --enable-libgdbm-compat
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
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

function make_system_expat()
{
	app=expat-2.1.0
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	install -v -dm755 /usr/share/doc/expat-2.1.0
	install -v -m644 doc/*.{html,png,css} /usr/share/doc/expat-2.1.0
	cd -
}

function make_system_inetutils()
{
	app=inetutils-1.9.2
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		echo '#define PATH_PROCNET_DEV "/proc/net/dev"' >> ifconfig/system/linux.h 
		cd -
	fi

	cd $build
	./configure --prefix=/usr        \
		    --localstatedir=/var \
		    --disable-logger     \
		    --disable-whois      \
		    --disable-servers
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	mv -v /usr/bin/{hostname,ping,ping6,traceroute} /bin
	mv -v /usr/bin/ifconfig /sbin
	cd -
}

function make_system_perl()
{
	app=perl-5.20.2
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	echo "127.0.0.1 localhost $(hostname)" > /etc/hosts
	export BUILD_ZLIB=False
	export BUILD_BZIP2=0

	cd $build
	sh Configure -des -Dprefix=/usr                 \
			  -Dvendorprefix=/usr           \
			  -Dman1dir=/usr/share/man/man1 \
			  -Dman3dir=/usr/share/man/man3 \
			  -Dpager="/usr/bin/less -isR"  \
			  -Duseshrplib
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make $MAKE_FLAGS
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make -k $MAKE_FLAGS test
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	unset BUILD_ZLIB BUILD_BZIP2
	cd -
}

function make_system_xmlparser()
{
	app=XML-Parser-2.44
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	perl Makefile.PL
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make test
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

function make_system_autoconf()
{
	app=autoconf-2.69
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make -i $MAKE_FLAGS check  # use very long time
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

function make_system_automake()
{
	app=automake-1.15
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.15
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		sed -i "s:./configure:LEXLIB=/usr/lib/libfl.a &:" t/lex-{clean,depend}-cxx.sh
		make -i $MAKE_FLAGS check # use very long time
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

function make_system_diffutils()
{
	app=diffutils-3.3
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		sed -i 's:= @mkdir_p@:= /bin/mkdir -p:' po/Makefile.in.in
		cd -
	fi

	cd $build
	./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
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

function make_system_gawk()
{
	app=gawk-4.1.1
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	mkdir -v /usr/share/doc/gawk-4.1.1
	cp -v doc/{awkforai.txt,*.{eps,pdf,jpg}} /usr/share/doc/gawk-4.1.1
	cd -
}

function make_system_findutils()
{
	app=findutils-4.4.2
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr --localstatedir=/var/lib/locate
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	mv -v /usr/bin/find /bin
	sed -i 's|find:=${BINDIR}|find:=/bin|' /usr/bin/updatedb
	cd -
}

function make_system_gettext()
{
	app=gettext-0.19.4
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr --docdir=/usr/share/doc/gettext-0.19.4
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
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

function make_system_intltool()
{
	app=intltool-0.50.2
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	install -v -Dm644 doc/I18N-HOWTO /usr/share/doc/intltool-0.50.2/I18N-HOWTO
	cd -
}

function make_system_gperf()
{
	app=gperf-3.0.4
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.0.4
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
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

function make_system_groff()
{
	app=groff-1.22.3
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	PAGE=A4 ./configure --prefix=/usr
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

function make_system_xz()
{
	app=xz-5.2.0
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr --docdir=/usr/share/doc/xz-5.2.0
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	mv -v /usr/bin/{lzma,unlzma,lzcat,xz,unxz,xzcat} /bin
	mv -v /usr/lib/liblzma.so.* /lib
	ln -svf /lib/$(readlink /usr/lib/liblzma.so) /usr/lib/liblzma.so
	cd -
}

function make_system_grub()
{
	app=grub-2.02~beta2
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr          \
		    --sbindir=/sbin        \
		    --sysconfdir=/etc      \
		    --disable-grub-emu-usb \
		    --disable-efiemu       \
		    --disable-werror
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

function make_system_less()
{
	app=less-458
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr --sysconfdir=/etc
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

function make_system_gzip()
{
	app=gzip-1.6
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr --bindir=/bin
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	mv -v /bin/{gzexe,uncompress,zcmp,zdiff,zegrep} /usr/bin
	mv -v /bin/{zfgrep,zforce,zgrep,zless,zmore,znew} /usr/bin
	cd -
}

function make_system_iproute2()
{
	app=iproute2-3.19.0
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		sed -i '/^TARGETS/s@arpd@@g' misc/Makefile
		sed -i /ARPD/d Makefile
		sed -i 's/arpd.8//' man/man8/Makefile
		cd -
	fi

	cd $build
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make DOCDIR=/usr/share/doc/iproute2-3.19.0 install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_system_kbd()
{
	app=kbd-2.0.2
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		patch -Np1 -i $SOURCE_TAR/kbd-2.0.2-backspace-1.patch
		sed -i 's/\(RESIZECONS_PROGS=\)yes/\1no/g' configure
		sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
		cd -
	fi

	cd $build
	PKG_CONFIG_PATH=/tools/lib/pkgconfig ./configure --prefix=/usr --disable-vlock
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	mkdir -v /usr/share/doc/kbd-2.0.2
	cp -R -v docs/doc/* /usr/share/doc/kbd-2.0.2
	cd -
}

function make_system_kmod()
{
	app=kmod-19
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr          \
		    --bindir=/bin          \
		    --sysconfdir=/etc      \
		    --with-rootlibdir=/lib \
		    --with-xz              
		    #--with-zlib            
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	for target in depmod insmod lsmod modinfo modprobe rmmod; do
		ln -sv ../bin/kmod /sbin/$target
	done
	ln -sv kmod /bin/lsmod
	cd -
}

function make_system_libpipeline()
{
	app=libpipeline-1.4.0
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	PKG_CONFIG_PATH=/tools/lib/pkgconfig ./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
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

function make_system_make()
{
	app=make-4.1
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
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

function make_system_patch()
{
	app=patch-2.7.4
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
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

function make_system_utillinux()
{
	app=util-linux-2.26
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	# FHS
	if [ ! -d /var/lib/hwclock ]; then
		mkdir -vp /var/lib/hwclock
	fi

	cd $build
	./configure ADJTIME_PATH=/var/lib/hwclock/adjtime   \
		    --docdir=/usr/share/doc/util-linux-2.26 \
		    --disable-chfn-chsh  \
		    --disable-login      \
		    --disable-nologin    \
		    --disable-su         \
		    --disable-setpriv    \
		    --disable-runuser    \
		    --disable-pylibmount \
		    --without-python
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		# Test
		chown -Rv nobody .
		su nobody -s /bin/bash -c "PATH=$PATH make -k check"
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_system_systemd()
{
	app=systemd-219
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		cat > config.cache << "EOF"
KILL=/bin/kill
HAVE_BLKID=1
BLKID_LIBS="-lblkid"
BLKID_CFLAGS="-I/tools/include/blkid"
HAVE_LIBMOUNT=1
MOUNT_LIBS="-lmount"
MOUNT_CFLAGS="-I/tools/include/libmount"
cc_cv_CFLAGS__flto=no
EOF
		sed -i "s:blkid/::" $（grep -rl "blkid/blkid.h"）
		patch -Np1 -i $SOURCE_TAR/systemd-219-compat-1.patch
		sed -i "s:test/udev-test.pl ::g" Makefile.in
		cd -
	fi

	cd $build
	./configure --prefix=/usr                                           \
		    --sysconfdir=/etc                                       \
		    --localstatedir=/var                                    \
		    --config-cache                                          \
		    --with-rootprefix=                                      \
		    --with-rootlibdir=/lib                                  \
		    --enable-split-usr                                      \
		    --disable-gudev                                         \
		    --disable-firstboot                                     \
		    --disable-ldconfig                                      \
		    --disable-sysusers                                      \
		    --without-python                                        \
		    --docdir=/usr/share/doc/systemd-219                     \
		    --with-dbuspolicydir=/etc/dbus-1/system.d               \
		    --with-dbussessionservicedir=/usr/share/dbus-1/services \
		    --with-dbussystemservicedir=/usr/share/dbus-1/system-services
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make LIBRARY_PATH=/tools/lib
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make LD_LIBRARY_PATH=/tools/lib install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	mv -v /usr/lib/libnss_{myhostname,mymachines,resolve}.so.2 /lib
	rm -rfv /usr/lib/rpm
	for tool in runlevel reboot shutdown poweroff halt telinit; do
		ln -sfv ../bin/systemctl /sbin/${tool}
	done
	ln -sfv ../lib/systemd/systemd /sbin/init
	sed -i "s:0775 root lock:0755 root root:g" /usr/lib/tmpfiles.d/legacy.conf
	sed -i "/pam.d/d" /usr/lib/tmpfiles.d/etc.conf
	# Create systemd-journald's /etc/machine-id
	systemd-machine-id-setup
	# Test
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		sed -i "s:minix:ext4:g" src/test/test-path-util.c
		make LD_LIBRARY_PATH=/tools/lib -k check
	fi
	cd -
}

function make_system_dbus()
{
	app=dbus-1.8.16
	tar=$SOURCE_TAR/$app.tar.gz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr                       \
		    --sysconfdir=/etc                   \
		    --localstatedir=/var                \
		    --docdir=/usr/share/doc/dbus-1.8.16 \
		    --with-console-auth-dir=/run/console
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
	mv -v /usr/lib/libdbus-1.so.* /lib
	ln -sfv /lib/$(readlink /usr/lib/libdbus-1.so) /usr/lib/libdbus-1.so
	ln -sfv /etc/machine-id /var/lib/dbus
	cd -
}

function make_system_mandb()
{
	app=man-db-2.7.1
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr                        \
		    --docdir=/usr/share/doc/man-db-2.7.1 \
		    --sysconfdir=/etc                    \
		    --disable-setuid                     \
		    --with-browser=/usr/bin/lynx         \
		    --with-vgrind=/usr/bin/vgrind        \
		    --with-grap=/usr/bin/grap
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	sed -i "s:man root:root root:g" /usr/lib/tmpfiles.d/man-db.conf
	cd -
}

function make_system_tar()
{
	app=tar-1.28
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	FORCE_UNSAFE_CONFIGURE=1  \
	./configure --prefix=/usr \
		    --bindir=/bin
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make -C doc install-html docdir=/usr/share/doc/tar-1.28
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cd -
}

function make_system_texinfo()
{
	app=texinfo-5.2
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make TEXMF=/usr/share/texmf install-tex
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	pushd /usr/share/info
	rm -v dir
	for f in *
		do install-info $f dir 2>/dev/null
	done
	popd
	cd -
}

function make_system_vim()
{
	app=vim74
	tar=$SOURCE_TAR/vim-7.4.tar.bz2
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
		cd $src
		echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
		cd -
	fi

	cd $build
	./configure --prefix=/usr
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_SKIP_CHECK" != "yes" ]; then
		make -j1 test
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	ln -sv vim /usr/bin/vi
	for L in /usr/share/man/{,*/}man1/vim.1; do
		ln -sv vim.1 $(dirname $L)/vi.1
	done
	ln -sv ../vim/vim74/doc /usr/share/doc/vim-7.4
	# Configure vim
	cat > /etc/vimrc << "EOF"
" Begin /etc/vimrc

set nocompatible
set backspace=2
syntax on
if (&term == "iterm") || (&term == "putty")
  set background=dark
endif

" End /etc/vimrc
EOF
	#vim -c ':options'
	cd -
}

function config_system_network()
{
	# Static IP
	cat > /etc/systemd/network/10-static-eth0.network << "EOF"
[Match]
Name=eth0

[Network]
Address=192.168.5.1/24
Gateway=192.168.5.1
DNS=192.168.0.1
EOF

	# DHCP
	cat > /etc/systemd/network/10-dhcp-eth0.network << "EOF"
[Match]
Name=eth0

[Network]
DHCP=yes
EOF

	# DNS
	cat > /etc/resolv.conf << "EOF"
# Begin /etc/resolv.conf

#domain <Your Domain Name>
#nameserver <IP address of your primary nameserver>
#nameserver <IP address of your secondary nameserver>
nameserver 8.8.8.8

# End /etc/resolv.conf
EOF
	#ln -sfv /run/systemd/resolve/resolv.conf /etc/resolv.conf

	# hostname
	echo "ocean" > /etc/hostname

	#
	cat > /etc/hosts << "EOF"
# Begin /etc/hosts (network card version)

# Format: IP_address myhost.example.org aliases

127.0.0.1 localhost
::1       localhost
#<192.168.0.2> <HOSTNAME.example.org> [alias1] [alias2] ...

# End /etc/hosts (network card version)
EOF

<< "EOF"
# Begin /etc/hosts (no network card version)

127.0.0.1 <HOSTNAME.example.org> <HOSTNAME> localhost
::1       localhost

# End /etc/hosts (no network card version)
EOF

}

function config_system()
{

	cat > /etc/fstab << "EOF"
# Begin /etc/fstab

# 文件系统  挂载点  文件类型     挂载选项             dump  fsck
#                                                              order

/dev/sda1     /            ext4     defaults            1     1
/dev/sda5     swap         swap     pri=1               0     0

# End /etc/fstab
EOF
}

function make_system_kernel()
{
	app=linux-3.19
	tar=$SOURCE_TAR/$app.tar.xz
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	make mrproper
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make defconfig
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make menuconfig
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make modules_install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	cp -v arch/$(uname -m)/boot/bzImage /boot/vmlinuz-3.19-lfs-7.7-systemd
	cp -v System.map /boot/System.map-3.19
	cp -v .config /boot/config-3.19
	cp -v .config /qmd/kernel_config-3.19
	install -d /usr/share/doc/linux-3.19
	cp -r Documentation/* /usr/share/doc/linux-3.19
	cd -
}

function config_system_grub()
{
	#grub-install /dev/sda
	cat > /boot/grub/grub.cfg << "EOF"
# Begin /boot/grub/grub.cfg
set default=0
set timeout=5

insmod ext4
set root=(hd0,1)

menuentry "GNU/Linux, Linux 3.19-lfs-7.7-systemd" {
        linux   /boot/vmlinuz-3.19-lfs-7.7-systemd root=/dev/sda1 rw
}
EOF
}

function make_system()
{
	if [ ! -d /qmd ]; then
		echo "You must chroot first"
		exit
	fi

	if [ "$1" == "clean" ]; then
		make_system_clean
		exit
	fi

<<EOF
	make_system_kernel_headers
	make_system_manpages
	make_system_glibc
	make_system_toolchain
	make_system_zlib
	make_system_file
	make_system_binutils
	make_system_gmp
	make_system_mpfr
	make_system_mpc
	make_system_gcc
	make_system_bzip2
	make_system_pkgconfig
	make_system_ncurses
	make_system_attr
	make_system_acl
	make_system_libcap
	make_system_sed
	make_system_shadow
	make_system_psmisc
	make_system_procpsng
	make_system_e2fsprogs
	make_system_coreutils
	make_system_iana
	make_system_m4
	make_system_flex
	make_system_bison
	make_system_grep
	make_system_readline
	make_system_bash
	make_system_bc
	make_system_libtool
	make_system_gdbm
	make_system_expat
	make_system_inetutils
	make_system_perl
	make_system_xmlparser
	make_system_autoconf
	make_system_automake
	make_system_diffutils
	make_system_gawk
	make_system_findutils
	make_system_gettext
	make_system_intltool
	make_system_gperf
	make_system_groff
	make_system_xz
	make_system_grub
	make_system_less
	make_system_gzip
	make_system_iproute2
	make_system_kbd
	make_system_kmod
	make_system_libpipeline
	make_system_make
	make_system_patch
	make_system_utillinux
	make_system_systemd
	make_system_dbus
	make_system_mandb
	make_system_tar
	make_system_texinfo
	make_system_vim
EOF
	#config_system_network
	#config_system
	#make_system_kernel
	config_system_grub
}

function create_virtualbox_vmdk()
{
	if [ -d /qmd ]; then
		echo "You must be on host"
		exit
	fi

	sudo VBoxManage internalcommands createrawvmdk -filename /home/lfs/mydisk.vmdk -rawdisk /dev/sda
}

function main()
{
	case "$1" in
	"disk")
		create_disk
		;;
	"user")
		create_user
		;;
	"srcs")
		create_srcs
		;;
	"tools")
		make_tools $2
		;;
	"rootfs")
		make_rootfs $2
		;;
	"chroot")
		change_root $2
		;;
	"system")
		make_system $2
		;;
	"clean")
		make_clean
		;;
	*)
		echo "Invalid args"
		;;
	esac
}

main $1 $2 $3
