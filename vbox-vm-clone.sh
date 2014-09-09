#!/usr/local/bin/bash
#
# Clone an existing VM with disks on ZVOL
# See the README.md file for general documentation
#
# This script takes one argument:
#  - the VM name, with an optional path prefix

### Constants
zvol_root='/dev/zvol/'
# The zfs pool where are stored the ZVOLs
zfs_pool='tank/vm/disks/'
# ZFS snapshot names for a clean state and the previous clean state
curr='Clean'
prev='Previous'
# VirtualBox VM root
vbox_root='/tank/vm/'
# VM snapshot to be cloned
tbc='ToBeCloned'

### User supplied variables
# $1: the full VM path, it can take subdirectories under $zfs_pool
if [ -z $1 ]; then
    echo -e "\033[31mPlease provide a VM name/path to make a snapshot.\033[0m"
    exit 1
fi
VM_path=$1
VM=${VM_path/*\//}

# $2: the full path for the new VM, it can take subdirectories under $zfs_pool
if [ -z $2 ]; then
    echo -e "\033[31mPlease provide a VM name/path for the new VM.\033[0m"
    exit 1
fi
new_VM_path=$2
new_VM=${new_VM_path/*\//}
new_VM_group='/'${new_VM_path%%\/*}

echo -e "We're going to clone \033[38;5;12m$VM_path\033[0m@\033[38;5;12m$curr\033[0m into \033[38;5;12m$new_VM_path\033[0m@\033[38;5;12m$curr\033[0m to make a new VM named \033[38;5;12m$new_VM\033[0m."

### Checks
# Check VM exists, has ZVOL disks and the $curr snapshot exists
VBoxManage showvminfo $VM > /dev/null
if [ $? -ne 0 ]; then
    echo -e "\033[31mThe VM \033[38;5;12m$VM\033[0;31m doesn't seem to be existing.\033[0m"
    exit 1
fi
zfs list $zfs_pool$VM_path@$curr > /dev/null
if [ $? -ne 0 ]; then
    echo -e "\033[31mThe VM \033[38;5;12m$VM\033[0;31m doesn't seem to have a snapshot of ZVOL disks at \033[38;5;12m$VM_path@$curr\033[0m"
    exit 1
fi

# Check there's no existing VM with the new name
VBoxManage showvminfo $new_VM > /dev/null 2> /dev/null
ret=$?
if [ $ret -eq 0 ]; then
    echo -e "\033[31mThere is already a VM named \033[38;5;12m$new_VM\033[0m, please provide another name."
    exit 1
fi
if [ $ret -ne 1 ]; then
    echo -e "\033[38;5;214mThis was not the return code that I was expecting ($return) for \033[38;5;12m$new_VM\033[0m"
    echo "I continue anyway, but something might go wrong later."
fi

### Action
# 1. We clone the ZVOL and take a initial snapshot
zfs clone ${zfs_pool}${VM_path}@${curr} ${zfs_pool}${new_VM_path}
if [ $? -ne 0 ]; then
    echo -e "\033[31mThere was a problem when cloning \033[38;5;12m$VM_path@$curr\033[31m to \033[38;5;12m$new_VM_path@$curr\033[0m"
    exit 1
fi
zfs snapshot ${zfs_pool}${new_VM_path}@${curr}

# 2. We clone the VM and remove any associated disk
VBoxManage clonevm $VM --snapshot $tbc --mode machine --options link --name $new_VM --groups $new_VM_group --register
vmdk_snap=`VBoxManage list hdds | awk "/\/${new_VM}\/Snapshots\// {print \\$2}"`
echo $vmdk_snap
VBoxManage storageattach $new_VM --storagectl SATA --port 0 --medium none
VBoxManage closemedium disk "$vmdk_snap" --delete

# 3. We create a new VMDK
VBoxManage internalcommands createrawvmdk -filename ${vbox_root}${new_VM_path}/${new_VM}.vmdk -rawdisk ${zvol_root}${zfs_pool}${new_VM_path}

# 4. We attach the VMDK to the newly created VM
VBoxManage storageattach $new_VM --storagectl SATA --port 0 --type hdd --medium ${vbox_root}${new_VM_path}/${new_VM}.vmdk

echo -e "\033[38;5;12m${new_VM}\033[0m was created with its disk as \033[38;5;12m${zvol_root}${zfs_pool}${new_VM_path}\033[0m"

