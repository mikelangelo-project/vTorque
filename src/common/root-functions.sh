#!/bin/bash
#
# Copyright 2016 HLRS, University of Stuttgart
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

#
#
# NOTE: source 'functions.sh' first !
#

set -o nounset;

#
# as first source the functions.sh
#
ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source $ABSOLUTE_PATH/functions.sh;


#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#



#---------------------------------------------------------
#
# Overrides _log function from functions.sh
#
# param1: logMsgType - DEBUG, TRACE, INFO, WARN, ERROR
# param2: msg
#
_log() {

  # disable 'set -x' in case it is enabled
  cachedBashOpts="$-";
  _unsetXFlag $cachedBashOpts;

  # check amount of params
  if [ $# -ne 3 ]; then
    logErrorMsg "Function '_log' called with '$#' arguments, '3' are expected.\nProvided params are: '$@'" 2;
  fi

  logLevel=$1;
  color=${COLORS[$logLevel]};
  logMsg=$2;
  printToSTDout=$3;

  # get caller's name (script file name or parent process if remote)
  processName="$(getCallerName)";

  # for shorter log level names, prepend the log message with a space to
  # have all messages starting at the same point, more convenient to read
  if [[ $logLevel =~ ^(WARN|INFO)$ ]]; then
    logMsg=" $logMsg";
  fi

  # log file exists ?
  if [ -z ${LOG_FILE-} ] \
       || [ ! -f "$LOG_FILE" ]; then
    # get dir
    logFileDir=$(dirname "$LOG_FILE");
    # ensure dir exists
    [ ! -d $logFileDir ] \
      && mkdir -p $logFileDir;
    # create log file
    touch "$LOG_FILE";
    # set correct owner
    chown $USERNAME:$USERNAME -R $(dirname "$LOG_FILE");
  fi

  # print log msg to job log file (may not exists during first cycles)
  if $printToSTDout \
      || [ "$processName" == "qsub" ]; then
    # stdout/err exists ?
    if [ ! -e /proc/$$/fd/1 ] || [ ! -e /proc/$$/fd/2 ]; then
      # log file exists ?
      if [ -f $LOG_FILE ]; then
        echo -e "$color[$LOCALHOST|$(date +%Y-%m-%dT%H:%M:%S)|$processName|$logLevel]$NC $logMsg" &>> "$LOG_FILE";
      fi
    elif [ -f $LOG_FILE ]; then
      echo -e "$color[$LOCALHOST|$(date +%Y-%m-%dT%H:%M:%S)|$processName|$logLevel]$NC $logMsg" |& tee -a "$LOG_FILE";
    else
      # fallback: print msg to the system log and to stdout/stderr
      logger "[$processName|$logLevel] $logMsg";
    fi
  else
    # print msg to the system log and to stdout/stderr
    logger "[$processName|$logLevel] $logMsg";
    echo -e "$color[$LOCALHOST|$(date +%Y-%m-%dT%H:%M:%S)|$processName|$logLevel]$NC $logMsg" &>> "$LOG_FILE";
  fi

  # re-enable 'set -x' if it was enabled before
  _setXFlag $cachedBashOpts;
}


#---------------------------------------------------------
#
# Checks if the shared fs prefix dir exists, if not it
# it will be created
#
checkSharedFS() {

  # shared root dir in place ?
  if [ ! -d $SHARED_FS_ROOT_DIR ]; then
    logDebugMsg "The shared fs root dir '$SHARED_FS_ROOT_DIR' does not exist, creating it.";
    if [ ! $(mkdir -p $SHARED_FS_ROOT_DIR) ]; then
    logErrorMsg "Shared file-system dir prefix '$SHARED_FS_ROOT_DIR' doesn't exist and cannot be created.";
    fi
    chmod 777 $SHARED_FS_ROOT_DIR;
  fi

  # if shared fs dir does not exist yet, create it quitely
  [ ! -d $SHARED_FS_JOB_DIR ] \
     && mkdir -p $SHARED_FS_JOB_DIR > /dev/null 2>&1 \
     && chown -R $USERNAME:$USERNAME $SHARED_FS_JOB_DIR \
     && chmod -R 775 $SHARED_FS_JOB_DIR;

  # check if shared fs: is present, is not in use, is read/write-able
  if [ -d "$SHARED_FS_JOB_DIR" ]; then
    if [ -n "$(lsof | grep $SHARED_FS_JOB_DIR)" ]; then
      logInfoMsg "Shared file system '$SHARED_FS_JOB_DIR' is in use.";
    elif [ ! -r $SHARED_FS_JOB_DIR/ ] && [ ! -w $SHARED_FS_JOB_DIR/ ]; then
      logErrorMsg "Shared file system '$SHARED_FS_JOB_DIR' has wrong \
permissions\n: $(ls -l $SHARED_FS_JOB_DIR/)!";
    else
      logDebugMsg "Shared file-system '$SHARED_FS_JOB_DIR' is available, readable and writable.";
    fi
  else
    # abort
    logErrorMsg "Shared file system '$SHARED_FS_JOB_DIR' not available!";
  fi
}


#---------------------------------------------------------
#
# Create RAM disk for image
#
createRAMDisk() {

  # create a ram disk (if not present and in use)
  if [ -d "$RAMDISK" ]; then
    if [ -n "$(lsof | grep $RAMDISK)" ]; then
      logErrorMsg "RAMdisk '$RAMDISK' is in use.";
    else
      logDebugMsg "Dir for ramdisk mount '$RAMDISK already exists, cleaning up.."
      umount $RAMDISK 2>/dev/null;
      rm -Rf $RAMDISK;
    fi
  fi
  # (re)create ramdisk mount point
  mkdir -p $RAMDISK;
  # mount ram disk and set owner
  mount -t ramfs ramfs $RAMDISK \
    && chmod 777 $RAMDISK \
    && chown $USERNAME:$USERNAME $RAMDISK;
}


#---------------------------------------------------------
#
# Cleans up hte shared fs dir, on the first allocated node in the list.
#
_cleanUpSharedFS() {
  # running inside root epilogue ?
  if [ $# -eq 0 ] \
      || [ "$1" != "rootNode" ]; then
    logDebugMsg "Skipping cleanup on sister node as we have a shared fs.";
  else # yes
    logDebugMsg "Cleaning up shared file system on root node '$LOCALHOST'.";
    if [ -n "$(lsof | grep $SHARED_FS_JOB_DIR/$LOCALHOST)" ]; then
      # print info
      logErrorMsg "Cannot clean shared file system '$SHARED_FS_JOB_DIR', it is in use.";
    fi
    # clean up the image files for the local node
    ! $DEBUG && rm -rf $SHARED_FS_JOB_DIR/$LOCALHOST;
  fi
}


#---------------------------------------------------------
#
# Cleans up RAM disk on each node.
#
_cleanUpRAMDisk() {
  echo "Cleaning up RAMdisk ";
  if [ -n "$(lsof | grep $RAMDISK)" ]; then
    # print info
    logErrorMsg "RAMdisk '$RAMDISK' is in use.";
  elif [ ! $DEBUG ]; then
    umount $RAMDISK;
    rm -Rf $RAMDISK;
  fi
}


#---------------------------------------------------------
#
# Destroys all local job related VMs.
#
_stopLocalJobVMs() {

  if [ $# -ne 3 ]; then
    logErrorMsg "Function '_destroyVM' called with '$#' arguments, '3' are expected.\nProvided params are: '$@'" 2;
  fi

  i=$1;
  totalCount=$2;
  domainXML=$3;
  startDate="$(date +%s)";

  # domain XML exists ?
  if [ ! -f "$domainXML" ]; then
    logWarnMsg "The guest's domain XML file '$domainXML' doesn't exist.";
    return 1;
  fi

  # grep domain name from VMs domainXML
  domainName="$(grep -E '<name>.*</name>' $domainXML | cut -d'>' -f2 | cut -d'<' -f1)";
  logTraceMsg "VM number '$i/$totalCount' has domainName '$domainName'.";

  # construct libVirt log file name for the VM
  vmLogFile=$VMLOG_FILE_PREFIX/$i-libvirt.log; # keep in sync with the name used in the prologue
  consoleLog="$VM_JOB_DIR/$LOCALHOST/$i-console.log";

  # create lock file
  logDebugMsg "Waiting for VM domain name '$domainName', using lock dir: '$LOCKFILES_DIR'";
  lockFile="$LOCKFILES_DIR/$domainName";
  touch $lockFile;

  #
  # if user disk is present, we need a clean shutdown first
  # the seed.img and sys iso needs to be skipped, thus we check if there are 3 in total
  #
  if [ 2 -lt $(grep '<disk type=' $domainXML | grep file | grep disk | wc -l) ]; then

    logTraceMsg "There is a disk attached to VM '$i/$totalCount' with domainName '$domainName'.";

    # shutdown VM
    logTraceMsg "Shutdown VM '$i/$totalCount' with domainName '$domainName'.";
    if $DEBUG;then
      output=$(virsh $VIRSH_OPTS --log $vmLogFile shutdown $domainName |& tee -a "$LOG_FILE");
      # ensure log file is user reabable
      chmod 644 "$vmLogFile";
    else
      output=$(virsh $VIRSH_OPTS shutdown $domainName 2>> "$LOG_FILE");
    fi
    logDebugMsg "virsh output:\n$output";
    # ensure console log file is user reabable, if it exists
    [ -f "$consoleLog" ] \
      && chmod 644 "$consoleLog";

    # wait until shutdown status is reached
    timeOut=false;
    while ! $timeOut \
        && [ -n "$(virsh list --all | grep ' $domainName ' | grep -iE 'shut off|ausgeschaltet')" ]; do

      # wait a moment before checking again
      logTraceMsg "Waiting for VM '$i/$totalCount' with domainName '$domainName' to shutdown..";
      sleep 2;

      # soft timeout reached ?
      timeOut=$(isTimeoutReached $TIMEOUT $startDate true);

    done
    # timeout reached ?
    if $timeOut; then
      # clean shut down finished
      msg="VM '$i/$totalCount' with domainName '$domainName', timeout \
of '$TIMEOUT' sec has been reached while waiting for shutdown to finish.";
      indicateRemoteError "$lockFile" "$msg";
      logErrorMsg "$msg";
    else
      # clean shut down finished
      logDebugMsg "VM '$i/$totalCount' with domainName '$domainName' has been \
shutdown or timeout of '$TIMEOUT' sec has been reached.";
    fi
  fi

  # destroy libvirt domain
  logDebugMsg "Destroying VM '$i/$totalCount' with domainName '$domainName'.";
  if $DEBUG;then
    output=$(virsh $VIRSH_OPTS --log $vmLogFile destroy $domainName |& tee -a "$LOG_FILE");
    # ensure log file is user reabable
    chmod 644 "$vmLogFile";
  else
    output=$(virsh $VIRSH_OPTS --log $vmLogFile destroy $domainName 2>> "$LOG_FILE");
  fi
  logDebugMsg "virsh output:\n$output";

  # ensure console log file is user reabable, if exists
  [ -f "$consoleLog" ] \
    && chmod 644 "$consoleLog";

  # remove lock file
  logDebugMsg "VM '$i/$totalCount' with domainName '$domainName' has been clean up.";
  logDebugMsg "Removing lock file for virsh domain name: '$domainName'.";
  rm -f "$lockFile";

  # done
  return 0;
}


#---------------------------------------------------------
#
# Clear local arp cache
#
_flushARPcache() {
  if [ -f "$LOCAL_VM_IP_FILE" ]; then
    vmIPs=$(cat "$LOCAL_VM_IP_FILE");
    logDebugMsg "Clearing VM IPs from local arp cache: $vmIPs";
    if [ -n "$vmIPs" ]; then
      for vmIP in $vmIPs; do
        $ARP_BIN -d $vmIP |& tee -a $LOG_FILE;
      done
    fi
  fi
}


#---------------------------------------------------------
#
# Clean up after the job has ran.
#
cleanUpVMs() {

  # log shutdown
  logDebugMsg "Shutting down and destroying all local VMs now.";

  if [ ! -e $(dirname "$DOMAIN_XML_PATH_NODE") ]; then
    logDebugMsg "Skipping VM cleanup, no domain *.xml files found";
    return 0;
  fi
  declare -a VM_DOMAIN_XML_LIST=($(ls $DOMAIN_XML_PATH_NODE/*.xml));

  # let remote processes know that we started our work
  informRemoteProcesses;

  # shutdown all VMs
  vmNo=0;
  totalCount=${#VM_DOMAIN_XML_LIST[@]};
  for domainXML in ${VM_DOMAIN_XML_LIST[@]}; do
    # increase counter
    vmNo=$(($vmNo + 1));
    # destroy local VMs
    logDebugMsg "Processing VM number '$vmNo/$totalCount' booted from domainXML='$domainXML'.";
    if $PARALLEL; then
      _stopLocalJobVMs $vmNo $totalCount $domainXML & continue;
    else
      _stopLocalJobVMs $vmNo $totalCount $domainXML;
    fi
  done

  if $PARALLEL; then
    # TODO wait for VMs to stop
     :
  fi

  logDebugMsg "Destroyed ($vmNo) local VM, done.";

  # clean up tmp files (images, etc)
  if $USE_RAM_DISK; then
    _cleanUpRAMDisk;
  else
    _cleanUpSharedFS $@;
  fi

  # flush arp cache
  _flushARPcache;

  # kill all processes owned by user
  skill -KILL -u $USERNAME;
}


#---------------------------------------------------------
#
# Run the original root scripts (prologue, epilogue, ...)
# that have been renamed to *.orig by the installer.
#
runScriptPreviouslyInPlace() {

  # check amount of params
  if [ $# -ne 1 ]; then
    logErrorMsg "Function 'runScriptPreviouslyInPlace' called with '$#' \
arguments, '1' is expected.\nProvided params are: '$@'" 2;
  fi

  scriptName=$1;
  res=0;

  # in case there was a script for this in the $TORQUE_HOME/mom_priv
  # that has been renamed (by the Makefile) to *.orig
  script="$TORQUE_HOME/mom_priv/$scriptName.orig";


  if [ -f "$script" ]; then
    logDebugMsg "Running '$script' script that was in place previously.";
    exec $script;
    res=$?;
  else
    logTraceMsg "There is no previous script '$script' in place that could be executed."
  fi
  return $res;
}


#---------------------------------------------------------
#
# Starts all the VM(s) dedicated to the current compute nodes
# where the script is executed.
#
startSnapTask(){

  # monitoring enabled ?
  if ! $SNAP_MONITORING_ENABLED; then
    logDebugMsg "Snap Monitoring is disabled, skipping initialization."
    return 0;
  fi

  # try
  {
    $SNAP_SCRIPT_DIR/snap-start.sh;
  } || { #catch
    logWarnMsg "Snap cannot tag task, skipping it.";
    return -9;
  }
  res=$?;
  logDebugMsg "Snap task tag return code: '$res'";
  return $?;
}


#---------------------------------------------------------
#
# Abort function that is called by the (global) signal trap.
#
stopSnapTask() {

  # monitoring enabled ?
  if ! $SNAP_MONITORING_ENABLED; then
    logDebugMsg "Snap Monitoring is disabled, skipping tear down."
    return 0;
  fi
  # try
  {
    $SNAP_SCRIPT_DIR/snap-stop.sh;
  } || { #catch
    logWarnMsg "Snap cannot clear tag from task, skipping it.";
    return -9;
  }
  res=$?;
  logDebugMsg "Snap task tag clearing return code: '$res'";
  return $res;
}


#---------------------------------------------------------
#
# this function sets up the environment to use shiquings prototype 1
# $1 is the IP address used for the dpdk bridge
#
setUPvRDMA_P1() {

  # enabled ?
  enabled=$($VRDMA_ENABLED && [ -f "$FLAG_FILE_DIR/.vrdma" ]);

  # does the local node support the required feature ?
  if ! $enabled \
      || ! [[ "$LOCALHOST" =~ ^$VRDMA_NODES$ ]]; then
    logDebugMsg "vRDMA disabled, skipping setup.";
    return 0;
  fi

  logDebugMsg "vRDMA is enabled, starting setup..";
  # try
  {
    # execute
    $VRDMA_SCRIPT_DIR/vrdma-start.sh;
  } || { #catch
    logWarnMsg "vRDMA cannot be started, skipping it.";
    return -9;
  }
  res=$?;
  logDebugMsg "vRDMA setup return code: '$res'";
  return $res;
}


#---------------------------------------------------------
#
# this function tear-down shiquing prototype 1
#
tearDownvRDMA_P1() {

  # enabled ?
  enabled=$($VRDMA_ENABLED && [ -f "$FLAG_FILE_DIR/.vrdma" ]);

  # enabled and does the local node support the required feature ?
  if ! $enabled \
      || ! [[ "$LOCALHOST" =~ ^$VRDMA_NODES$ ]]; then
    logDebugMsg "vRDMA disabled, skipping tear down.";
    return 0;
  fi
  # try
  {
    # execute
    $VRDMA_SCRIPT_DIR/vrdma-stop.sh;
  } || { #catch
    logWarnMsg "vRDMA cannot be stopped, skipping it.";
    return -9;
  }
  res=$?;
  logDebugMsg "vRDMA tear down return code: '$res'";
  return $res;
}


#---------------------------------------------------------
#
# setup IOcm
#
setupIOCM() {

  # enabled ?
  enabled=$($IOCM_ENABLED && [ -f "$FLAG_FILE_DIR/.iocm" ]);

  # does the local node support the required feature ?
  if ! $enabled \
      || ! [[ "$LOCALHOST" =~ ^$IOCM_NODES$ ]]; then
    logDebugMsg "IOCM disabled, skipping setup.";
    return 0;
  fi

  logDebugMsg "IOcm is enabled, starting setup..";
  # try
  {
    # execute
    $IOCM_SCRIPT_DIR/iocm-start.sh;
  } || { #catch
    logWarnMsg "IOcm cannot be started, skipping it.";
    return -9;
  }
  res=$?;
  logDebugMsg "IOcm setup return code: '$res'";
  return $res;
}


#---------------------------------------------------------
#
# Tears down IOcm
#
teardownIOcm() {

  # enabled ?
  enabled=$($IOCM_ENABLED && [ -f "$FLAG_FILE_DIR/.iocm" ]);

  # enabled and does the local node support the required feature ?
  if ! $enabled \
      || ! [[ "$LOCALHOST" =~ ^$IOCM_NODES$ ]]; then
    logDebugMsg "IOCM disabled, skipping tear down.";
    return 0;
  fi
  # try
  {
    # execute
    $IOCM_SCRIPT_DIR/iocm-stop.sh;
  } || { #catch
    logWarnMsg "IOcm cannot be stopped, skipping it.";
    return -9;
  }
  res=$?;
  logDebugMsg "IOcm tear down return code: '$res'";
  return $res;
}


#---------------------------------------------------------
#
# copy libvirt log from global logs dir to vm job dir (for vm jobs)
#
copyVMlogFile() {
  if [ -n "$(ls /var/log/libvirt/qemu/ | grep $JOBID | grep -E \.log$)" ]; then
    cp /var/log/libvirt/qemu/${JOBID}*.log "$VM_JOB_DIR/$LOCALHOST/";
    chown $USERNAME:$USERNAME "$VM_JOB_DIR/$LOCALHOST/"${JOBID}*.log;
  fi
}


#---------------------------------------------------------
#
# qsub creates the symlink based on the jobID as soon as the job is submitted
# due to race-conditions it may be possible that we want to write the log file
# but the symlink is not in place, yet
#
waitUntilJobDirIsAvailable() {
  # we wait a moment if there is still no dir it's not a VM job
  # and we should run regardless of that dir
  timeout=5;
  startDate="$(date +%s)";
  cachedValue=$PRINT_TO_STDOUT;
  PRINT_TO_STDOUT=true;
  while [ ! -e "$VM_JOB_DIR" ] \
    && ! isTimeoutReached $timeout $startDate true; do
    sleep 1;
    logDebugMsg "Waiting for job dir symlink '$VM_JOB_DIR' to become available.."
  done
  PRINT_TO_STDOUT=$cachedValue;
}


#---------------------------------------------------------
#
# Spawns a process that boots VMs and configures iocm
#
#
function spawnProcess() {
  # spawn
  {

    logDebugMsg "Spawning root process..";
    # cache start date
    startDate="$(date +%s)";

    # ensure flag file dir exists
    if [ ! -e "$FLAG_FILE_DIR/$LOCALHOST" ]; then
      {
        mkdir -p "$FLAG_FILE_DIR/$LOCALHOST" \
          && chown $USERNAME:$USERNAME "$FLAG_FILE_DIR/$LOCALHOST";
      } || logErrorMsg "Failed to create flag files dir '$FLAG_FILE_DIR/$LOCALHOST'.";
    fi

    # wait for userPrologue to generate VM files
    logDebugMsg "Waiting for flag file '$FLAG_FILE_DIR/$LOCALHOST/.userPrologueDone' to become available..";
    while [ ! -e "$FLAG_FILE_DIR/$LOCALHOST/.userPrologueDone" ]; do
      sleep 1;
      logTraceMsg "Waiting for flag file '$FLAG_FILE_DIR/$LOCALHOST/.userPrologueDone' to become available..";
      # timeout reached ? (if yes, we abort)
      isTimeoutReached $ROOT_PROLOGUE_TIMEOUT $startDate;
      # cancelled meanwhile ?
      checkCancelFlag;
    done
    logTraceMsg "Flag file '$FLAG_FILE_DIR/$LOCALHOST/.userPrologueDone' found."

    # boot all (localhost) VMs
    bootVMs;

    # setup IOcm
    setupIOCM;

    # indicate work is done
    {
      touch "$FLAG_FILE_DIR/$LOCALHOST/.rootPrologueDone" \
        && chown $USERNAME:$USERNAME "$FLAG_FILE_DIR/$LOCALHOST/.rootPrologueDone";
    } || logErrorMsg "Failed to create flag file '$FLAG_FILE_DIR/$LOCALHOST/.rootPrologueDone' and change owner to '$USERNAME'.";

  } & return 0;
}


#---------------------------------------------------------
#
# Boots VMs.
#
#
function bootVMs() {

  declare -a VM_DOMAIN_XML_LIST=($(ls $DOMAIN_XML_PATH_NODE/*.xml));
  totalCount=${#VM_DOMAIN_XML_LIST[@]};
  # boot all VMs dedicated to the current node we run on
  i=1;
  for domainXML in ${VM_DOMAIN_XML_LIST[@]}; do

    # construct filename of metadata yaml file that was used to create the seed.img
    metadataFile="$VM_JOB_DIR/$LOCALHOST/${i}-metadata";
    # grep vhostname from metadata file
    vHostName="$(grep 'hostname: ' $metadataFile | cut -d' ' -f2)";

    # construct logfile names
    vmLogFile="$VMLOG_FILE_PREFIX/$i-libvirt.log";
    consoleLog="$VM_JOB_DIR/$LOCALHOST/$i-console.log";

    # boot VM
    logDebugMsg "Booting VM number '$i/$totalCount' on compute node '$LOCALHOST' from domainXML='$domainXML'.";
    if $DEBUG; then
      output=$(virsh $VIRSH_OPTS --log $vmLogFile create $domainXML |& tee -a $LOG_FILE);
      logDebugMsg "virsh create cmd output:\n'$output'";
      # ensure log file is user reabable
      chmod 644 "$vmLogFile";
    else
      output=$(virsh $VIRSH_OPTS create $domainXML 2>> "$LOG_FILE");
    fi
    res=$?;

    # ensure console log file is user reabable, if exists
    [ -f "$consoleLog" ] \
      && chmod 644 "$consoleLog";

    # check if it's running
    vmName="$(grep '<name>' $domainXML | cut -d'>' -f2 | cut -d'<' -f1)";
    if [ $res -ne 0 ] \
        || [[ "$output" =~ operation\ failed ]] \
        || [ ! -n "$(virsh list | grep $vmName)" ] ; then
      # abort with error code 2
      logErrorMsg "Booting VM '$vmName' from domain XML file '$domainXML' failed!" 2 \
        & abort 2;
    elif [[ "$output" =~ operation\ is\ not\ valid ]]; then
      # abort with error code 9
      logErrorMsg "Booting VM '$vmName' from domain XML file '$domainXML' failed! Maybe it is running already?" 9 \
        & abort 9;
    fi
    logDebugMsg "VM is running.";
  done
}

