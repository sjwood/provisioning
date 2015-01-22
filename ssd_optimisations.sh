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
    local required_tools=("lsblk" "cut" "cat" "grep" "sed" "rm" "awk" "mktemp" "wget" "tar" "file" "find" "mv" "ln" "hdparm" "tr" "funzip" "innoextract" "df" "wc" "blkid" "mount")

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

function disable_trim_cron_job() {
    if [ -f /etc/cron.weekly/fstrim ]
    then
        rm /etc/cron.weekly/fstrim
    fi
}

function install_magician_if_device_is_samsung_ssd() {
    local block_device="$1"

    local ssd_model=$(lsblk --noheadings --nodeps --raw --output MODEL "$block_device" | cut --delimiter=' ' --fields=1 | awk '{ print tolower($0); }')

    if [ "$ssd_model" == "samsung" ]
    then
        local magician_path
        magician_path=$(which magician)

        if [ $? -ne 0 ]
        then
            local temporary_folder=$(mktemp --directory)

            wget --quiet --output-document=- "http://www.samsung.com/global/business/semiconductor/minisite/SSD/downloads/software/samsung_magician_dc-v1.0_rtm_p2.tar.gz" | tar --extract --gzip --no-same-owner --directory="$temporary_folder"

            local bash_executable=$(which bash)

            local bash_executable_type=$(file --brief "$bash_executable" | cut --delimiter=, --fields=1)

            local magician_executables=($(find "$temporary_folder" -type f))

            local magician_executable
            for magician_executable in ${magician_executables[@]}
            do
                local magician_executable_type=$(file --brief "$magician_executable" | cut --delimiter=, --fields=1)

                if [ "$magician_executable_type" == "$bash_executable_type" ]
                then
                    local target_magician_directory="/usr/local/sbin"
                    local target_magician_executable_name="magician_dc-v1.0"
                    local target_magician_symbolic_name="magician"

                    mv "$magician_executable" "$target_magician_directory/$target_magician_executable_name"
                    chmod 555 "$target_magician_directory/$target_magician_executable_name"

                    pushd "$target_magician_directory" > /dev/null

                    ln --symbolic "$target_magician_executable_name" "$target_magician_symbolic_name"

                    popd > /dev/null

                    break
                fi
            done

            rm -rf "$temporary_folder"
        fi
    fi
}

function configure_overprovisioning_if_device_is_samsung_ssd() {
    local block_device="$1"

    local ssd_model=$(lsblk --noheadings --nodeps --raw --output MODEL "$block_device" | cut --delimiter=' ' --fields=1 | awk '{ print tolower($0); }')

    if [ "$ssd_model" == "samsung" ]
    then
        local magician_path
        magician_path=$(which magician)

        if [ $? -eq 0 ]
        then
            local temporary_folder=$(mktemp --directory)

            pushd "$temporary_folder" > /dev/null

            local device_serial_number=$(hdparm -I "$block_device" | grep Serial\ Number: | sed "s/Serial\ Number://" | tr --delete [:space:])

            local magician_disk_number=$(magician --list | grep "$device_serial_number" | cut --delimiter=\| --fields=2 | sed "s/*//" | tr --delete [:space:])

            local recommended_overprovisioning=$(magician --disk "$magician_disk_number" --over-provision --query | grep "Recommended OP" | cut --delimiter=: --fields=2 | tr --delete [:space:])

            local current_overprovisioning=$(magician --disk "$magician_disk_number" --over-provision --query | grep "Current OP" | cut --delimiter=: --fields=2 | tr --delete [:space:])

            if [ "$current_overprovisioning" != "$recommended_overprovisioning" ]
            then
                magician --disk "$magician_disk_number" --over-provision --set > /dev/null
            fi

            popd > /dev/null

            rm -rf "$temporary_folder"
        fi
    fi
}

function install_secure_erase_bootable_iso_if_device_is_samsung_ssd() {
    local block_device="$1"

    local ssd_model=$(lsblk --noheadings --nodeps --raw --output MODEL "$block_device" | cut --delimiter=' ' --fields=1 | awk '{ print tolower($0); }')

    if [ "$ssd_model" == "samsung" ]
    then
        local grub_config_file="/boot/grub/grub.cfg"

        if [ -f "$grub_config_file" ]
        then
            local samsung_secure_erase_iso_full_path="/boot/iso/sece.iso"

            if [ ! -f "$samsung_secure_erase_iso_full_path" ]
            then
                local temporary_folder=$(mktemp --directory)

                local setup_file_path="$temporary_folder/setup.exe"

                wget --quiet --output-document=- "http://www.samsung.com/global/business/semiconductor/minisite/SSD/downloads/software/Samsung_Magician_Setup_v45.zip" | funzip > "$setup_file_path"

                local extracted_folder_path="$temporary_folder/extracted"

                mkdir --parents "$extracted_folder_path"
                innoextract --extract --silent --output-dir "$extracted_folder_path" "$setup_file_path"

                local samsung_secure_erase_iso_file_name=$(basename "$samsung_secure_erase_iso_full_path")

                local target_file=$(find "$extracted_folder_path" -type f -name "$samsung_secure_erase_iso_file_name")

                local samsung_secure_erase_iso_folder_path=$(dirname "$samsung_secure_erase_iso_full_path")
                mkdir --parents "$samsung_secure_erase_iso_folder_path"

                mv "$target_file" "$samsung_secure_erase_iso_full_path"
                chmod 444 "$samsung_secure_erase_iso_full_path"

                rm -rf "$temporary_folder"
            fi

            local custom_grub_file="/etc/grub.d/40_custom"

            local is_grub_entry_missing
            cat "$custom_grub_file" | grep "Samsung SSD Secure Erase Utility (v4.5) ISO" > /dev/null
            is_grub_entry_missing="$?"

            if [ "$is_grub_entry_missing" == "1" ]
            then
                local boot_block_device=$(df --output=source /boot | awk '{ if (NR!=1) { print $0;}; }')

                local boot_block_device_identifier=$(lsblk --noheadings --nodeps --raw --output KNAME "$boot_block_device")

                local boot_drive_letter=$(echo "$boot_block_device_identifier" | rev | cut -c2 | rev)

                local boot_drive_ascii_character_code=$(printf '%d' "'$boot_drive_letter")

                local boot_drive=$((boot_drive_ascii_character_code - 97))

                local boot_partition=$(echo "$boot_block_device_identifier" | rev | cut -c1 | rev)

                echo 'menuentry "Samsung SSD Secure Erase Utility (v4.5) ISO" {' >> "$custom_grub_file"
                echo -e '\tloopback loop (hd'"$boot_drive"','"$boot_partition"')"'"$samsung_secure_erase_iso_full_path"'"' >> "$custom_grub_file"
                echo -e '\tlinux16 (loop)/isolinux/memdisk' >> "$custom_grub_file"
                echo -e '\tinitrd16 (loop)/isolinux/btdsk.img' >> "$custom_grub_file"
                echo '}' >> "$custom_grub_file"
            fi

            update-grub 2> /dev/null
        fi
    fi
}

function reduce_writes_in_firefox_config() {
    local firefox_path
    firefox_path=$(which firefox)

    if [ $? -eq 0 ]
    then
        local firefox_prefs_line_count=$(wc -l /etc/firefox/syspref.js | cut --delimiter=' ' --fields 1)

        if [ "$firefox_prefs_line_count" == "0" ]
        then
            echo "//" >> /etc/firefox/syspref.js
        fi

        __add_preference_to_firefox_config "lockPref(\"browser.cache.disk.enable\", false)"

        __add_preference_to_firefox_config "lockPref(\"browser.cache.memory.enable\", true)"

        __add_preference_to_firefox_config "lockPref(\"browser.cache.memory.capacity\", 358400)"
    fi
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

function __add_preference_to_firefox_config() {
    local preference="$1"

    local is_preference_set
    cat /etc/firefox/syspref.js | grep "^$preference;" > /dev/null
    is_preference_set="$?"

    if [ "$is_preference_set" == "1" ]
    then
        echo "$preference;" >> /etc/firefox/syspref.js
    fi
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
disable_trim_cron_job
install_magician_if_device_is_samsung_ssd "$1"
configure_overprovisioning_if_device_is_samsung_ssd "$1"
install_secure_erase_bootable_iso_if_device_is_samsung_ssd "$1"
reduce_writes_in_firefox_config

echo "Finished."

exit 0


