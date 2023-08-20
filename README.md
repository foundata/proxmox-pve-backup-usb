# `pve_backup_usb.sh` - Script to copy local PVE backup dumps to encrypted USB disks

**This project is *not* associated with the official [Proxmox Virtual Environment (PVE)](https://www.proxmox.com/en/proxmox-virtual-environment/overview) nor Proxmox Server Solutions GmbH.**

`pve_backup_usb.sh` is a script for smaller environments without dedicated [Proxmox Backup Server](https://www.proxmox.com/en/proxmox-backup-server/overview). It helps you to copy PVE dumps (created by using the [built-in backup functionality](https://pve.proxmox.com/wiki/Backup_and_Restore) stored on a PVE Host) to external, encrypted USB drives for offsite disaster backup.

**Features:**

* Easy selection of PVE dumps to copy (including limitation of „only the N newest ones of machine X“).
* Can search multiple backup source directories for PVE dumps.
* Automatic search of USB drive, mount including decryption / `cryptsetup open`.
* Extensive output, syslog and optional mail notification (using the system's `mail`; please make sure a proper relay is configured).
* Robust error handling and checks (e.g. available space on target, prevent parallel execution and so on).


## Table of Contents

- [Installation](#installation)
- [Usage](#usage)
  - [Cronjob example](#cronjob-example)
  - [Preparation of an external USB drive](#preparation-of-an-external-usb-drive)
  - [Logging](#logging)
    - [Logfile](#logfile)
    - [systemd journal](#systemd-journal)
- [License, copyright](#license-copyright)
- [Author information](#author-information)


## Installation

Simply store [`pve_backup_usb.sh`](./pve_backup_usb.sh) where you like and make it executable. `/usr/local/bin/pve_backup_usb.sh` is usually a good place.

You might download the latest release via command line as follows:

```bash

# install dependencies (usually, all except of hdparm should be
# already installed on a common PVE host)
apt-get install coreutils hdparm lsof util-linux

# get latest version
apt-get install jq
version="$(curl -s -L https://api.github.com/repos/foundata/proxmox-pve_backup_usb/releases/latest | jq -r '.tag_name' | sed -e 's/^v//g')"
printf '%s\n' "${version}"

# download
curl -L "https://raw.githubusercontent.com/foundata/proxmox-pve_backup_usb/v${version}/pve_backup_usb.sh"  > "/usr/local/bin/pve_backup_usb.sh"

# check the content (you've just downloaded a file from the internet :-D)
cat "/usr/local/bin/pve_backup_usb.sh"

# take care about owner and permissions
chown "root:root" "/usr/local/bin/pve_backup_usb.sh"
chmod 0755 "/usr/local/bin/pve_backup_usb.sh"
```


## Usage

Example call:

```bash
pve_backup_usb.sh \
  -b "10:1,22:4,333" -s "/mnt/backup1/dump:/mnt/backup2/dump" \
  -c -e "it@example.com" -g "admin2@example.com,admin3@example.com"
```

Explanation:

* `-b "10:1,22:4,333"`: Handling backups of
  * machine with PVE ID `10`: Only the last backup (if there are more, they will be ignored)
  * machine with PVE ID `22`: Only the last four backups (if there are more, they will be ignored)
  * machine with PVE ID `333`: All existing backups
* Search in `/mnt/backup1/dump` and `/mnt/backup2/dump` for backups
* `-c`: Create a checksums file and verify the backup copies afterwards
* `-e`: email the backup report to `it@example.com`
* `-g`: email the backup report (as CC) to `admin2@example.com` and `admin3@example.com`


Description of available parameters:

**Mandatory:**

* `-b`: Defines which PVE dumps of will be copied. The format is a CSV list of `PveID:maxCount` value tuples where `:maxCount` is optional. All backups for `PveId` will be copied if `:maxCount` is not given. Example: The value `123:2,456:4,789` will copy
  * the last two backups of machine `123`
  * the last four backups machine `456`
  * all backups of machine `789`
* `-s`: List of one or more directories to search for PVE dumps, without trailing slash, separated by `:`. Examples: `/path/to/pve/dumps` or `/pve1/dumps:/pve2/dumps`.

**Quite important, but optional**

* `-c`: Flag to enable checksum creation and verification of the copies (recommended for safety but propably doubles the time needed for completing the task).
* `-e`: Email address to send notifications to. Format: `email@example.com`. Has to be set for sending mails. This script is using the system's `mail` command, so please make sure a proper relay is configured.
* `-g`: Email address(es) to send notifications to (CC). Format: `email@example.com`. Separate multiple addresses via comma (CSV list).

**Miscellaneous, optional**

* `-d`: A UUID of the target partition to decrypt. Will be used to search it in `/dev/disk/by-uuid/` (you might use `blkid /dev/sdX1` to determine the UUID). By default, the script is simply using the first partition on the first USB disk it is able to find via `/dev/disk/by-path/`. No worries: existing drives not used for backups won't be destroyed as the decryption will fail. But this automatism presumes that only one USB disk is connected during the script run. Defining a UUID will work if there are more than one (e.g. when it is not feasible in your environment to just have one disk connected simultaneously).
* `-h`: Flag to print help.
* `-k`: Path to a keyfile containing a passphrase to unlock the target device. Defaults to `/etc/credentials/luks/pve_backup_usb`. There must be no other chars beside the passphrase, including no trailing new line or [`EOF`](https://en.wikipedia.org/wiki/End-of-file). You might use `perl -pi -e 'chomp if eof' /etc/credentials/luks/pve_backup_usb` to get rid of an invisible, unwanted `EOF`.
* `-l`: Name used for handling LUKS via `/dev/mapper/` and creating a mountpoint subdirectory at `/media/`. Defaults to `pve_backup_usb`. 16 alphanumeric chars at max.
* `-q`: Flag to enable quiet mode. Emails will be sent only on error then.
* `-u`: Username of the account used to run the backups. Defaults to `root`. The script checks if the correct user is calling it and permissions of e.g. the keyfile are fitting or are too permissive. The user also needs permissions to mount devices. Running the script as `root`` is propably a good choice for most environments.

The script deletes the old backup content on the target device (afterwards, if there is enough space to copy the new files and keep the old ones during copy operation or upfront if there is not enough space to keep both). To keep multiple revisions of the last N PVE dumps, you simply have to use multiple external drives and rotate them as you wish (=disconnect old drive, change and connect new drive).

By default, the script is simply using the first partition on the first USB disk it is able to find via `/dev/disk/by-path/`. No worries: existing drives not used for backups won't be destroyed as the decryption will fail. But this automatism presumes that only one USB disk is connected during the script run. Defining a UUID will work when there are more (cf. `-d` parameter).


### Cronjob example

The easiest way for getting a rotation in place and use this script is a cronjob. For example, place something like the following via `crontab -e` in the crontab of `root`:

```
0 19 * * Sat  /usr/local/bin/pve_backup_usb.sh -b "10:1,22:4,333" -s "/mnt/backup1/dump:/mnt/backup2/dump" -c -e "it@example.com" -g "admin2@example.com,admin3@example.com" > /dev/null 2>&1
```

Explanation:

* `0 19 * * Sat  /usr/local/bin/pve_backup_usb.sh`: Run on [every Saturday at 19:00 o'clock](https://crontab.guru/#0_19_*_*_Sat).
* `-b "10:1,22:4,333"`: Handling backups of
  * machine with PVE ID `10`: Only the last backup (if there are more, they will be ignored)
  * machine with PVE ID `22`: Only the last four backups (if there are more, they will be ignored)
  * machine with PVE ID `333`: All existing backups
* Search in `/mnt/backup1/dump` and `/mnt/backup2/dump` for backups
* `-c`: Create a checksums file and verifies the backup copies afterwards
* `-e`: email the backup report to `it@example.com`
* `-g`: email the backup report (as CC) to `admin2@example.com` and `admin3@example.com`


### Preparation of an external USB drive

An external USB drive has to be prepared before using it as storage target for PVE dump copies:

1. Add a GPT partitioning table and one primary partition for the whole disk.
2. Encrypt it with LUKS.
3. Format the partition with a filesystem (e.g. EXT4 or XSF).
4. Place a keyfile with the LUKS passphrase on the PVE host for automatic opening of the device for backups.

Full example of preparing a drive:

```bash
# determine your device
lsblk
lsblk -l -p
ls -l /dev/disk/by-path/*usb*

TARGETDEVICE='/dev/sdX' # adapt X to point to your USB disk
DEVICELABEL='pve_backup_usb' # 16 chars max
MAPPERNAME="${DEVICELABEL}"

# get some infos about the drive
apt-get install hdparm
hdparm -I "${TARGETDEVICE}"

# make sure predefined filesystems are currently not mounted (new USB drives
# are usually shipped with a filesystem).
umount --force --recursive --all-targets "${TARGETDEVICE}"*

# Create a partition and encrypt it.
#
# Please use a long passphrase (at least 20 chars) for security and store
# it in your password management. You do not have to type it anywhere,
# the script will grab it from a keyfile later.
#
# You might want to look at a current system with disk encryption which crypto
# default settings are en-vouge:
#   dmsetup table ${deviceNameBelow/dev/mapper}
#   cryptsetup luksDump ${device}
# As of 2023 "aes-xts-plain64" should be a good choice.
apt-get install parted
parted "${TARGETDEVICE}" mktable GPT
parted "${TARGETDEVICE}" mkpart primary 0% 100%
cryptsetup luksFormat --cipher aes-xts-plain64 --verify-passphrase "${TARGETDEVICE}1"

# optional: add an additional fallback key. Please use a long passphrase (at least
# 20 chars) for security and store it in your password management.
cryptsetup luksDump "${TARGETDEVICE}1"
cryptsetup luksAddKey "${TARGETDEVICE}1"
cryptsetup luksDump "${TARGETDEVICE}1"

# open and list, access possible via /dev/mappper/${MAPPERNAME} afterwards
cryptsetup open "${TARGETDEVICE}1" "${MAPPERNAME}"
dmsetup ls --target "crypt"

# create EXT4 system, prevent lazy init to get full performance at first use
mkfs.ext4 \
  -E lazy_itable_init=0,lazy_journal_init=0 \
  -L "${DEVICELABEL}" "/dev/mapper/${MAPPERNAME}" && sync

# test mount
tmpdirmnt="$(mktemp -d)"
mount "/dev/mapper/${MAPPERNAME}" "${tmpdirmnt}"
ls -la "${tmpdirmnt}"

# close and cleanup (the drive is ready for usage afterwards and/or
# can be disconnected now)
umount "/dev/mapper/${MAPPERNAME}" && sync
cryptsetup luksClose "${MAPPERNAME}" && sync
```

Your USB disk is now encrypted. Therefore it is secure to store copies of PVE backups dumps on it. So you can use the USB drive for offsite backup without getting in trouble when a disk gets lost or stolen.

Now place a keyfile containing the passphrase to make it possible to automatically unlock the disk(s). By default, the script searches at `/etc/credentials/luks/pve_backup_usb` for it but you can specify another keyfile when calling `pve_backup_usb.sh` by using the `-k` parameter. Example:

```bash
# create the file
mkdir -p /etc/credentials/luks/
chmod 0770 /etc/credentials/
chmod 0770 /etc/credentials/luks/
touch /etc/credentials/luks/pve_backup_usb
chmod 0660 /etc/credentials/luks/pve_backup_usb

# now put the passphase (without linebreaks before or after) into
# /etc/credentials/luks/pve_backup_usb using your favorite editor

# nothing(!) is allowed at the end of the file, also no EOF like
# e.g. nano is adding it. Make sure there is none:
perl -pi -e 'chomp if eof' /etc/credentials/luks/pve_backup_usb

# test
TARGETDEVICE="/dev/$(ls -l /dev/disk/by-path/*usb*part1 | cut -f 7 -d "/" | head -n 1)"
cryptsetup open --key-file "/etc/credentials/luks/pve_backup_usb" "${TARGETDEVICE}" "pve_backup_usb"
ls -l "/dev/mapper/pve_backup_usb"
cryptsetup luksClose "pve_backup_usb"
```


### Logging

#### Logfile

The detailled logfile of a script run will be copied beside the mirrored backups and is named after the script's filename plus `.log` extension. By default, this is `/media/pve_backup_usb/dump/pve_backup_usb.sh.log`.

The logfile is handled as temporary file during the script execution and placed at `${TMPDIR}/pve_backup_usb_XXXXXXXXXXXXXX` where `XXXXXXXXXXXXXX` is random and `$TMPDIR` is either defined by your environment or set to `/tmp`. If you want to look at the file during execution without blocking the file, the following command can do so (the `:` at the beginning is no error):

```bash
: "${TMPDIR:=/tmp}"; cat "${TMPDIR}/pve_backup_usb_"* | less
```

If you are using email notifications (cf. `-e`, `-f` and `-g` parameters), the complete logfile content will be added to the email message automatically.


#### systemd journal

The script logs with its own filename as `SYSLOG_IDENTIFIER`. So by default, you can filter with `pve_backup_usb.sh` as follows:

```bash
# all logs
journalctl -t "pve_backup_usb.sh"

# all logs, reverse order
journalctl -t "pve_backup_usb.sh" -r

# all logs, reverse order, without pager (so no scrolling, all written directly to STDOUT)
journalctl -t "pve_backup_usb.sh" -r --no-pager

# only errors
journalctl -t "pve_backup_usb.sh" -r  -p 0..3

# only non-error messages
journalctl -t "pve_backup_usb.sh" -r  -p 4..7
```

Other examples:

```bash
# search for messages including related things (produced by other units, e.g. mount
# messages, cronjob start, ...) in  reverse order
journalctl -r -g "pve_backup_usb"

# JSON, pretty print
journalctl -o "json" --no-pager -t "pve_backup_usb.sh" -r | jq -C . | less
journalctl -o "json" --no-pager -g "pve_backup_usb" -r | jq -C . | less
```


## License, copyright

This project is under [Apache License 2.0](http://www.apache.org/licenses/LICENSE-2.0). See [`LICENSE`](./LICENSE) and [`NOTICE`](./NOTICE) for details.


## Author information

This project was created and is maintained by [foundata](https://foundata.com/). If you like it, you might [buy them a coffee](https://buy-me-a.coffee/proxmox-pve_backup_usb/).