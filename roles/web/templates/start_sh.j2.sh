#!/bin/bash

function numberOfDockerContainers () {
    local nr
    nr=$(docker ps | wc -l)
    echo "$nr"
}

_NR_CONTAINERS="$(numberOfDockerContainers)"

if [ "$_NR_CONTAINERS" -lt 1 ]
then
    echo "No containers running ... starting" | systemd-cat
    cd "{{ docker_base_path }}" || exit
    /usr/local/bin/docker-compose -f docker-compose.yml start
else
    echo "${_NR_CONTAINERS} containers running ... nothing to do" | systemd-cat
fi