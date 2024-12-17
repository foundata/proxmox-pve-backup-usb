# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [1.4.0] - 2024-12-17

### Added

- Added `-v` parameter: Print the script's version number, then exit. (c72ac68, ae1f2ff)

### Fixed

- Fix automatic detection of unlabeled LUKS drives as backup targets (regression introduced with v1.3.0) (0afe1ef)


## [1.3.0] - 2024-12-08

### Added

- Enhanced `-d` parameter: Added support for custom disk labels or UUIDs to override default locations. Multiple targets can be specified as a CSV list. (a9699ab)

### Changed

- Improved automated search for backup target partitions: The script now also searches for the first partition labeled `pve_backup_usb` under `/dev/disk/by-label/`. (a9699ab)


## [1.2.0] - 2024-12-07

### Added

- New option (`-j`) to allow the backup process to proceed with remaining files even if errors occur during copying or verification. (1a3584d)

- Support for the [REUSE specification](https://reuse.software/spec/). The [`.reuse/dep5`](.reuse/dep5) file provides detailed licensing and copyright information in a human- and machine-readable format.

### Changed

- ⚠️ Changed repository URL from `https://github.com/foundata/proxmox-pve_backup_usb` to `https://github.com/foundata/proxmox-pve-backup-usb` according to [our guidelines](https://github.com/foundata/guidelines/blob/master/git-repository-naming.md). GitHub [redirects HTTP and most of the `git` actions](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository) but executing `git remote set-url origin git@github.com:foundata/proxmox-pve-backup-usb.git` is recommended.

- Better error messages (dmesg), e.g. provide useful information in the script's log about hardware failures. (94b68df)


## [1.1.3] - 2023-09-10

### Changed

- Undo moving old dumps on target device if deleting them would not free up sufficient space. (c2a741f)

### Fixed

- Fix error preventing copying even if there is enough space on the target in some situations. (559eb10)


## [1.1.2] - 2023-08-30

### Fixed

- Fix regression, preventing email notification on success. (085047d)


## [1.1.1] - 2023-08-23

### Fixed

- Logfile output was missing in email notification because of wrongly timed clean-up. (5436f18)


## [1.1.0] - 2023-08-20

### Added

- Introduce "warning" as message type. (5436f18)

### Changed

- "warning" if there were no backups to copy (was "error" before). (5436f18)
- Introduce `pve_backup_usb_` as prefix for tempfile. Makes it easier to look a the logfile's content during exec. (5436f18)


## [1.0.1] - 2023-08-19

### Fixed

- Fix help (`-h`) output and improve descriptions.


## [1.0.0] - 2023-08-19

### Added

- All functionality and files.


[unreleased]: https://github.com/foundata/proxmox-pve-backup-usb/compare/v1.4.0...HEAD
[1.4.0]: https://github.com/foundata/proxmox-pve-backup-usb/releases/tag/v1.4.0
[1.3.0]: https://github.com/foundata/proxmox-pve-backup-usb/releases/tag/v1.3.0
[1.2.0]: https://github.com/foundata/proxmox-pve-backup-usb/releases/tag/v1.2.0
[1.1.3]: https://github.com/foundata/proxmox-pve-backup-usb/releases/tag/v1.1.3
[1.1.2]: https://github.com/foundata/proxmox-pve-backup-usb/releases/tag/v1.1.2
[1.1.1]: https://github.com/foundata/proxmox-pve-backup-usb/releases/tag/v1.1.1
[1.1.0]: https://github.com/foundata/proxmox-pve-backup-usb/releases/tag/v1.1.0
[1.0.1]: https://github.com/foundata/proxmox-pve-backup-usb/releases/tag/v1.0.1
[1.0.0]: https://github.com/foundata/proxmox-pve-backup-usb/releases/tag/v1.0.0
