#!/bin/sh
set -ex

virt-install \
    --connect qemu:///system \
    --name test-host \
    --ram 4096 \
    --vcpus 2 \
    --arch x86_64 \
    --os-variant fedora27 \
    --disk size=8 \
    --network default \
    --location  http://dl.fedoraproject.org/pub/fedora/linux/releases/28/Everything/x86_64/os/ \
    --initrd-inject=fedora-minimal.ks \
    --extra-args "ks=file:/fedora-minimal.ks"


target_ip="$(virsh --quiet -c qemu:///system domifaddr test-host | tail -n1 | awk '{print $4}' | cut -d'/' -f1)"
echo "Install complete, connect using:"
echo
echo "ssh root@$target_ip"
echo
echo "SSHPASS=fedora sshpass -e ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@$target_ip"
