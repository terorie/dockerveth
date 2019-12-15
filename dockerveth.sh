#!/bin/sh

# Copyright (c) 2017 Micah Culpepper
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


#####################
# DECLARE CONSTANTS #
#####################

NL='
'

####################
# DEFINE FUNCTIONS #
####################

usage () {
    printf %s \
"dockerveth.sh - Show which docker containers are attached to which
\`veth\` interfaces.

Usage: dockerveth.sh [DOCKER PS OPTIONS] | [-h, --help]

Options:
    DOCKER PS OPTIONS   Pass any valid \`docker ps\` flags. Do not pass
                        a '--format' flag.
    -h, --help          Show this help and exit.

Output:
    If stdout is not a tty, column headers are omitted.
"
}

get_container_data () {
    # Get data about the running containers. Accepts arbitrary arguments, so you can pass
    # a filter to `docker ps` if desired.
    # Input: `docker ps` arguments (optional)
    # Output: A multi-line string where each line contains the container id, followed by
    # a space, and then any friendly names.
    docker ps --format '{{.ID}} {{.Names}}' "$@"
}

get_veth () {
    # Get the host veth interface attached to a container.
    # Input: docker container ID; also needs $dockerveth__addrs
    # Output: the veth name, like "veth6638cfa"
    c_if_indices=$(get_container_if_indices "$1")
    full_len="${#dockerveth__addrs}"
    veth="not_found"
    for i in $c_if_indices; do
        match="${dockerveth__addrs%%@if${i}:*}"
        if [ "${#match}" = "${full_len}" ]; then
            continue
        else
            b="${match##*${NL}}"
            veth="${b#* }"
            break
        fi
    done
    printf "${veth}"
}

get_container_if_indices () {
    # Get the index number of a docker container's veth interfaces (typically eth0)
    # Input: the container ID
    # Output: The index number(s), like "42\n44\n"
    netns=$(get_netns "$1")
    ils=$(ip netns exec $netns ip link show type veth)
    indices=""
    for line in $ils; do
        m1="${line%%:*}"
        m2="${line%% *}"
        if [ "${m1}:" = "$m2" ]; then
            indices="${indices}${m1}${NL}"
        fi
    done
    printf "${indices}"
}

get_netns () {
    # Make a docker container's networking info available to `ip netns`
    # Input: the container's PID
    # Output: namespace ID
    # If the Docker networking namespaces are not already mounted,
    # performs the set-up so that `ip netns` commands can access
    # the target container's namespace.
    if [ ! -d /var/run/netns ]; then
        mkdir -p /var/run/netns
    fi
    docker_netns_path=$(docker inspect --format='{{.NetworkSettings.SandboxKey}}' "${1}")
    netns_id=$(basename ${docker_netns_path})
    target_netns_path="/var/run/netns/${netns_id}"
    if [ ! -f "${target_netns_path}" ]; then
        ln -sf "${docker_netns_path}" "${target_netns_path}"
    fi
    printf "${netns_id}"
}

get_pid () {
    # Get the PID of a docker container
    # Input: the container ID
    # Output: The PID, like "2499"
    docker inspect --format '{{.State.Pid}}' "$1"
}

make_row () {
    # Produce a table row for output
    # Input:
    #     1 - The container ID
    #     2 - The container's friendly name
    # Output: A row of data, like "1e8656e195ba	veth1ce04be	thirsty_meitner"
    id="${1}"
    name="${2}"
    netns=$(get_netns "$id")
    veth=$(get_veth "$id")
    printf "${id}\t${veth}\t${netns}\t${name}"
}

make_table () {
    # Produce a table for output
    # Input: raw data rows, like `c26682fe4545 friendly-name`
    # Output: A multi-line string consisting of rows from `make_row`. Does not
    # contain table column headers.
    for i in $@; do
        id="${i%% *}"
        name="${i#* }"
        r=$(make_row "$id" "$name")
        printf "${r}\n"
    done
}


######################
# PARSE COMMAND LINE #
######################

case "$1" in
    -h|--help)
    usage
    exit 0
    ;;
    *)
    ;;
esac


##################
# EXECUTE SCRIPT #
##################

set -e
container_data=$(get_container_data "$@")
dockerveth__addrs="$(ip address show)"
table=$(IFS="$NL"; make_table $container_data)
printf "CONTAINER ID\tVETH\tNETNS\tNAMES\n"
printf "${table}\n"
