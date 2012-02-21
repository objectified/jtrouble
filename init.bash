#!/usr/bin/env bash

. "`dirname $0`/functions.bash"

OS=`uname`
[ "$OS" = "SunOS" ] && export PATH="/usr/xpg4/bin:$PATH";

