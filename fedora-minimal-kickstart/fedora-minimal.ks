text
lang en_US.UTF-8
keyboard us
timezone Etc/UTC
auth --useshadow --passalgo=sha512
selinux --enforcing
firewall --enabled --service=mdns
services --enabled=sshd,NetworkManager,chronyd
network --hostname test-host --bootproto=dhcp --device=link --activate
rootpw --plaintext fedora

zerombr
clearpart --all --initlabel --disklabel=msdos
part / --grow --fstype=ext4

%packages
@core
kernel
%end

shutdown
