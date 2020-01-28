#!/bin/bash

SERVER_FILE_NAME="./server_list.txt"
USER_NAME='user'
password='*******'

>./output.txt
while read -r line;
do
    time="$(sshpass -p "$password" ssh -q -n -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$USER_NAME"@"$line" "date")"
    [[ $? -eq 0 ]] && echo "$line": "$time" >> "output.txt"
done < "$SERVER_FILE_NAME"