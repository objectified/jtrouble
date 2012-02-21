#!/usr/bin/env bash

. "`dirname $0`/init.bash"

requirePidAndApptype "${@}"

ensureJavaProcessUser "$JAVA_PID"

inspectJavaLog
