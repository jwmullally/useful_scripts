#!/bin/bash

set -euo pipefail

extract_iso() {
    ISO="$1"
    ISODIR="$2"
    mkdir "$ISODIR"
    echo "Extracting $ISO to $ISODIR..."
    for filepath in $(isoinfo -f -R -i "$ISO"); do
        filedir="$ISODIR/$(dirname $filepath)"
        [ -d "$filedir" ] || rm "$filedir"
        mkdir -p "$filedir"
        isoinfo -R -i "$ISO" -x "$filepath" > "$ISODIR/$filepath"
    done
}

patch_contents() {
    ISODIR="$1"
    KS="$2"
    echo "Patching $ISODIR. Kickstart: $KS"
    cp "$KS" "$ISODIR/ks.cfg"
    sed -i '1s/^/serial 0 9600\n/' "$ISODIR/isolinux/isolinux.cfg"
    sed -i 's/^timeout .*/timeout 50/' "$ISODIR/isolinux/isolinux.cfg"
    sed -i 's/ quiet//' "$ISODIR/isolinux/isolinux.cfg"
    sed -i 's/ rd.live.check//' "$ISODIR/isolinux/isolinux.cfg"
    sed -i '/^\s*append initrd=/ s/$/ inst.ks=cdrom:\/ks.cfg inst.cmdline console=tty0 console=ttyS0,9600n8/' "$ISODIR/isolinux/isolinux.cfg"
}

rebuild_iso() {
    ISODIR="$1"
    LABEL="$2"
    OUTFILE="$3"
    echo "Generating $OUTFILE (label $LABEL) from $ISODIR..."
    mkisofs \
        -quiet \
        -J -R -l \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e images/efiboot.img \
        -no-emul-boot \
        -V "$LABEL" \
        -o "$OUTFILE" \
        "$ISODIR"
}

rebuild() {
    ISO="$1"
    KS="$2"

    LABEL="$(isoinfo -d -i "$ISO" | awk '/^Volume id: / { print $3 }')"
    OUTFILE="$(basename "$ISO" .iso).ks.iso"
    ISODIR="$OUTFILE.root"

    extract_iso "$ISO" "$ISODIR"
    patch_contents "$ISODIR" "$KS"
    rebuild_iso "$ISODIR" "$LABEL" "$OUTFILE"
}

case $1 in
    extract_iso)
        extract_iso $2 $3
        ;;
    patch_contents)
        patch_contents $2 $3
        ;;
    rebuild_iso)
        rebuild_iso $2 $3 $4
        ;;
    rebuild)
        rebuild $2 $3
        ;;
    *)
        cat << EOF
This script repacks Fedora/RHEL/CentOS ISOs to include a
kickstart file and redirects output to serial console.

Useful for remote unattended installs using a single self-contained ISO.
Also comes in handy with plain QEMU where virt-install is unavailable
(e.g. provisioning to RAID disks using data center bare metal rescue images).

If you just need automated loading of ks.cfg from a seperate CD, see 
kickstart "OEMDRV" volume label support:
    cp ks.cfg oemdrv/ && mkisofs -V OEMDRV -o oemdrv.iso oemdrv/

Commands: 
    rebuild ISO KICKSTART_FILE

    extract_iso ISO ISODIR
    patch_contents ISODIR KICKSTART_FILE
    rebuild_iso ISODIR LABEL OUTFILE

Example:
    $0 \\
        rebuild \\
        Fedora-Atomic-x86_64-26.iso \\
        ks.cfg

    qemu-system-x86_64 \\
        -enable-kvm \\
        -drive file=/dev/sda \\
        -drive file=/dev/sdb \\
        -cdrom Fedora-Atomic-x86_64-26.ks.iso \\
        -device virtio-net,netdev=mynet0,mac=00:11:22:33:44:55 \\
        -netdev user,id=mynet0 \\
        -boot d \\
        -nographic
EOF
        exit 1
        ;;
esac
