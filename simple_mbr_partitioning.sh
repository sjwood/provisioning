#!/usr/bin/env bash

# Copyright 2015 sjwood
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

function _ensure_running_as_root() {
    if [ "$EUID" -ne 0 ]
    then
        echo "This script must be run as root." 1>&2
        exit 1
    fi
}

function _ensure_single_argument_provided() {
    local argument_count=$#
    if [ $argument_count -ne 1 ]
    then
        echo "This script expects a single argument." 1>&2
        exit 1
    fi
}

function _ensure_argument_is_block_device() {
    local block_device="$1"
    if [ ! -b "$block_device" ]
    then
        echo "The script argument must be an existent block device." 1>&2
        exit 1
    fi
}

function _ensure_block_device_is_an_ide_or_scsi_disk() {
    local block_device="$1"

    local block_device_type=$(lsblk --noheadings --nodeps --raw "$1" --output TYPE)
    if [ "$block_device_type" != "disk" ]
    then
        echo "The script argument must be an IDE or SCSI disk." 1>&2
        exit 1
    fi

    local block_device_major_number=$(lsblk --noheadings --nodeps --output MAJ:MIN "$1" | tr --delete ' ' | cut --delimiter=: --fields=1)
    # MAJ=3 is an IDE disk
    if [ "$block_device_major_number" != "3" ]
    then
        # MAJ=8 is a SCSI (or SATA) disk
        if [ "$block_device_major_number" != "8" ]
        then
            echo "The script argument must be an IDE or SCSI disk." 1>&2
            exit 1
        fi
    fi
}

_ensure_running_as_root
_ensure_single_argument_provided "$@"
_ensure_argument_is_block_device "$1"
_ensure_block_device_is_an_ide_or_scsi_disk "$1"

echo "TODO - incomplete"

exit 0


