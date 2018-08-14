#!/bin/sh
set -ex

## https://docs.fedoraproject.org/en-US/quick-docs/creating-windows-virtual-machines-using-virtio-drivers/
# wget https://fedorapeople.org/groups/virt/virtio-win/virtio-win.repo -O /etc/yum.repos.d/virtio-win.repo
# dnf install virtio-win

virt-install \
    --connect qemu:///system \
    --name=win10 \
    --memory=8192 \
    --cpu=Broadwell-noTSX-IBRS \
    --vcpus=2 \
    --os-type=windows \
    --os-variant=win10 \
    --disk bus=virtio,size=50 \
    --disk /var/lib/libvirt/images/Win10_1803_EnglishInternational_x64.iso,device=cdrom,bus=ide,shareable=on \
    --disk /usr/share/virtio-win/virtio-win.iso,device=cdrom,bus=ide,shareable=on \
    --disk /usr/share/virtio-win/virtio-win_amd64.vfd,device=floppy,readonly=on,shareable=on \
    --network network=default,model=virtio \
    --graphics spice,listen=none \
    --panic default \
    --rng /dev/random
