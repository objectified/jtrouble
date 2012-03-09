# JTrouble
## A bundle of shell scripts for troubleshooting JEE application servers

### Introduction
JTrouble was created to serve the need for operations teams to investigate problems that occur inside running Java processes. It can be used to dig into problems yourself, or record information that can be passed on to development teams to do further investigation of the problem. It aims to work on both Linux and Solaris. Currently the supported application servers/containers are Glassfish and Tomcat, although it should be fairly trivial to add support for other application containers.

### Features
JTrouble includes the following tools:
#### jt-threaddump.sh
Creates a thread dump of the running process. It does not use the jstack tool provided by the JVM, because of very unpredictable behaviour since JVM 1.6u[23-24]. Instead it sends a QUIT signal to the Java process, and fetches the last thread dump from where the process sends its stdout (which differs per application server). It stores the thread dump on disk for further investigation.

#### jt-heapdump.sh
Creates a heap dump (a snapshot of all objects in memory) of the currently running Java process. This can become quite large depending on how big you allow your heap to grow, so make sure you have enough disk space before running this script. It uses the JVM provided JMap tool under the hood. It takes multi JVM environments in account, as it uses the JMap binary that is located inside the JRE that the container runs on.

#### jt-heavythreads.sh
Lists the top 10 Java threads by CPU usage, including their position in the stack. Under the hood, it uses the Unix top utility to list the heaviest threads, creates a thread dump, takes the hex value of the thread ID and relates this to the thread dump to get to the stack position. The -k parameter can be used to optionally keep the thread dump that was created while running this script. 

#### jt-loginspect.sh
Inspects the standard application server log file for dangerous patterns. It builds a grep regular expression based on the log patterns in log_patterns.conf and searches the last 5000 lines of the log file for this regular expression.

#### jt-loginspect-file.sh
Same as jt-loginspect.sh, except this script can search inside an arbitrary log file. Unlike all the other scripts, it does not expect a pid and an application type.

### Usage
Most JTrouble scripts (except for jt-loginspect-file.sh) can be called like:
```
    ./jt-threaddump.sh -p [pid] -a [application type]
```
.. where [pid] is the pid of the Java process you want to use, and [application type] refers to the type of container you are using (either "tomcat" or "glassfish" currently). The reasons for this information to be present is as follows:
- the pid is needed as there can be many JVM processes running on a machine, each with their own characteristics
- the application type is needed so that the scripts can figure out sensible defaults (where is the main log file, where does stdout go, etc.)

jt-loginspect-file.sh can simply be called as follows:
```
    ./jt-loginspect-file.sh /path/to/your/logfile.log
```
