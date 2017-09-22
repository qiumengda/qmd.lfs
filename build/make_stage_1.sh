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
        sudo groupadd lfs
        sudo useradd -s /bin/bash -g lfs -m -k /dev/null lfs
        sudo passwd lfs

#Use root
<< EOF
        cat > /home/lfs/.bash_profile << EOF
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF

#Use dd as root
<< EOF
        sudo dd of=/home/lfs/.bash_profile << EOF
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF

#Use tee as root
<< EOF
        cat << EOF | sudo tee /home/lfs/.bash_profile 
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF

#Use bash as root
<< EOF
        sudo bash -c "cat << EOF > /home/lfs/.bash_profile
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF"
EOF

#Use bash as root
#<<EOF
        sudo bash -c 'cat > /home/lfs/.bash_profile' << EOF 
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF

        sudo bash -c 'cat > /home/lfs/.bashrc' << EOF
set +h
umask 022
LFS=/mnt/lfs
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/tools/bin:/bin:/usr/bin
export LFS LC_ALL LFS_TGT PATH
alias ls='ls --color=auto'
alias grep='grep --color=auto'
EOF

        #su - lfs
        #source /home/lfs/.bash_profile
        #sudo swapon -v /dev/sdb2
        #sudo chmod -v a+wt $LFS/sources

        #sudo chown -vR $LFS
}

function make_init()
{
        if [ ! -d $SOURCE_TAR ]; then 
                mkdir -v $SOURCE_TAR
                # tar -xvf lfs-packages-7.7-systemd.tar -C $SOURCE_TAR
        fi   

        if [ ! -d $TOOLS_SRC ]; then 
                mkdir -v $TOOLS_SRC
        fi   

        if [ ! -d $SYSTEM_SRC ]; then 
                mkdir -v $SYSTEM_SRC
        fi   

        if [ ! -d $TOOLS_INSTALL ]; then 
                mkdir -v $TOOLS_INSTALL
        fi   

        if [ ! -d $SYSTEM_INSTALL ]; then 
                mkdir -v $SYSTEM_INSTALL
        fi   

        if [ ! -d $SYSTEM_INSTALL/build ]; then 
                mkdir -v $SYSTEM_INSTALL/build
        fi   

        if [ ! -d $SYSTEM_INSTALL/tools ]; then 
                mkdir -v $SYSTEM_INSTALL/tools
        fi   

        if [ ! -L /tools ]; then 
                sudo ln -sv $TOOLS_INSTALL /tools
        fi   

        if [ ! -d /tools/lib ]; then 
                mkdir -v /tools/lib
        fi 

        case $(uname -m) in
        x86_64)
                if [ ! -L /tools/lib64 ]; then
                        ln -sv lib /tools/lib64 
                fi
                ;;
        esac

}

function mount_memfs()
{
        mount_list="$ROOTFS/dev $ROOTFS/dev/pts $ROOTFS/proc $ROOTFS/sys $ROOTFS/run"
        umount_list="$ROOTFS/dev/pts $ROOTFS/dev $ROOTFS/proc $ROOTFS/sys $ROOTFS/run"

        if [ "$1" == "clean" ]; then
                list=$umount_list
        else
                list=$mount_list
        fi

        for dir in $list;
        do
                if [ "$1" == "clean" ]; then
                        if grep -q "$dir" /proc/mounts; then
                                sudo umount -v $dir
                        else
                                printf "%-32s already umounted\n" $dir
                        fi
                        continue
                fi

                if grep -q "$dir" /proc/mounts; then
                        printf "%-32s already mounted\n" $dir
                        continue
                fi

                if [ ! -d $dir ]; then
                        echo "$dir not exists"
                        continue
                fi
 
                case "$dir" in
                "$ROOTFS/dev")
                        sudo mount -v --bind /dev $dir
                        ;;
                "$ROOTFS/dev/pts")
                        sudo mount -vt devpts devpts $dir -o gid=5,mode=620
                        ;;
                "$ROOTFS/proc")
                        sudo mount -vt proc proc $dir
                        ;;
                "$ROOTFS/sys")
                        sudo mount -vt sysfs sysfs $dir
                        ;;
                "$ROOTFS/run")
                        sudo mount -vt tmpfs tmpfs $dir
                        ;;
                esac
        done

        if [ -h $ROOTFS/dev/shm ]; then
                dir=$ROOTFS/$(readlink $ROOTFS/dev/shm)
                if [ ! -d $dir ]; then
                        sudo mkdir -vp $dir
                fi
        fi
}

function mount_dirs()
{
        for dir in $ROOTFS/build $ROOTFS/tools; do
                if [ "$1" == "clean" ]; then
                        if grep -q "$dir" /proc/mounts; then
                                sudo umount -v $dir
                        else
                                printf "%-32s already umounted\n" $dir
                        fi
                        continue
                fi

                if grep -q "$dir" /proc/mounts; then
                        printf "%-32s already mounted\n" $dir
                        continue
                fi

                if [ ! -d $dir ]; then
                        echo "$dir not exists"
                        continue
                fi

                case "$dir" in
                "$ROOTFS/build")
                        sudo mount -v --bind $BUILD_INSTALL $dir
                        ;;
                "$ROOTFS/tools")
                        sudo mount -v --bind $TOOLS_INSTALL $dir
                        ;;
                esac
        done
}

function make_clean()
{
	echo "make clean"

	mount_memfs clean
	mount_dirs clean
	rm -rf $SOURCE_TAR
	sudo rm -rf $TOOLS_SRC
	sudo rm -rf $SYSTEM_SRC
	sudo rm -rf $TOOLS_INSTALL
	sudo rm -rf $SYSTEM_INSTALL
	sudo rm -vf /tools
}

function main()
{
	case "$1" in
	"clean")
		make_clean
		;;
	*)
		print_env
		;;
	esac
}

main $1

#end
