#!/bin/bash

set -e

ssh_key="${PT_key%$'\n'}"
key_name="${ssh_key##* }"

if [ -z "$key_name" ] ; then
    key_name='deploy key'
fi

project_id=$( gitlab -o json project list | jq '.[] | select(.path_with_namespace == "puppet/control") | .id' )
project_key=$( gitlab -o json project-key list --project-id "$project_id"  | jq '.[] | select(.key == "'"$ssh_key"'")' )

if [ -z "$project_key" ] ; then
    gitlab project-key create \
        --project-id "$project_id" \
        --title "$key_name" \
        --key "$ssh_key"
fi
