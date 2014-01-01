#!/tmp/busybox sh
#
# Universal Updater Script for Samsung Galaxy S Phones
# (c) 2011 by Teamhacksung // EpicCM
# Samsung Victory version
#

check_mount() {
    local MOUNT_POINT=`/tmp/busybox readlink $1`
    if ! /tmp/busybox test -n "$MOUNT_POINT" ; then
        # readlink does not work on older recoveries for some reason
        # doesn't matter since the path is already correct in that case
        /tmp/busybox echo "Using non-readlink mount point $1"
        MOUNT_POINT=$1
    fi
    if ! /tmp/busybox grep -q $MOUNT_POINT /proc/mounts ; then
        /tmp/busybox mkdir -p $MOUNT_POINT
        /tmp/busybox umount -l $2
        if ! /tmp/busybox mount -t $3 $2 $MOUNT_POINT ; then
            /tmp/busybox echo "Cannot mount $1 ($MOUNT_POINT)."
            exit 1
        fi
    fi
}

set_log() {
    rm -rf $1
    exec >> $1 2>&1
}

fix_package_location() {
    local PACKAGE_LOCATION=$1
    # Remove leading /mnt for Samsung recovery
    PACKAGE_LOCATION=${PACKAGE_LOCATION#/mnt}
    # Convert to modern sdcard path
    PACKAGE_LOCATION=`echo $PACKAGE_LOCATION | /tmp/busybox sed -e "s|^/sdcard|/storage/sdcard0|"`
    echo $PACKAGE_LOCATION
}

set -x
export PATH=/:/sbin:/system/xbin:/system/bin:/tmp:$PATH

# check if we're running on a bml or mtd device, or if /system needs to be resized
if /tmp/busybox test -e /dev/block/bml7 || [ $(grep mtdblock2 /proc/partitions | awk '{ print $3 }') -lt 469504 ]; then
    # we're running on a bml device, or /system is the wrong size

    # make sure sdcard is mounted
    check_mount /mnt/sdcard /dev/block/mmcblk0p1 vfat

    # everything is logged into /mnt/sdcard/cyanogenmod_bml.log
    set_log /mnt/sdcard/cyanogenmod_bml.log

    # write the package path to sdcard cyanogenmod.cfg
    if /tmp/busybox test -n "$UPDATE_PACKAGE" ; then
        /tmp/busybox echo `fix_package_location $UPDATE_PACKAGE` > /mnt/sdcard/cyanogenmod.cfg
    fi

    # Scorch any ROM Manager settings to require the user to reflash recovery
    /tmp/busybox rm -f /mnt/sdcard/clockworkmod/.settings

    # write new kernel to boot partition
    /tmp/flash_image boot /tmp/boot.img
    if [ "$?" != "0" ] ; then
        exit 3
    fi
    /tmp/busybox sync

    /sbin/reboot now
    exit 0

elif /tmp/busybox test -e /dev/block/mtdblock0 ; then
    # we're running on a mtd (current) device

    # make sure sdcard is mounted
    check_mount /sdcard /dev/block/mmcblk0p1 vfat

    # everything is logged into /sdcard/cyanogenmod.log
    set_log /sdcard/cyanogenmod_mtd.log

    if ! /tmp/busybox test -e /sdcard/cyanogenmod.cfg ; then
        # update install - flash boot image then skip back to updater-script
        # (boot image is already flashed for first time install or old mtd upgrade)

        # flash boot image
        /tmp/bml_over_mtd.sh boot 72 reservoir 4012 /tmp/boot.img

        exit 0
    fi

    # if a cyanogenmod.cfg exists, then this is a first time install
    # let's format the volumes

    # remove the cyanogenmod.cfg to prevent this from looping
    /tmp/busybox rm -f /sdcard/cyanogenmod.cfg

    # unmount, format and mount system
    /tmp/busybox umount -l /system
    /tmp/erase_image system
    /tmp/busybox mount -t yaffs2 /dev/block/mtdblock2 /system

    # unmount and format cache
    /tmp/busybox umount -l /cache
    /tmp/erase_image cache

    # unmount and format datadata
    /tmp/busybox umount -l /data
    /tmp/erase_image userdata

    # restart into recovery so the user can install further packages before booting
    REC_BOOT_ADDR="0x57fff800"
    REC_BOOT_MAGIC="0x5EC0B007" # Must be in caps.

    /tmp/busybox devmem "$REC_BOOT_ADDR" 32 "$REC_BOOT_MAGIC"
    exit 0
fi
