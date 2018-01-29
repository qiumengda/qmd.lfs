#!/bin/sh

#Make sure this file only be included once
if [ "$__MODULE_ADD_USER__" == "yes" ]; then
        return
else
        __MODULE_ADD_USER__=yes
fi

function add_lfs_user()
{
	print_title "Add lfs user and group"
        sudo groupadd lfs
        sudo useradd -s /bin/bash -g lfs -m -k /dev/null lfs
        sudo passwd lfs

#Use root
<< EOF
        cat > /home/lfs/.bash_profile << EOF
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\W\$ ' /bin/bash
EOF

#Use dd as root
<< EOF
        sudo dd of=/home/lfs/.bash_profile << EOF
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\W\$ ' /bin/bash
EOF

#Use tee as root
<< EOF
        cat << EOF | sudo tee /home/lfs/.bash_profile 
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\W\$ ' /bin/bash
EOF

#Use bash as root
<< EOF
        sudo bash -c "cat << EOF > /home/lfs/.bash_profile
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\W\$ ' /bin/bash
EOF"
EOF

#Use bash as root
#<<EOF
        sudo bash -c "cat > /home/lfs/.bash_profile" << EOF 
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\W\$ ' /bin/bash
EOF

        sudo bash -c "cat > /home/lfs/.bashrc" << EOF
set +h
umask 022
PS1='\u:\W\$ '
LFS=/mnt/lfs
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/tools/bin:/bin:/usr/bin
export LFS LC_ALL LFS_TGT PATH
alias ls='ls --color=auto'
alias grep='grep --color=auto'
EOF

	sudo grep -rHn lfs /etc/sudoers
	if [ $? != 0 ]; then
		sudo bash -c "cat >> /etc/sudoers" << EOF 
lfs ALL=(ALL) ALL
EOF
	fi

        #su - lfs
        #source /home/lfs/.bash_profile
        #sudo swapon -v /dev/sdb2
        #sudo chmod -v a+wt $LFS/sources

        #sudo chown -vR $LFS
}

function del_lfs_user()
{
	print_title "Delelte lfs user and group"
	sudo userdel -r lfs
	sudo groupdel lfs
}

function chown_lfs_user()
{
	print_title "Change files owner to lfs"
	sudo chown -v lfs:lfs $TOP
	sudo chown -v lfs:lfs $BUILD_INSTALL
	sudo chown -v lfs:lfs $BUILD_INSTALL/*.sh
	sudo chmod -v 777 $BUILD_INSTALL/*.sh
	sudo chown -v lfs:lfs $BUILD_INSTALL/kernel_config*
	sudo chown -vR lfs:lfs $SOURCE_TAR
}

#end
