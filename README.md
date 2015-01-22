# provisioning

## Overview

provisioning is a collection of scripts that automate the application of system configuration.

## Recipes

### New laptop install

  1. Set **SATA Mode** in the BIOS to **AHCI**
  2. Download and execute the simple provisioning script:
```bash
$ wget --quiet "https://raw.githubusercontent.com/sjwood/provisioning/master/simple_mbr_partitioning.sh"
$ chmod u+x simple_mbr_partitioning.sh
$ ./simple_mbr_partitioning.sh
```
  3. Install operating system (probably some flavour of [Debian][1])...
  4. Download and execute the SSD optimisations script (if appropriate):
```bash
$ wget --quiet "https://raw.githubusercontent.com/sjwood/provisioning/master/ssd_optimisations.sh"
$ chmod u+x ssd_optimisations.sh
$ ./ssd_optimisations.sh
```

## License

provisioning is released under the [Apache 2.0 license][2]

  [1]: https://www.debian.org
  [2]: http://opensource.org/licenses/Apache-2.0

