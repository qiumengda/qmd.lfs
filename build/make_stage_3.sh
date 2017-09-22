#!/bin/sh

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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	if [ "$MAKE_CHECK" == "yes" ]; then
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
	filepath=/etc/fstab
	echo "Create mount configuration file $filepath"
	cat > $filepath << "EOF"
# Begin /etc/fstab

# <file system> <mount point>   <type>  <options>       <dump>  <pass>
#                                                              order

/dev/sda1     /            ext4     defaults            1     1
/dev/sda5     swap         swap     pri=1               0     0

# End /etc/fstab
EOF

	filepath=/etc/passwd
	echo "Create $filepath"
	cat > $filepath << EOF
root::0:0:root:/root:/bin/bash
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
EOF

	filepath=/etc/group
	echo "Create $filepath"
	cat > $filepath << EOF
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
EOF
	# Configure shadow
	pwconv
	grpconv
	# Passwd root
	passwd root

	filepath=/etc/profile
	echo "Create $filepath"
	cat > $filepath << "EOF"
# Begin /etc/profile

PS1='\u@\h:\W\$ '
alias ls='ls --color=auto'
alias grep='grep --color=auto'

# End /etc/profile
EOF

	filepath=/etc/vimrc
	echo "Create $filepath"
	cat >> $filepath << "EOF"
syntax on  
set history=100  
set encoding=utf-8  
set nocompatible  
set number  
set hlsearch  
set cindent  
set showmatch  
set cursorline  
set ruler  
set laststatus=2  
set cmdheight=1  
set statusline=\ %<%F[%1*%M%*%n%R%H]%=\ %y\ %0(%{&fileformat}\ %{&encoding}\ %c:%l/%L%)\
EOF

	config_system_network
	config_system_grub
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
	#make menuconfig
	#cp /build/kernel_config-3.19 .config
	cp /build/kernel_config-3.19.x .config
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make $MAKE_FLAGS
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
	#cp -v .config /build/kernel_config-3.19
	if [ "$MAKE_DOC" == "yes" ]; then
		install -d /usr/share/doc/linux-3.19
		cp -r Documentation/* /usr/share/doc/linux-3.19
	fi
	cd -
}

function make_system_cpio()
{
	app=cpio-2.12
	tar=$SOURCE_TAR/$app.tar.bz2
	src=$SYSTEM_SRC/$app
	build=$SYSTEM_SRC/$app

	if [ ! -d $src ]; then
		tar -xvf $tar -C $SYSTEM_SRC
	fi

	cd $build
	./configure --prefix=/usr \
		--bindir=/bin \
		--enable-mt   \
		--with-rmt=/usr/libexec/rmt &&
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	make
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_CHECK" == "yes" ]; then
		make check
		if [ $? != 0 ]; then
			echo fail; exit
		fi
	fi
	if [ "$MAKE_DOC" == "yes" ]; then
		makeinfo --html            -o doc/html      doc/cpio.texi &&
		makeinfo --html --no-split -o doc/cpio.html doc/cpio.texi &&
		makeinfo --plaintext       -o doc/cpio.txt  doc/cpio.texi
		# texlive-20160523b
		#make -C doc pdf &&
		#make -C doc ps
	fi
	make install
	if [ $? != 0 ]; then
		echo fail; exit
	fi
	if [ "$MAKE_DOC" == "yes" ]; then
		install -v -m755 -d /usr/share/doc/cpio-2.12/html &&
		install -v -m644    doc/html/* \
				    /usr/share/doc/cpio-2.12/html &&
		install -v -m644    doc/cpio.{html,txt} \
				    /usr/share/doc/cpio-2.12
		install -v -m644    doc/cpio.{pdf,ps,dvi} \
				    /usr/share/doc/cpio-2.12
	fi
	cd -
}

function make_system_initrd()
{
	make_system_cpio

	cat > /sbin/mkinitramfs << "EOF"
#!/bin/bash
# This file based in part on the mkinitramfs script for the LFS LiveCD
# written by Alexander E. Patrakov and Jeremy Huntwork.

copy()
{
	local file

	if [ "$2" == "lib" ]; then
		file=$(PATH=/lib:/usr/lib type -p $1)
	else
		file=$(type -p $1)
	fi

  if [ -n $file ] ; then
    cp $file $WDIR/$2
  else
    echo "Missing required file: $1 for directory $2"
    rm -rf $WDIR
    exit 1
  fi
}

if [ -z $1 ] ; then
  INITRAMFS_FILE=initrd.img-no-kmods
else
  KERNEL_VERSION=$1
  INITRAMFS_FILE=initrd.img-$KERNEL_VERSION
fi

if [ -n "$KERNEL_VERSION" ] && [ ! -d "/lib/modules/$1" ] ; then
  echo "No modules directory named $1"
  exit 1
fi

printf "Creating $INITRAMFS_FILE... "

binfiles="sh cat cp dd killall ls mkdir mknod mount "
binfiles="$binfiles umount sed sleep ln rm uname"

# Systemd installs udevadm in /bin. Other udev implementations have it in /sbin
if [ -x /bin/udevadm ] ; then binfiles="$binfiles udevadm"; fi

sbinfiles="modprobe blkid switch_root"

#Optional files and locations
for f in mdadm mdmon udevd udevadm; do
  if [ -x /sbin/$f ] ; then sbinfiles="$sbinfiles $f"; fi
done

unsorted=$(mktemp /tmp/unsorted.XXXXXXXXXX)

DATADIR=/usr/share/mkinitramfs
INITIN=init.in

# Create a temporary working directory
WDIR=$(mktemp -d /tmp/initrd-work.XXXXXXXXXX)

# Create base directory structure
mkdir -p $WDIR/{bin,dev,lib/firmware,run,sbin,sys,proc}
mkdir -p $WDIR/etc/{modprobe.d,udev/rules.d}
touch $WDIR/etc/modprobe.d/modprobe.conf
ln -s lib $WDIR/lib64

# Create necessary device nodes
mknod -m 640 $WDIR/dev/console c 5 1
mknod -m 664 $WDIR/dev/null    c 1 3

# Install the udev configuration files
if [ -f /etc/udev/udev.conf ]; then
  cp /etc/udev/udev.conf $WDIR/etc/udev/udev.conf
fi

for file in $(find /etc/udev/rules.d/ -type f) ; do
  cp $file $WDIR/etc/udev/rules.d
done

# Install any firmware present
cp -a /lib/firmware $WDIR/lib

# Copy the RAID configuration file if present
if [ -f /etc/mdadm.conf ] ; then
  cp /etc/mdadm.conf $WDIR/etc
fi

# Install the init file
install -m0755 $DATADIR/$INITIN $WDIR/init

if [  -n "$KERNEL_VERSION" ] ; then
  if [ -x /bin/kmod ] ; then
    binfiles="$binfiles kmod"
  else
    binfiles="$binfiles lsmod"
    sbinfiles="$sbinfiles insmod"
  fi
fi

# Install basic binaries
for f in $binfiles ; do
  ldd /bin/$f | sed "s/\t//" | cut -d " " -f1 >> $unsorted
  copy $f bin
done

# Add lvm if present
if [ -x /sbin/lvm ] ; then sbinfiles="$sbinfiles lvm dmsetup"; fi

for f in $sbinfiles ; do
  ldd /sbin/$f | sed "s/\t//" | cut -d " " -f1 >> $unsorted
  copy $f sbin
done

# Add udevd libraries if not in /sbin
if [ -x /lib/udev/udevd ] ; then
  ldd /lib/udev/udevd | sed "s/\t//" | cut -d " " -f1 >> $unsorted
elif [ -x /lib/systemd/systemd-udevd ] ; then
  ldd /lib/systemd/systemd-udevd | sed "s/\t//" | cut -d " " -f1 >> $unsorted
fi

# Add module symlinks if appropriate
if [ -n "$KERNEL_VERSION" ] && [ -x /bin/kmod ] ; then
  ln -s kmod $WDIR/bin/lsmod
  ln -s kmod $WDIR/bin/insmod
fi

# Add lvm symlinks if appropriate
# Also copy the lvm.conf file
if  [ -x /sbin/lvm ] ; then
  ln -s lvm $WDIR/sbin/lvchange
  ln -s lvm $WDIR/sbin/lvrename
  ln -s lvm $WDIR/sbin/lvextend
  ln -s lvm $WDIR/sbin/lvcreate
  ln -s lvm $WDIR/sbin/lvdisplay
  ln -s lvm $WDIR/sbin/lvscan

  ln -s lvm $WDIR/sbin/pvchange
  ln -s lvm $WDIR/sbin/pvck
  ln -s lvm $WDIR/sbin/pvcreate
  ln -s lvm $WDIR/sbin/pvdisplay
  ln -s lvm $WDIR/sbin/pvscan

  ln -s lvm $WDIR/sbin/vgchange
  ln -s lvm $WDIR/sbin/vgcreate
  ln -s lvm $WDIR/sbin/vgscan
  ln -s lvm $WDIR/sbin/vgrename
  ln -s lvm $WDIR/sbin/vgck
  # Conf file(s)
  cp -a /etc/lvm $WDIR/etc
fi

# Install libraries
sort $unsorted | uniq | while read library ; do
  if [ "$library" == "linux-vdso.so.1" ] ||
     [ "$library" == "linux-gate.so.1" ]; then
    continue
  fi

  copy $library lib
done

if [ -d /lib/udev ]; then
  cp -a /lib/udev $WDIR/lib
fi
if [ -d /lib/systemd ]; then
  cp -a /lib/systemd $WDIR/lib
fi

# Install the kernel modules if requested
if [ -n "$KERNEL_VERSION" ]; then
  find                                                                        \
     /lib/modules/$KERNEL_VERSION/kernel/{crypto,fs,lib}                      \
     /lib/modules/$KERNEL_VERSION/kernel/drivers/{block,ata,md,firewire}      \
     /lib/modules/$KERNEL_VERSION/kernel/drivers/{scsi,message,pcmcia,virtio} \
     /lib/modules/$KERNEL_VERSION/kernel/drivers/usb/{host,storage}           \
     -type f 2> /dev/null | cpio --make-directories -p --quiet $WDIR

  cp /lib/modules/$KERNEL_VERSION/modules.{builtin,order}                     \
            $WDIR/lib/modules/$KERNEL_VERSION

  depmod -b $WDIR $KERNEL_VERSION
fi

( cd $WDIR ; find . | cpio -o -H newc --quiet | gzip -9 ) > $INITRAMFS_FILE

# Remove the temporary directory and file
rm -rf $WDIR $unsorted
printf "done.\n"

EOF

	chmod 0755 /sbin/mkinitramfs

mkdir -p /usr/share/mkinitramfs &&
cat > /usr/share/mkinitramfs/init.in << "EOF"
#!/bin/sh

PATH=/bin:/usr/bin:/sbin:/usr/sbin
export PATH

problem()
{
   printf "Encountered a problem!\n\nDropping you to a shell.\n\n"
   sh
}

no_device()
{
   printf "The device %s, which is supposed to contain the\n" $1
   printf "root file system, does not exist.\n"
   printf "Please fix this problem and exit this shell.\n\n"
}

no_mount()
{
   printf "Could not mount device %s\n" $1
   printf "Sleeping forever. Please reboot and fix the kernel command line.\n\n"
   printf "Maybe the device is formatted with an unsupported file system?\n\n"
   printf "Or maybe filesystem type autodetection went wrong, in which case\n"
   printf "you should add the rootfstype=... parameter to the kernel command line.\n\n"
   printf "Available partitions:\n"
}

do_mount_root()
{
   mkdir /.root
   [ -n "$rootflags" ] && rootflags="$rootflags,"
   rootflags="$rootflags$ro"

   case "$root" in
      /dev/* ) device=$root ;;
      UUID=* ) eval $root; device="/dev/disk/by-uuid/$UUID"  ;;
      LABEL=*) eval $root; device="/dev/disk/by-label/$LABEL" ;;
      ""     ) echo "No root device specified." ; problem    ;;
   esac

   while [ ! -b "$device" ] ; do
       no_device $device
       problem
   done

   if ! mount -n -t "$rootfstype" -o "$rootflags" "$device" /.root ; then
       no_mount $device
       cat /proc/partitions
       while true ; do sleep 10000 ; done
   else
       echo "Successfully mounted device $root"
   fi
}

init=/sbin/init
root=
rootdelay=
rootfstype=auto
ro="ro"
rootflags=
device=

mount -n -t devtmpfs devtmpfs /dev
mount -n -t proc     proc     /proc
mount -n -t sysfs    sysfs    /sys
mount -n -t tmpfs    tmpfs    /run

read -r cmdline < /proc/cmdline

for param in $cmdline ; do
  case $param in
    init=*      ) init=${param#init=}             ;;
    root=*      ) root=${param#root=}             ;;
    rootdelay=* ) rootdelay=${param#rootdelay=}   ;;
    rootfstype=*) rootfstype=${param#rootfstype=} ;;
    rootflags=* ) rootflags=${param#rootflags=}   ;;
    ro          ) ro="ro"                         ;;
    rw          ) ro="rw"                         ;;
  esac
done

# udevd location depends on version
if [ -x /sbin/udevd ]; then
  UDEVD=/sbin/udevd
elif [ -x /lib/udev/udevd ]; then
  UDEVD=/lib/udev/udevd
elif [ -x /lib/systemd/systemd-udevd ]; then
  UDEVD=/lib/systemd/systemd-udevd
else
  echo "Cannot find udevd nor systemd-udevd"
  problem
fi

${UDEVD} --daemon --resolve-names=never
udevadm trigger
udevadm settle

if [ -f /etc/mdadm.conf ] ; then mdadm -As                       ; fi
if [ -x /sbin/vgchange  ] ; then /sbin/vgchange -a y > /dev/null ; fi
if [ -n "$rootdelay"    ] ; then sleep "$rootdelay"              ; fi

do_mount_root

killall -w ${UDEVD##*/}

exec switch_root /.root "$init" "$@"

EOF


	mkinitramfs 3.19.0
	mv initrd.img-3.19.0 /boot
}

function config_system_grub()
{
	#grub-install /dev/sda
	if [ ! -d /boot/grub/ ]; then
		mkdir -v /boot/grub
	fi

	filepath=/boot/grub/grub.cfg
	echo "Create $filepath"
	cat > $filepath << "EOF"
# Begin /boot/grub/grub.cfg
set default=0
set timeout=5

insmod ext2
set root=(hd0,1)

menuentry "GNU/Linux, Linux 3.19-lfs-7.7-systemd" {
	linux /boot/vmlinuz-3.19-lfs-7.7-systemd root=/dev/sdb1 rw rootdelay=5
	initrd /boot/initrd.img-3.19.0
}
EOF
}

function make_rootfs()
{
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

	make_system_kernel
	make_system_initrd
	config_system
}

function make_rootfs_strip()
{
	echo "system strip"
	#/tools/bin/find /{,usr/}{bin,lib,sbin} -type f -exec /tools/bin/strip --strip-debug '{}' ';'
#	/tools/bin/strip --strip-debug /{,usr/}{bin,lib,sbin}/*
<<EOF
	/tools/bin/find /bin -type f -exec /tools/bin/strip --strip-debug '{}' ';'
	echo 1 ; sleep 1
	/tools/bin/find /lib -type f -exec /tools/bin/strip --strip-debug '{}' ';'
	echo 2 ; sleep 1
	/tools/bin/find /sbin -type f -exec /tools/bin/strip --strip-debug '{}' ';'
	echo 3 ; sleep 1
	/tools/bin/find /usr/bin -type f -exec /tools/bin/strip --strip-debug '{}' ';'
	/tools/bin/find /usr/lib -type f -exec /tools/bin/strip --strip-debug '{}' ';'
	/tools/bin/find /usr/sbin -type f -exec /tools/bin/strip --strip-debug '{}' ';'
	/tools/bin/strip --strip-debug /bin/*
	/tools/bin/strip --strip-debug /lib/*
	/tools/bin/strip --strip-debug /sbin/*
	/tools/bin/strip --strip-debug /usr/bin/*
	/tools/bin/strip --strip-debug /usr/lib/*
	/tools/bin/strip --strip-debug /usr/sbin/*
EOF

	files=$(/tools/bin/find /{,usr/}{bin,lib,sbin})
	#files=$(/tools/bin/find /{,usr/}{bin,sbin})
	for file in $files;
	do
		echo "Check $file"
		if echo "$file" | grep -E "*\.a$|*\.ko$|*\.o$" ; then
			echo "Skip $file"
			continue
		fi
		if /tools/bin/file $file | /tools/bin/grep "not stripped" ; then
			echo "strip $file"
			/tools/bin/strip $file
		else
			echo "Can not strip $(/tools/bin/file $file)"
		fi
	done

<<EOF
	#files=$(/tools/bin/find /{,usr/}lib)
	files=$(/tools/bin/find /lib)
	for file in $files;
	do
		echo "Check $file"
		if echo "$file" | grep -E "*\.a$|*\.ko$|*\.o$" ; then
			echo "Skip $file"
			continue
		fi
		if /tools/bin/file $file | /tools/bin/grep "not stripped" ; then
			echo "strip $file"
			/tools/bin/strip $file
		else
			echo "Can not strip $(/tools/bin/file $file)"
		fi
	done
EOF
}

function make_rootfs_init()
{
        if [ ! -d $SYSTEM_SRC ]; then
                mkdir -v $SYSTEM_SRC
        fi
	
}

function make_rootfs_clean()
{
	rm -vrf $SYSTEM_SRC
}

function main()
{
	if [ -d /build ]; then
		echo  "You must chroot"
		exit
	fi

	case "$1" in
	"clean")
		make_rootfs_clean
		;;
	"strip")
		make_rootfs_strip
		;;
	*)
		make_rootfs_init
		make_rootfs
		;;
	esac
}

main $1
