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

function ensure_tooling_available() {
    local required_tools=("lsblk" "cut" "udevadm" "grep" "badblocks" "fdisk" "mkfs.ext4")

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

function ensure_running_as_root() {
    if [ "$EUID" -ne 0 ]
    then
        echo "This script must be run as root." 1>&2
        exit 1
    fi
}

function ensure_two_arguments_provided() {
    local argument_count=$#
    if [ $argument_count -ne 2 ]
    then
        echo "This script expects two arguments." 1>&2
        exit 1
    fi
}

function ensure_first_argument_is_block_device() {
    local block_device="$1"
    if [ ! -b "$block_device" ]
    then
        echo "The first script argument must be an existent block device." 1>&2
        exit 1
    fi
}

function ensure_first_argument_is_an_ide_or_scsi_disk() {
    local block_device="$1"

    local block_device_type=$(lsblk --noheadings --nodeps --raw "$1" --output TYPE)
    if [ "$block_device_type" != "disk" ]
    then
        echo "The first script argument must be an IDE or SCSI disk." 1>&2
        exit 1
    fi

    local block_device_major_number=$(lsblk --noheadings --nodeps --raw --output MAJ:MIN "$1" | cut --delimiter=: --fields=1)
    # MAJ=3 is an IDE disk
    if [ "$block_device_major_number" != "3" ]
    then
        # MAJ=8 is a SCSI (or SATA) disk
        if [ "$block_device_major_number" != "8" ]
        then
            echo "The first script argument must be an IDE or SCSI disk device." 1>&2
            exit 1
        fi
    fi
}

function ensure_first_argument_is_a_usb_disk() {
    local block_device="$1"

    local block_device_identifier=$(lsblk --noheadings --nodeps --raw --output KNAME "$block_device")

    udevadm info --query=all --path="/sys/block/$block_device_identifier" | grep ID_PATH=.*usb.* > /dev/null
    if [ $? -ne 0 ]
    then
        echo "The first script argument must be a USB disk device." 1>&2
        exit 1
    fi
}

function type_y_to_continue() {
    local block_device="$1"

    echo -n "This will destructively test and repartition USB disk device ""$block_device"". Are you sure (Y/N)?"

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

function test_block_device_for_bad_blocks() {
    local block_device="$1"

    badblocks -w -s -v -b 4096 "$block_device"

    if [ $? -ne 0 ]
    then
        echo "Device $block_device has bad blocks!" 1>&2
        exit 1
    fi
}

function create_new_mbr_partition_table() {
    local block_device="$1"

    echo -e "o\nw" | fdisk "$block_device" &> /dev/null
}

function create_data_partition() {
    local block_device="$1"
    local partition_number="$2"
    local partition_label="$3"

    echo -e "n\np\n$partition_number\n\n\nt\n83\nw" | fdisk "$block_device" &> /dev/null

    mkfs.ext4 -m0 -L "$partition_label" "$block_device$partition_number" &> /dev/null
}

ensure_tooling_available
ensure_running_as_root
ensure_two_arguments_provided "$@"
ensure_first_argument_is_block_device "$1"
ensure_first_argument_is_an_ide_or_scsi_disk "$1"
ensure_first_argument_is_a_usb_disk "$1"
type_y_to_continue "$1"
test_block_device_for_bad_blocks "$1"
create_new_mbr_partition_table "$1"
create_data_partition "$1" 1 "$2"

echo "Finished."

exit 0
