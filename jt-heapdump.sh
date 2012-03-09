#!/usr/bin/env bash

. "`dirname $0`/init.bash"

requirePidAndApptype "${@}"

ensureJavaProcessUser "$JAVA_PID"

dump_file=$(createHeapDump)

echo "${dump_file}"

if [ "$?" = "0" ]; then
    exit 0
else
    echo "Creating heap dump failed"
    exit 1
fi
