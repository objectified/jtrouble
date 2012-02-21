#!/usr/bin/env bash

. "`dirname $0`/init.bash"

if ! [ -f "$1" ]; then
    echo "File does not exist: $1"
else
    inspectJavaLog "$1"
fi
