# provisioning

## Overview

[provisioning][1] is a collection of scripts that automate the application of system configuration.

## Recipes

### New laptop install

  1. Set **SATA Mode** in the BIOS to **AHCI**
  2. Download and execute the provisioning script:
```bash
$ wget --quiet "https://raw.githubusercontent.com/sjwood/provisioning/master/simple_mbr_partitioning.sh"
$ chmod u+x simple_mbr_partitioning.sh
$ sudo ./simple_mbr_partitioning.sh /dev/sda
```
  3. Install operating system (probably some flavour of [Debian][2])...
  4. Download and execute the SSD optimisations script (if appropriate):
```bash
$ wget --quiet "https://raw.githubusercontent.com/sjwood/provisioning/master/ssd_optimisations.sh"
$ chmod u+x ssd_optimisations.sh
$ sudo ./ssd_optimisations.sh /dev/sda
```

### External USB disk

  1. Plugin device
  2. Download and execute the provisioning script:
```bash
$ wget --quiet "https://raw.githubusercontent.com/sjwood/provisioning/master/usb_disk_preparation.sh"
$ chmod u+x usb_disk_preparation.sh
$ sudo ./usb_disk_preparation.sh /dev/sdb backup
```

## License

[provisioning][1] is released under the [Apache 2.0 license][3]

  [1]: https://github.com/sjwood/provisioning
  [2]: https://www.debian.org
  [3]: http://opensource.org/licenses/Apache-2.0

