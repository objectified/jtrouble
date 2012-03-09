#!/usr/bin/env bash

. "`dirname $0`/init.bash"

KEEP_THREAD_DUMP="0"

while getopts "p:a:k" opt; do
    case $opt in
        p)
            export JAVA_PID="$OPTARG"
            validateJavaPid "$JAVA_PID"
            if [ "$?" != 0 ]; then
                echo "Invalid Java pid: ${JAVA_PID}"
                exit 1 
            fi
            ;;
        a)
            APP_TYPE="$OPTARG"
            case "$APP_TYPE" in
                "glassfish")
                    setGlassfishEnv
                    ;;
                "tomcat")
                    setTomcatEnv
                    ;;
                *)
                    echo "Unknown application type: ${APP_TYPE}";
                    exit 1
                    ;;
            esac
            ;;
        k)
            KEEP_THREAD_DUMP="1"
            ;;

        ?)
            echo "Usage: $0 -p [pid] -a [application type]"
            exit 1
    esac
done

if [[ -z "$APP_STDOUT_FILE" ]] || [[ -z "$APP_LOG" ]]; then
    echo "Usage: $0 -p [pid] -a [application type] [-k]"
    echo "-k can optionally be used to keep the thread dump this script creates"
    
    exit 1
fi


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

[ "${KEEP_THREAD_DUMP}" != "1" ] && rm "$thread_dump" || echo "Thread dump saved in ${thread_dump}"
