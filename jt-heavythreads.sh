#!/usr/bin/env bash

. "`dirname $0`/init.bash"

requirePidAndApptype "${@}"

ensureJavaProcessUser "$JAVA_PID"

if [ "$OS" = "Linux" ]; then
    top10_java_pids=`top -H -b -n 1 -p $JAVA_PID | grep java | head -10 | awk '{ print $1 }'`
elif [ "$OS" = "SunOS" ]; then
    top10_java_pids=`prstat -L -p $JAVA_PID -n 10 1 1 | grep java | awk '{ print $NF }' | cut -d'/' -f 2`
else
    echo "Unsupported OS: ${OS}"
    exit 1
fi

thread_dump=$(createThreadDump)
[ "$?" != "0" ] && ( echo "Creating thread dump failed: ${thread_dump}"; exit 1; )


# iterate over pids
for p in $top10_java_pids; do 
    # need hex value of native thread pid
    hex_p=`printf "%x" $p`

    # get relevant thread from thread dump, including stack
    cat "$thread_dump" | awk -v hex_pid_pattern=".*nid=0x${hex_p} .*" \
         'BEGIN { RS = ""; FS = "\n" } $0 ~ hex_pid_pattern { print $0 , "\n"}'
done

rm "$thread_dump"
