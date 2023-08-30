# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

- Nothing worth mentioning yet.


## [1.1.2] - 2023-08-30

### Fixed

- Fix regression, preventing email notification on success (085047d)


## [1.1.1] - 2023-08-23

### Fixed

- Logfile output was missing in email notification because of wrongly timed clean-up. (5436f18)


## [1.1.0] - 2023-08-20

### Added

- Introduce "warning" as message type (5436f18)

### Changed

- "warning" if there were no backups to copy (was "error" before) (5436f18)
- Introduce `pve_backup_usb_` as prefix for tempfile. Makes it easier to look a the logfile's content during exec. (5436f18)


## [1.0.1] - 2023-08-19

### Fixed

- Fix help (`-h`) output and improve descriptions.


## [1.0.0] - 2023-08-19

### Added

- All functionality and files.


[unreleased]: https://github.com/foundata/proxmox-pve_backup_usb/compare/v1.1.2...HEAD
[1.1.2]: https://github.com/foundata/proxmox-pve_backup_usb/releases/tag/v1.1.2
[1.1.1]: https://github.com/foundata/proxmox-pve_backup_usb/releases/tag/v1.1.1
[1.1.0]: https://github.com/foundata/proxmox-pve_backup_usb/releases/tag/v1.1.0
[1.0.1]: https://github.com/foundata/proxmox-pve_backup_usb/releases/tag/v1.0.1
[1.0.0]: https://github.com/foundata/proxmox-pve_backup_usb/releases/tag/v1.0.0
