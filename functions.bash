#!/usr/bin/env bash

function validateJavaPid() {
    local PID="$1"

    if ! echo "$PID" | grep -qE '^[0-9]+$'; then
        return 1; 
    fi

    if ! kill -0 $PID > /dev/null 2>&1; then
        return 1
    fi 

    return 0 
}

function requirePidAndApptype() {
    while getopts "p:a:" opt; do
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
            ?)
                echo "Usage: $0 -p [pid] -a [application type]"
                exit 1
        esac
    done

    if [[ -z "$APP_STDOUT_FILE" ]] || [[ -z "$APP_LOG" ]]; then
       echo "Usage: $0 -p [pid] -a [application type]"
       exit 1
    fi
}

function findJavaDir() {
    local BIN_PATH=$(ps -eo comm,args -p $JAVA_PID | grep java | awk '{ print $2 }')
    local JAVA_DIR=$(dirname "$BIN_PATH")
    echo "$JAVA_DIR"

    return 0
}

function findJavaBin() {
    local BIN="$1"
    local JAVA_DIR=$(findJavaDir)
    local JBIN_PATH="${JAVA_DIR}/${BIN}"

    if ! [ -f "$JBIN_PATH" ]; then
        echo "Not found: ${JBIN_PATH}"
        return 1
    elif ! [ -x "$JBIN_PATH" ]; then
        echo "Not executable: ${JBIN_PATH}"
        return 1
    else 
        echo "$JBIN_PATH"
        return 0 
    fi
}

function getCpuBits() {
    local OS=`uname`
    if [ "$OS" = "SunOS" ]; then
        if [ `isainfo -kv | grep '^64-bit'` ]; then
            echo 64
        else 
            echo 32
        fi
    elif [ "$OS" = "Linux" ]; then
        if [ `uname -m` = "x86_64" ]; then
            echo 64
        else
            echo 32
        fi
    fi

    return 0
}

function ensureJavaProcessUser() {
    local PID_RE="^[[:space:]]*$1"
    local CUR_UID=`id -u`   

    PROCESS_UID=$(ps -eo pid,uid,comm,args | grep $PID_RE | awk '{ print $2 }')

    if [ "$PROCESS_UID" != "$CUR_UID" ]; then
        echo "Script must run under the same user as the Java process"
        exit 1 
    fi
  
    return 0 
}

function extractLastDumpFromFile() {
    # could use some DRY cleanup, but works for now

    local DUMP_FILE="$1"

    if [ "$OS" = "SunOS" ]; then
        tail -r "$APP_STDOUT_FILE" | while read -t 30 line ; do
            echo "$line" | grep -q 'JNI global references'
            if [ "$?" = 0 ]; then
                record="1"
            fi

            if [ "$record" = "1" ]; then
                echo "$line" >> "${DUMP_FILE}.tmp"
            fi

            echo "$line" | grep -q 'Full thread dump'
            if [ "$?" = 0 ]; then
                break
            fi
        done
    else
        tac "$APP_STDOUT_FILE" | while read -t 30 line ; do
            echo "$line" | grep -q '^JNI global references'
            if [ "$?" = 0 ]; then
                record="1"
            fi

            if [ "$record" = "1" ]; then
                echo "$line" >> "${DUMP_FILE}.tmp"
            fi

            echo "$line" | grep -q '^Full thread dump'
            if [ "$?" = 0 ]; then
                break
            fi
        done
    fi
}

function createThreadDump() {
    local DUMP_FILE="/var/tmp/thread-dump-`date +%d%m%Y-%H%M%S`.tdump"
    
    # make a thread dump by sending a QUIT signal to the process
    kill -3 $JAVA_PID
    sleep 10 # give process some time to dump stack (kill returns directly)

    ! [ -f "$APP_STDOUT_FILE" ] && { echo "File is not a regular file: ${APP_STDOUT_FILE}"; return 1; }
    ! [ -r "$APP_STDOUT_FILE" ] && { echo "Cannot read: ${APP_STDOUT_FILE}"; return 1; }
    ! [ -w "/var/tmp" ] && { "Cannot write to /var/tmp"; return 1; }

    SAVEIFS=$IFS
    IFS=$(printf '\n\b')

    extractLastDumpFromFile $DUMP_FILE

    # fix those pesky html entities that appear in the thread dump for some reason
    perl -p -i -e "s/&quot;/\"/g" "${DUMP_FILE}.tmp"
    perl -p -i -e "s/&lt;/</g" "${DUMP_FILE}.tmp"
    perl -p -i -e "s/&gt;/>/g" "${DUMP_FILE}.tmp"

    
    if [ "$OS" = "SunOS" ]; then
        tail -r "${DUMP_FILE}.tmp" > $DUMP_FILE
    else
        tac "${DUMP_FILE}.tmp" > $DUMP_FILE
    fi
    rm "${DUMP_FILE}.tmp"

    IFS=$SAVEIFS

    logger "Java thread dump created for pid ${JAVA_PID}, saved in ${DUMP_FILE}"

    echo "${DUMP_FILE}"

    return $?
}

function createHeapDump() {
    JMAP_PATH=$(findJavaBin 'jmap')
    DUMP_FILE="/var/tmp/heap-dump-`date +%d%m%Y-%H%M%S`.hprof"
    JAVA_OPTS=""
    if [ `getCpuBits` = "64" ]; then
        $JAVA_OPTS="-J-d64"
    fi

    $JMAP_PATH $JAVA_OPTS -dump:format=b,file=$DUMP_FILE $JAVA_PID 
    res="$?"

    # probably want to log the result of this, as it will pause the JVM and create a huge file
    [ "$?" != "0" ] && logger "Failed to create heap dump for pid ${JAVA_PID}" || \
        logger "Java heap dump created for pid ${JAVA_PID}, saved in ${DUMP_FILE}"

    if [ "$res" != "0" ]; then
        return 1
    else
        echo "$DUMP_FILE"
        return 0 
    fi
}

function patternConf2Pattern() {
    local PATTERN=""

    SAVEIFS=$IFS
    IFS=$(echo -en "\n\b")

    conf=( $( cat "`dirname $0`/log_patterns.conf" ) )

    for (( i=0; i<${#conf[@]}; i++ )); do
        line="${conf[$i]}"
        if ! [[ "$line" =~ ^# ]]; then # ignore comment lines
            line=$(echo $line | sed 's/\./\\./g')
            if [[ $i -lt ${#conf[@]}-1 ]]; then
                PATTERN="${PATTERN}${line}\|"
            else
                PATTERN="${PATTERN}${line}"
            fi
        fi
    done
    echo "$PATTERN"

    IFS=$SAVEIFS
}

function inspectJavaLog() {
    local LOG=""
    if [[ -z "$1" ]]; then # if no argument is given, search on the process app log
        LOG="$APP_LOG"
    else
        LOG="$1"
    fi

    patternConf2Pattern

    local MAX_TAIL_LINES="5000"
    local SUSPICIOUS_PATTERNS=$(patternConf2Pattern)

    tail -$MAX_TAIL_LINES "$LOG" | grep -A 5 -B 1 $SUSPICIOUS_PATTERNS 
}

# Glassfish specific functions

function getGlassfishFile() {
    export REL_PATH="$1"

    if [ "$OS" = "Linux" ]; then
        local STDOUT_FILE=$(ps -o args -p $JAVA_PID | \
            perl -n -e '/com\.sun\.aas\.instanceRoot=(\S*)/ && print "$1/".$ENV{"REL_PATH"}')

    elif [ "$OS" = "SunOS" ]; then
        local STDOUT_FILE=$(pargs $JAVA_PID | \
            perl -n -e '/^argv\[[0-9]{1,5}\]:\s-Dcom\.sun\.aas\.instanceRoot=(\S*)/ && print "$1/".$ENV{"REL_PATH"}')

    else 
        echo "Unknown OS: ${OS}"
        exit 1
    fi

    [[ "$?" != "0" || "$STDOUT_FILE" = "" ]] && { echo "Error resolving Glassfish file: ${REL_PATH}"; return 1; }

    if ! [ -f "$STDOUT_FILE" ]; then
        echo "File does not exist: ${STDOUT_FILE}"
        return 1
    else 
        echo "$STDOUT_FILE"
        return 0
    fi
}

function getGlassfishStdoutFile() {
    getGlassfishFile 'logs/jvm.log'
}

function getGlassfishServerLog() {
    getGlassfishFile 'logs/server.log'
}

function setGlassfishEnv() {
    export APP_STDOUT_FILE=$(getGlassfishStdoutFile)
    [ "$?" != "0" ] && { echo "Error occurred: ${APP_STDOUT_FILE}"; exit 1; }

    export APP_LOG=$(getGlassfishServerLog)
    [ "$?" != "0" ] && { echo "Error occurred: ${APP_LOG}"; exit 1; }
}

# Tomcat specific functions 

function getTomcatFile() {
    export REL_PATH="$1"

    if [ "$OS" = "Linux" ]; then
        local STDOUT_FILE=$(ps -o args -p $JAVA_PID | \
            perl -n -e '/catalina\.base=(\S*)/ && print "$1/".$ENV{"REL_PATH"}')
    elif [ "$OS" = "SunOS" ]; then
        local STDOUT_FILE=$(pargs $JAVA_PID | \
            perl -n -e '/^argv\[[0-9]{1,5}\]:\s-Dcatalina\.base=(\S*)/ && print "$1/".$ENV{"REL_PATH"}')
    else 
        echo "Unknown OS: ${OS}"
        exit 1
    fi


    [[ "$?" != "0" || "$STDOUT_FILE" = "" ]] && { echo "Error resolving Tomcat file: ${REL_PATH}"; return 1; }

    if ! [ -f "$STDOUT_FILE" ]; then
        echo "File does not exist: ${STDOUT_FILE}"
        return 1
    else 
        echo "$STDOUT_FILE"
        return 0
    fi
}

function getTomcatStdoutFile() {
    getTomcatFile 'logs/catalina.out'
}

function getTomcatServerLog() {
    getTomcatFile 'logs/catalina.out'
}

function setTomcatEnv() {
    export APP_STDOUT_FILE=$(getTomcatStdoutFile)
    [ "$?" != "0" ] && { echo "Error occurred: ${APP_STDOUT_FILE}"; exit 1; }

    export APP_LOG=$(getGlassfishServerLog)
    [ "$?" != "0" ] && { echo "Error occurred: ${APP_LOG}"; exit 1; }
}
