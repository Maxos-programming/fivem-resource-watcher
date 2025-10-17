#!/bin/sh -l

beginswith() { case "$2" in "$1"*) true ;; *) false ;; esac }

icecon_command() {
    icecon --command "$1" "${SERVER_IP}:${SERVER_PORT}" "${RCON_PASSWORD}"
}

get_player_count() {
    response=$(curl -s "${SERVER_IP}:${SERVER_PORT}/players.json")
    player_count=$(echo "$response" | jq 'length')
    echo "$player_count"
}

exists_in_list() {
    # usage: exists_in_list "item" "list"  , where list may be space- or comma-separated
    item=$1
    list=$2
    # normalize commas to spaces
    list2=$(echo "$list" | tr ',' ' ')
    for i in $list2; do
        if [ "$i" = "$item" ]; then
            return 0
        fi
    done
    return 1
}

RESTART_INDIVIDUAL_RESOURCES=$1
SERVER_IP=$2
SERVER_PORT=$3
RCON_PASSWORD=$4
RESOURCES_FOLDER=$5
RESTART_SERVER_WHEN_0_PLAYERS=$6
IGNORED_RESOURCES=$7
RESOURCES_NEED_RESTART=$8

git config --global --add safe.directory /github/workspace

if [ "${GITHUB_BASE_REF}" ]; then
    # Pull Request
    git fetch origin "${GITHUB_BASE_REF}" --depth=1
    export DIFF=$(git diff --name-only "origin/${GITHUB_BASE_REF}" "${GITHUB_SHA}")
    echo "Diff between origin/${GITHUB_BASE_REF} and ${GITHUB_SHA}"
else
    # Push
    git fetch origin "${GITHUB_EVENT_BEFORE}" --depth=1
    export DIFF=$(git diff --name-status "${GITHUB_EVENT_BEFORE}" "${GITHUB_SHA}")
    echo "Diff between ${GITHUB_EVENT_BEFORE} and ${GITHUB_SHA}"
fi

# collect resource names into a temporary file, then dedupe
tmpfile=$(mktemp) || tmpfile="/tmp/entrypoint_resources.$$"

# Safe iteration over lines in DIFF
printf "%s\n" "${DIFF}" | while IFS= read -r changed; do
    # original script removed first two chars for name-status entries; keep the behavior
    changed=${changed#??}
    if beginswith "${RESOURCES_FOLDER}" "${changed}"; then
        filtered=${changed##*]/} # Remove subfolders (keeps last part after ']/' if present)
        filtered=${filtered%%/*} # Remove filename and get the folder which corresponds to the resource name
        if [ -n "${filtered}" ]; then
            printf "%s\n" "${filtered}" >> "${tmpfile}"
        fi
    fi
done

# create a space-separated unique list
if [ -f "${tmpfile}" ]; then
    resources_to_restart_list=$(sort -u "${tmpfile}" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    rm -f "${tmpfile}"
else
    resources_to_restart_list=""
fi

echo "rss: ${resources_to_restart_list}"

if [ -z "${resources_to_restart_list}" ]; then
    echo "Nothing to restart"
else
    player_count=$(get_player_count)
    if [ "${RESTART_SERVER_WHEN_0_PLAYERS}" = true ] && [ "${player_count}" -eq 0 ]; then
        echo "Will restart the whole server due to 0 players"
        icecon_command "quit"
    elif [ "${RESTART_INDIVIDUAL_RESOURCES}" = true ]; then
        echo "Will restart individual resources"
        for resource in ${resources_to_restart_list}; do
            if exists_in_list "${resource}" "${IGNORED_RESOURCES}"; then
                echo "Ignoring restart of the resource ${resource}"
            else if exists_in_list "${resource}" "${RESOURCES_NEED_RESTART}"; then
                icecon_command "quit"
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
