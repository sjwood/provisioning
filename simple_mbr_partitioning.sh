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

function _ensure_tooling_available() {
    local required_tools=("lsblk" "cut" "fdisk" "dmidecode" "grep" "awk" "mkswap" "mkfs.ext4")

    local are_tools_missing=0

    local tool
    for tool in ${required_tools[@]}
    do
        local tool_path
        tool_path=$(which "$tool")

        if [ $? -ne 0 ]
        then
            echo "$tool is required by this script but is not available."
            are_tools_missing=1
        fi
    done

    if [ "$are_tools_missing" -eq "1" ]
    then
        exit 1
    fi
}

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

    local block_device_major_number=$(lsblk --noheadings --nodeps --raw --output MAJ:MIN "$1" | cut --delimiter=: --fields=1)
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

function _type_y_to_continue() {
    local block_device="$1"

    echo -n "This will unrecoverably repartition hard disk device ""$block_device"". Are you sure (Y/N)?"

    local confirmation
    while read -r -n 1 confirmation
    do
        if [ "${confirmation,,}" = "n" ]
        then
            echo -e "\nConfirmation declined."
            exit 1
        elif [ "${confirmation,,}" = "y" ]
        then
            echo -e ""
            break
        fi
    done
}

function _create_new_mbr_partition_table() {
    local block_device="$1"

    echo -e "o\nw" | fdisk "$block_device" &> /dev/null
}

function _create_swap_partition() {
    local block_device="$1"

    # calculate the size of the current installed memory
    local dimm_sizes=($(dmidecode --type memory | grep Size | awk '{ print $2; }'))
    local dimm_units=($(dmidecode --type memory | grep Size | awk '{ print $3; }'))
    local dimm_count=${#dimm_sizes[@]}
    local total_memory_in_bytes=0
    for i in $(seq 0 $(($dimm_count-1)))
    do
        local size=${dimm_sizes[$i]}
        local units=${dimm_units[$i]}
        local units_in_bytes=0
        case "$units" in
            "MB")
                units_in_bytes=$((1024*1024))
                ;;
            *)
                echo "Unrecognised Memory unit $units"
                exit 1
        esac
        local size_in_bytes=$(($size*$units_in_bytes))
        let total_memory_in_bytes+=$size_in_bytes
    done

    # calculate swap partition as twice the size of the RAM
    local swap_size_in_sectors=$(($total_memory_in_bytes*2/512))
    local last_swap_sector=$(($swap_size_in_sectors-1))

    local partition_number=1
    echo -e "n\np\n$partition_number\n\n+$last_swap_sector\nt\n82\nw" | fdisk "$block_device" &> /dev/null

    mkswap -L swap "$block_device$partition_number" &> /dev/null
}

function _create_main_partition() {
    local block_device="$1"

    local partition_number=2
    echo -e "n\np\n$partition_number\n\n\nt\n$partition_number\n83\nw" | fdisk "$block_device" &> /dev/null

    mkfs.ext4 -L system "$block_device$partition_number" &> /dev/null
}

_ensure_tooling_available
_ensure_running_as_root
_ensure_single_argument_provided "$@"
_ensure_argument_is_block_device "$1"
_ensure_block_device_is_an_ide_or_scsi_disk "$1"
_type_y_to_continue "$1"
_create_new_mbr_partition_table "$1"
_create_swap_partition "$1"
_create_main_partition "$1"

echo "Finished."

exit 0
