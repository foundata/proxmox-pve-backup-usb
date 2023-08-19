# Development

This file provides additional information for maintainers and contributors.


## Testing

Nothing special or automated yet. Therefore just some hints for manual testing:

* Run the script with invalid values.
* Run the script with technically valid values but PVE IDs of non-existing machines.
* Run the script with and without connected USB drive.
* Try to interrupt the backup process by sending signals, CTRL+C and so on.
* Try to run multiple instances of the script in parallel (should not work).


## Releases

1. Do proper [Testing](#testing). Continue only if everything is fine.
2. Determine the next version number. This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
3. Update the [`CHANGELOG.md`](./CHANGELOG.md). Insert a section for the new release. Do not forget the comparison link at the end of the file.
4. If everything is fine: commit the changes, tag the release and push:
   ```console
   git tag v<version> <commit> -m "version <version>"
   git show v<version>
   git push origin main --follow-tags
   ```
   If something minor went wrong (like missing `CHANGELOG.md` update), delete the tag and start over:
   ```console
   git tag -d v<version>                 # delete the old tag locally
   git push origin :refs/tags/v<version> # delete the old tag remotely
   ```
   This is *only* possible if there was no [GitHub release](https://github.com/foundata/proxmox-pve_backup_usb/releases/). Use a new patch version number otherwise.
5. Use [GitHub's release feature](https://github.com/foundata/proxmox-pve_backup_usb/releases/new), select the tag you pushed and create a new release:
   * Use `v<version>` as title
   * A description is optional. In doubt, use `See CHANGELOG.md for more information about this release.`
6. Check if the GitHub API delivers the correct version as `latest`:
   ```console
   curl -s -L https://api.github.com/repos/foundata/proxmox-pve_backup_usb/releases/latest | jq -r '.tag_name' | sed -e 's/^v//g'
   ```


## Miscellaneous

### Encoding

* Use UTF-8 encoding with `LF` (Line Feed `\n`) line endings *without* [BOM](https://en.wikipedia.org/wiki/Byte_order_mark) for all files.
