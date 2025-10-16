#!/bin/sh -l

beginswith() { case $2 in "$1"*) true ;; *) false ;; esac }

icecon_command() {
    icecon --command "$1" "${SERVER_IP}:${SERVER_PORT}" "${RCON_PASSWORD}"
}

get_player_count() {
    response=$(curl -s "${SERVER_IP}:${SERVER_PORT}/players.json")
    player_count=$(echo "$response" | jq 'length')
    echo "$player_count"
}

RESTART_INDIVIDUAL_RESOURCES=$1
SERVER_IP=$2
SERVER_PORT=$3
RCON_PASSWORD=$4
RESOURCES_FOLDER=$5
RESTART_SERVER_WHEN_0_PLAYERS=$6
IGNORED_RESOURCES=$7

git config --global --add safe.directory /github/workspace

if [ ${GITHUB_BASE_REF} ]; then
    # Pull Request
    git fetch origin ${GITHUB_BASE_REF} --depth=1
    export DIFF=$(git diff --name-only origin/${GITHUB_BASE_REF} ${GITHUB_SHA})
    echo "Diff between origin/${GITHUB_BASE_REF} and ${GITHUB_SHA}"
else
    # Push
    git fetch origin ${GITHUB_EVENT_BEFORE} --depth=1
    export DIFF=$(git diff --name-status ${GITHUB_EVENT_BEFORE} ${GITHUB_SHA})
    echo "Diff between ${GITHUB_EVENT_BEFORE} and ${GITHUB_SHA}"
fi

resources_to_restart_temp=

IFS=$'\n'
for changed in $DIFF; do
    changed=${changed#??}
    if beginswith "${RESOURCES_FOLDER}" "${changed}"; then
        filtered=${changed##*]/} # Remove subfolders
        filtered=${filtered%%/*} # Remove filename and get the folder which corresponds to the resource name
        resources_to_restart_temp=("${resources_to_restart_temp[@]}" $filtered) # push element

    fi
done
unset IFS

declare -A resources_to_restart
for k in $resources_to_restart_temp ; do resources_to_restart[$k]=1 ; done


echo "rss: ${resources_to_restart}"


if [ -z "$resources_to_restart" ]; then
    echo "Nothing to restart"
else
    player_count=$(get_player_count)
    if [ "$RESTART_SERVER_WHEN_0_PLAYERS" = true ] && [ "$player_count" -eq 0 ]; then
        echo "Will restart the whole server due to 0 players"
        icecon_command "quit"
    elif [ "$RESTART_INDIVIDUAL_RESOURCES" = true ]; then
        echo "Will restart individual resources"
        for resource in $resources_to_restart; do
            if exists_in_array "${resource}" "${IGNORED_RESOURCES}"; then
                echo "Ignoring restart of the resource ${resource}"
            else
                echo "Restarting ${resource}"
                icecon_command "ensure ${resource}"
            fi
        done
    else
        echo "Will restart the whole server"
        icecon_command "quit"
    fi
fi
