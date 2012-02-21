#!/usr/bin/env bash 

. "`dirname $0`/init.bash"

requirePidAndApptype "${@}"

ensureJavaProcessUser "$JAVA_PID"

dump_file=$(createThreadDump)

if [ "$?" = "0" ]; then
    echo "Saved thread dump in ${dump_file}"
    exit 0
else
    echo "Creating thread dump failed"
    exit 1
fi
