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
    local required_tools=("lsblk" "cut" "cat" "blkid" "grep" "sed" "awk")

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

function ensure_single_argument_provided() {
    local argument_count=$#
    if [ $argument_count -ne 1 ]
    then
        echo "This script expects a single argument." 1>&2
        exit 1
    fi
}

function ensure_argument_is_block_device() {
    local block_device="$1"
    if [ ! -b "$block_device" ]
    then
        echo "The script argument must be an existent block device." 1>&2
        exit 1
    fi
}

function ensure_block_device_is_an_ide_or_scsi_disk() {
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
            echo "The script argument must be an IDE or SCSI disk device." 1>&2
            exit 1
        fi
    fi
}
function ensure_block_device_is_an_ssd() {
    local block_device="$1"

    local block_device_identifier=$(lsblk --noheadings --nodeps --raw --output KNAME "$block_device")

    local is_rotational=$(cat "/sys/block/$block_device_identifier/queue/rotational")

    if [ "$is_rotational" == "1" ]
    then
        echo "The script argument must be an SSD disk device." 1>&2
        exit 1
    fi
}

function reduce_writes_on_ext4_partitions_with_noatime() {
    local block_device="$1"
    local partition_type="ext4"
    local option="noatime"
    __set_option_on_partition_types "$block_device" "$partition_type" "$option"
}

function reduce_chance_of_swapping_to_disk() {
    local swappiness=$(cat /proc/sys/vm/swappiness)

    if [ "$swappiness" != "0" ]
    then
        local is_swappiness_setting_missing
        cat /etc/sysctl.conf | grep vm.swappiness > /dev/null
        is_swappiness_setting_missing="$?"

        local swappiness_setting="vm.swappiness = 0"

        if [ "$is_swappiness_setting_missing" == "1" ]
        then
            echo "$swappiness_setting" >> /etc/sysctl.conf
        else
            sed -i "s/^vm.swappiness = .*/$swappiness_setting/" /etc/sysctl.conf
        fi

        sysctl vm.swappiness=0 > /dev/null
    fi
}

function change_scheduler_to_deadline() {
    local block_device="$1"

    local block_device_identifier=$(lsblk --noheadings --nodeps --raw --output KNAME "$block_device")

    local is_not_deadline
    cat "/sys/block/$block_device_identifier/queue/scheduler" | grep "\[deadline\]" > /dev/null
    is_not_deadline="$?"

    if [ "$is_not_deadline" == "1" ]
    then
        echo "deadline" > "/sys/block/$block_device_identifier/queue/scheduler"
    fi
}

function enable_trim_on_ext4_partitions() {
    local block_device="$1"
    local partition_type="ext4"
    local option="discard"
    __set_option_on_partition_types "$block_device" "$partition_type" "$option"
}

function __set_option_on_partition_types() {
    local block_device="$1"
    local partition_type="$2"
    local option="$3"

    local partitions=($(blkid -t TYPE="$partition_type" -o device))

    local partition
    for partition in ${partitions[@]}
    do
        local partition_uuid=$(blkid "$partition" -s UUID -o value)

        local fstab_line_number=$(cat /etc/fstab | grep -n "UUID=$partition_uuid" | cut --delimiter=: --fields=1)

        local existing_options=$(sed $fstab_line_number'!d' /etc/fstab | awk '{ print $4; }')

        local is_option_missing
        echo $existing_options | grep "$option" > /dev/null
        is_option_missing="$?"

        if [ "$is_option_missing" == "1" ]
        then
            local option_delimiter=","
            if [ -z "$existing_options" ]
            then
                option_delimiter=""
            fi

            local new_options="$existing_options$option_delimiter$option"

            sed -i -e $fstab_line_number"s/"$existing_options"/"$new_options"/" /etc/fstab

            mount -o remount "$partition"
        fi
    done
}

ensure_tooling_available
ensure_running_as_root
ensure_single_argument_provided "$@"
ensure_argument_is_block_device "$1"
ensure_block_device_is_an_ide_or_scsi_disk "$1"
ensure_block_device_is_an_ssd "$1"
reduce_writes_on_ext4_partitions_with_noatime "$1"
reduce_chance_of_swapping_to_disk
change_scheduler_to_deadline "$1"
enable_trim_on_ext4_partitions "$1"

echo "TODO - complete"

exit 1


