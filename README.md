# `pve_backup_usb.sh` - Script to copy local PVE backup dumps to encrypted USB disks

**This project is *not* associated with Proxmox Server Solutions GmbH nor the official [Proxmox Virtual Environment (PVE)](https://www.proxmox.com/en/proxmox-virtual-environment/overview) project.** Please [report any bugs or suggestions to us](./CONTRIBUTING.md), do NOT use the official Proxmox support channels.

---

`pve_backup_usb.sh` is a script for smaller environments without dedicated [Proxmox Backup Server](https://www.proxmox.com/en/proxmox-backup-server/overview). It helps you to copy PVE dumps (created by using the [built-in backup functionality](https://pve.proxmox.com/wiki/Backup_and_Restore) stored on a PVE Host) to external, encrypted USB drives for offsite disaster backup.

**Features:**

* Easy selection of PVE dumps to copy (including limitation of „only the N newest ones of machine X“).
* Can search multiple backup source directories for PVE dumps.
* Automatic search of USB drive, mount including decryption / `cryptsetup open`.
* Extensive output, syslog and optional mail notification (using the system's `mail`; please make sure a [proper mail relay is configured](https://foundata.com/en/blog/2023/proxmox-pve-email-relay-smart-host/)).
* Robust error handling and checks (e.g. available space on target, prevent parallel execution and so on).


## Table of Contents

- [Installation](#installation)
- [Updating](#updating)
- [Usage](#usage)
  - [Parameters](#parameters)
  - [Cronjob example](#cronjob-example)
  - [Preparation of an external USB drive](#preparation-of-an-external-usb-drive)
  - [Logging](#logging)
    - [Logfile](#logfile)
    - [systemd journal](#systemd-journal)
    - [Example logfile](#example-logfile)
- [Compatibility](#compatibility)
- [Contributing](#contributing)
- [Licensing, copyright](#licensing-copyright)
- [Author information](#author-information)


## Installation

Simply store [`pve_backup_usb.sh`](./pve_backup_usb.sh) where you like and make it executable. `/usr/local/bin/pve_backup_usb.sh` is usually a good place.

You can download the latest release via command line as follows:

```bash

# install dependencies (all except of hdparm and jq should be already
# installed on a common PVE host; jq is not needed by the script for
# some of the code snippets of the README)
apt-get install coreutils hdparm jq lsof util-linux

# get version number of the latest release
version="$(curl -s -L https://api.github.com/repos/foundata/proxmox-pve_backup_usb/releases/latest | jq -r '.tag_name' | sed -e 's/^v//g')"
printf '%s\n' "${version}"

# download
curl -L "https://raw.githubusercontent.com/foundata/proxmox-pve_backup_usb/v${version}/pve_backup_usb.sh" > "/usr/local/bin/pve_backup_usb.sh"

# check the content (you've just downloaded a file from the internet :-D)
cat "/usr/local/bin/pve_backup_usb.sh"

# take care about owner and permissions
chown "root:root" "/usr/local/bin/pve_backup_usb.sh"
chmod 0755 "/usr/local/bin/pve_backup_usb.sh"
```


## Updating

Updating is as simple as overwriting the old script file. Just follow the [installation instructions](#installation) to get the newest release. This should be a low-risk operation as there were no backwards-compatibility-breaking releases yet (for example, all existing releases handle the target storage the same way).


## Usage

Example call:

```bash
pve_backup_usb.sh \
  -b "10:1,22:4,333" -s "/mnt/backup1/dump:/mnt/backup2/dump" \
  -c -e "it@example.com" -g "admin2@example.com,admin3@example.com"
```

Explanation:

* `-b "10:1,22:4,333"`: Handling backups of
  * machine with PVE ID `10`: only the last backup (`:1`) (if there are more, they will be ignored)
  * machine with PVE ID `22`: only the last four backups (`:4`) (if there are more, they will be ignored)
  * machine with PVE ID `333`: all existing backups (no `:X` behind the PVE ID)
* `-s`: Search in `/mnt/backup1/dump` and `/mnt/backup2/dump` for PVE backup dumps to copy. Both paths have to exist. Separator for multiple sources is `:`.
* `-c`: Create a checksums file and verify the backup copies afterwards.
* `-e`: email the backup report to `it@example.com`.
* `-g`: email the backup report (as CC) to `admin2@example.com` and `admin3@example.com`.

The script deletes the old backup content on the target device (after copying the new data if there is enough space to copy the new files and keep the old ones during copy operation or upfront if there is not enough space to keep both). To keep multiple revisions of the last `N` PVE dumps, you can use multiple external drives and rotate them as you wish (=disconnect old drive, change and connect new drive).

By default, the script is using the first partition on the first USB disk it detects in `/dev/disk/by-path/`. No worries: existing drives not [prepared](#preparation-of-an-external-usb-drive) for usage won't be destroyed nor touched as the decryption will fail. However, this automatism presumes that only one USB disk is connected during the script run. Defining a UUID will work if there is more than one USB disk attached (cf. `-d` parameter).


### Parameters

**Mandatory:**

* `-b`: Defines which PVE dumps of will be copied. The format is a CSV list of `PveID:maxCount` value tuples where `:maxCount` is optional. All backups for `PveId` will be copied if `:maxCount` is not given. Example: The value `123:2,456:4,789` will copy
  * the last two backups of machine `123`
  * the last four backups machine `456`
  * all backups of machine `789`
* `-s`: List of one or more directories to search for PVE dumps, without trailing slash, separated by `:`. Examples: `/path/to/pve/dumps` or `/pve1/dumps:/pve2/dumps`.

**Important, but optional**

* `-c`: Flag to enable checksum creation and verification of the copies (recommended for safety but propably doubles the time needed for completing the task).
* `-e`: Email address to send notifications to. Format: `email@example.com`. Has to be set for sending mails. This script is using the system's `mail` command, so please make sure a proper relay is configured.
* `-g`: Email address(es) to send notifications to (CC). Format: `email@example.com`. Separate multiple addresses via comma (CSV list).

**Miscellaneous, optional**

* `-d`: A UUID of the target partition to decrypt. Will be used to search it in `/dev/disk/by-uuid/` (you might use `blkid /dev/sdX1` to determine the UUID). By default, the script is simply using the first partition on the first USB disk it is able to find via `/dev/disk/by-path/`. No worries: existing drives not used for backups won't be destroyed as the decryption will fail. But this automatism presumes that only one USB disk is connected during the script run. Defining a UUID will work if there are more than one (e.g. when it is not feasible in your environment to just have one disk connected simultaneously).
* `-h`: Flag to print help.
* `-k`: Path to a keyfile containing a passphrase to unlock the target device. Defaults to `/etc/credentials/luks/pve_backup_usb`. There must be no other chars beside the passphrase, including no trailing new line or [`EOF`](https://en.wikipedia.org/wiki/End-of-file). You might use `perl -pi -e 'chomp if eof' /etc/credentials/luks/pve_backup_usb` to get rid of an invisible, unwanted `EOF`.
* `-l`: Name used for handling LUKS via `/dev/mapper/` and creating a mountpoint subdirectory at `/media/`. Defaults to `pve_backup_usb`. 16 alphanumeric chars at max.
* `-q`: Flag to enable quiet mode. Emails will be sent only on `error` or `warning` then (but not on `info` or `success`).
* `-u`: Username of the account used to run the backups. Defaults to `root`. The script checks if the correct user is calling it and permissions of e.g. the keyfile are fitting or are too permissive. The user also needs permissions to mount devices. Running the script as `root` is propably a good choice for most environments.


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
apt-get install parted cryptsetup
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

dmsetup ls --target "crypt"
ls -l "/dev/mapper/pve_backup_usb"

cryptsetup luksClose "pve_backup_usb"
dmsetup ls --target "crypt"
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


#### Example logfile

Running the command

```bash
/usr/local/bin/pve_backup_usb.sh -c -b "120:1" -s "/mnt/localbackup01/pve/dump"
```

to mirror the lastest dump of the VM with PVE ID `120` from `/mnt/localbackup01/pve/dump` to the encrypted USB device (a cheap 5TB WD Elements USB-HDD) gave the following logfile:

```
#### pve_backup_usb.sh ####
Current time: Wed Aug 30 05:58:34 PM UTC 2023.
CSV list of 'PveMachineID[:MaxBackupCount]' entries (defines what to copy): '120:1'
Sync, unmount and close of LUKS device (upfront safeguard against stale or previously interrupted execs).
Creating mountpoint at '/media/pve_backup_usb'
Going to unlock '/dev/sdc1', using using keyfile '/etc/credentials/luks/pve_backup_usb'
Successfully unlocked '/dev/sdc1', should be available at '/dev/mapper/pve_backup_usb' now.
Current time: Wed Aug 30 05:58:37 PM UTC 2023.
Elapsed time: 00h:00m:03s.

#### Info about physical disk (mounted at /media/pve_backup_usb) ####
Model Number:       WDC WD50NDZW-11MR8S1
Serial Number:      WD-<censored>

#### Checking for existing backups to copy for PVE ID 120 ####
Found backup 'vzdump-qemu-120-2023_08_29-21_00_03' in '/mnt/localbackup01/pve/dump'
Found backup 'vzdump-qemu-120-2023_08_28-21_00_02' in '/mnt/localbackup01/pve/dump'
Found backup 'vzdump-qemu-120-2023_08_24-21_00_05' in '/mnt/localbackup01/pve/dump'
Added backup 'vzdump-qemu-120-2023_08_29-21_00_03' to the list for processing.
Skipped backup 'vzdump-qemu-120-2023_08_28-21_00_02' as max backup count 1 for ID '120' was reached.
Skipped backup 'vzdump-qemu-120-2023_08_24-21_00_05' as max backup count 1 for ID '120' was reached.


#### Miscellaneous preparation ####
Copying the backup files will need 20.89GiB of space on the target device.
The target device mounted at '/media/pve_backup_usb' has a size of about 4.27TiB.
There seems to be older backup data on the target device, moving it from '/media/pve_backup_usb/dump' to '/media/pve_backup_usb/dump_old'
Successfully moved '/media/pve_backup_usb/dump' to '/media/pve_backup_usb/dump_old'.
There is about 4.27TiB of free space available on the target device.
Current time: Wed Aug 30 05:58:37 PM UTC 2023.
Elapsed time: 00h:00m:03s.
Going to process the created list of backups to copy now.
Creating copy target directory at '/media/pve_backup_usb/dump'.

#### Handling backup 'vzdump-qemu-120-2023_08_29-21_00_03' ####
Creating checksums file
cd "/mnt/localbackup01/pve/dump" && sha1sum "./vzdump-qemu-120-2023_08_29-21_00_03"* > "/media/pve_backup_usb/dump/vzdump-qemu-120-2023_08_29-21_00_03.sha1" 2>&1
Current time: Wed Aug 30 05:59:10 PM UTC 2023.
Elapsed time: 00h:00m:36s.
Starting copy of backup
cp -r -f -v "/mnt/localbackup01/pve/dump/vzdump-qemu-120-2023_08_29-21_00_03"* "/media/pve_backup_usb/dump" 2>&1
  '/mnt/localbackup01/pve/dump/vzdump-qemu-120-2023_08_29-21_00_03.log' -> '/media/pve_backup_usb/dump/vzdump-qemu-120-2023_08_29-21_00_03.log'
  '/mnt/localbackup01/pve/dump/vzdump-qemu-120-2023_08_29-21_00_03.vma.zst' -> '/media/pve_backup_usb/dump/vzdump-qemu-120-2023_08_29-21_00_03.vma.zst'
  '/mnt/localbackup01/pve/dump/vzdump-qemu-120-2023_08_29-21_00_03.vma.zst.notes' -> '/media/pve_backup_usb/dump/vzdump-qemu-120-2023_08_29-21_00_03.vma.zst.notes'
Current time: Wed Aug 30 06:12:50 PM UTC 2023.
Elapsed time: 00h:14m:16s.
Verify checksums of file copies
cd "/media/pve_backup_usb/dump" && sha1sum -c "./vzdump-qemu-120-2023_08_29-21_00_03.sha1" 2>&1
  ./vzdump-qemu-120-2023_08_29-21_00_03.log: OK
  ./vzdump-qemu-120-2023_08_29-21_00_03.vma.zst: OK
  ./vzdump-qemu-120-2023_08_29-21_00_03.vma.zst.notes: OK
Verification was successful.
Current time: Wed Aug 30 06:13:19 PM UTC 2023.
Elapsed time: 00h:14m:45s.
All file operations were finished successfully.
Going to clean up the old backup data at '/media/pve_backup_usb/dump_old'.
Current time: Wed Aug 30 06:13:20 PM UTC 2023.
Elapsed time: 00h:14m:46s.
Mirroring backups to '/media/pve_backup_usb' was successful.
Syslog entry was created (priority: info)
Successfully unmounted '/media/pve_backup_usb'
Successfully deleted mountpoint '/media/pve_backup_usb'.
Successfully closed LUKS device 'pve_backup_usb'
```


## Compatibility

The script should be compatible with Proxmox Virtual Environment (PVE) 7.X and newer. It was tested on:

* Proxmox VE 8: 8.1.4, 8.0.4
* Proxmox VE 7: 7.4-16


## Contributing

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) if you want to get involved.

The script's functionality is mature, so there might be little activity on the repository in the future. Don't get fooled by this, the project is under active maintenance and used on daily basis by the maintainers.


## Licensing, copyright

<!--REUSE-IgnoreStart-->
Copyright (c) 2023, 2024 foundata GmbH (https://foundata.com)

This project is licensed under the Apache License 2.0 (SPDX-License-Identifier: `Apache-2.0`), see [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt) for the full text.

The [`.reuse/dep5`](.reuse/dep5) file provides detailed licensing and copyright information in a human- and machine-readable format. This includes parts that may be subject to different licensing or usage terms, such as third party components. The repository conforms to the [REUSE specification](https://reuse.software/spec/), you can use [`reuse spdx`](https://reuse.readthedocs.io/en/latest/readme.html#cli) to create a [SPDX software bill of materials (SBOM)](https://en.wikipedia.org/wiki/Software_Package_Data_Exchange).
<!--REUSE-IgnoreEnd-->

[![REUSE status](https://api.reuse.software/badge/github.com/foundata/proxmox-pve_backup_usb)](https://api.reuse.software/info/github.com/foundata/proxmox-pve_backup_usb)


## Author information

This project was created and is maintained by [foundata](https://foundata.com/). If you like it, you might [buy them a coffee](https://buy-me-a.coffee/proxmox-pve_backup_usb/).