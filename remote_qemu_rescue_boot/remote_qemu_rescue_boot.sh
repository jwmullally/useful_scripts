#!/bin/bash
set -e -o pipefail -o errtrace

SSH_OPTS="-o ServerAliveInterval=60 -o ControlMaster=auto -o ControlPath=~/.ssh/sock.%r@%h-%p -o ControlPersist=300"

usage() {
    cat <<EOF
This script assists installing or troubleshooting remote hosts when the host is
booted into some kind of rescue image.

Via SSH, a QEMU instance is started attached to the target disks. This is run
under screen to prevent SSH disconnects from killing the VM. QEMU can be 
configured to boot from an install ISO to install a new system, or from the OS
already on the disks in order to troubleshoot boot issues without needing
physical access to console. VNC can then be used to see the display of the host.

Requirements for the remote host are:
- QEMU (included in the rescue images of many dedicated host providers)
- wget (if an install ISO is to be fetched)
- root/sudo access to the disks
- The disks are unmounted and unused by the host rescue system
  WARNING: Filesystem corruption will result if both host system and VM write
           seperate changes to the disk. See "--drives" option for more info


Usage:
remote_qemu_rescue_boot.sh --host=HOST --action=ACTION [OPTIONS]

    --action=ACTION     Action to perform. Required.
                        halt: power off QEMU
                        install: start QEMU, booting from /tmp/install.iso.
                                 Also uploads oemdrv/ in ISO form, used
                                 for kickstart files, extra drivers etc.
                        rescue: start QEMU, booting from attached devices.
                                Useful to troubleshoot booting issues remotely
                                without console access to the host.
                        monitor: Connect to the monitor of the running QEMU
                        ssh: Start a tunnel to port 22 of the QEMU VM. This 
                             can be used to ssh into the host with:
                               ssh localhost -p 10022
                        vnc: Connect to the QEMU display via VNC.
                          Ex. --action=rescue
    --drives=DRIVES     Space seperated list of the physical block devices that
                        the system will boot from. This script attempts to stop
                        any auto-detected RAID arrays using these drives.
                        WARNING: There are many ways drives can still be in use
                                 by the parent OS - verify manually before
                                 running that they are not mounted or disk
                                 corruption could result.
                          Ex. --drives="/dev/sda /dev/sdb"
    --help              Show the program usage text and exit.
    --host=HOSTNAME     Set the host to connect to. Required.
                          Ex. --host=myhost.example.org
    --iso-url=URL       The URL of the install ISO to download to 
                        /tmp/install.iso for use by QEMU. To use a custom ISO,
                        omit this option and copy one to that location.
                          Ex. --iso-url="https://example.org/distro-123.iso"
    --mac=MACADDR       MAC address to be used for the QEMU network interface.
                        If not supplied, will default to an auto-generated one.
                          Ex. --mac="01:23:45:67:89:AB"
    --user=USER         SSH user. Must have sudo capability on remote host.
                        Defaults to 'root'.
                          Ex. --user=someuser
    --verbose           Enable verbose output.


Examples:
Installing a new OS:
    $ ./remote_qemu_rescue_boot.sh \\
        --host=myhost.example.org \\
        --drives="/dev/sda /dev/sdb" \\
        --iso-url="https://example.org/distro-123.iso" \\
        --action=install
    $ ./remote_qemu_rescue_boot.sh \\
        --host=myhost.example.org \\
        --action=vnc

Troubleshooting boot issues for an existing OS:
    $ ./remote_qemu_rescue_boot.sh \\
        --host=myhost.example.org \\
        --drives="/dev/sda /dev/sdb" \\
        --action=rescue
    $ ./remote_qemu_rescue_boot.sh \\
        --host=myhost.example.org \\
        --action=vnc
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        opt="${1%=*}"
        val="${1##*=}"
        if [ "$val" = "$opt" ]; then
            val=""
        fi
        shift
        case "$opt" in
            --action)
                ACTION="$val"
                ;;
            --drives)
                DRIVES="$val"
                ;;
            --help)
                usage
                exit
                ;;
            --host)
                HOST="$val"
                ;;
            --iso-url)
                ISO_URL="$val"
                ;;
            --mac)
                QEMU_MAC=",mac=$val"
                ;;
            --user)
                SSH_USER="$val"
                ;;
            --verbose)
                # shellcheck disable=SC2034
                VERBOSE='-v'
                set -x
                ;;
            *)
                echo "Unknown option \"$opt\", exiting..." 1>&2
                usage 1>&2
                exit 1
                ;;
        esac
    done

}

main() {
    if [ -z "$SSH_USER" ]; then
        SSH_USER='root'
    fi
    if [ -z "$HOST" ]; then
        echo "--host= needs to be defined" 1>&2
        exit 1
    fi
    SSH_CMD="ssh $SSH_OPTS $SSH_USER@$HOST"
    case $ACTION in
        halt)
            do_halt
            ;;
        install)
            do_install
            ;;
        rescue)
            do_rescue
            ;;
        monitor)
            connect_monitor
            ;;
        ssh)
            connect_ssh
            ;;
        vnc)
            connect_vnc
            ;;
        *)
            echo "--action=\"$ACTION\" unknown, exiting..." 1>&2;
            exit 1
            ;;
    esac
}

upload_oemdrv() {
    if [ ! -d oemdrv ]; then
        mkdir oemdrv
    fi
    mkisofs -V OEMDRV -o oemdrv.iso oemdrv/
    scp oemdrv.iso "$SSH_USER@$HOST":/tmp/
}

fetch_iso() {
    $SSH_CMD wget -c -O /tmp/install.iso "$ISO_URL"
}

umount_disks() {
    if [ -n "$DRIVES" ]; then
        found_raid=$($SSH_CMD "lsblk -lpno NAME,TYPE $DEVICES | awk '\$2~/^raid/ {print \$1}'")
        if [ -n "$found_raid" ]; then
            $SSH_CMD "sudo dmsetup remove_all && sudo mdadm --stop $found_raid"
        fi
    fi
}

run_qemu() {
    umount_disks
    screenrc | $SSH_CMD "cat - > /tmp/screenrc.custom"
    # shellcheck disable=SC2046,SC2068
    $SSH_CMD -t \
        screen -c "/tmp/screenrc.custom" -xRS qemu \
        sudo qemu-system-x86_64 \
        -enable-kvm \
        -cpu host \
        -smp 4 \
        -m 4096 \
        -k en-us \
        $(echo -n "$DRIVES" | xargs -d' ' -I '{}' echo -n "-drive file='{}' ") \
        -device virtio-net,netdev=mynet0$QEMU_MAC \
        -netdev user,id=mynet0,hostfwd=tcp:127.0.0.1:10022-:22 \
        -usbdevice tablet \
        -vnc 127.0.0.1:1 \
        -monitor stdio \
        $@
}

do_install() {
    upload_oemdrv
    if [ -n "$ISO_URL" ]; then
        fetch_iso
    fi
    run_qemu \
        -drive media=cdrom,file=/tmp/install.iso \
        -drive media=cdrom,file=/tmp/oemdrv.iso \
        -boot d
}

do_rescue() {
    run_qemu
}

do_halt() {
    $SSH_CMD screen -X -S qemu quit
}

connect_vnc() {
    $SSH_CMD -N -o ExitOnForwardFailure=yes -L 5901:localhost:5901 &
    vncviewer localhost:1
}

connect_monitor() {
    $SSH_CMD -t screen -x -S qemu
}

connect_ssh() {
    echo "To connect to remote VM, use: ssh localhost -p 10022"
    $SSH_CMD -N -o ExitOnForwardFailure=yes -L 10022:localhost:10022
}

screenrc() {
    cat <<EOF
zombie kr
startup_message off
msgminwait 1
EOF
}

errexit() {
  echo "Error in ${BASH_SOURCE[1]}:${BASH_LINENO[0]}: '${BASH_COMMAND}' exited with status $?" 1>&2
  exit -1
}
trap 'errexit' ERR
trap 'kill 0' EXIT

parse_args "$@"
main
