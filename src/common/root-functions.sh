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

  # log file exists ?
  if [ -z ${LOG_FILE-} ] \
       || [ ! -f $LOG_FILE ]; then
    # get dir
    logFileDir=$(dirname $LOG_FILE);
    # ensure dir exists
    [ ! -d $logFileDir ] && mkdir -p $logFileDir;
    # create log file
    touch $LOG_FILE;
    # set correct owner
    chown $USERNAME:$USERNAME -R $(dirname $LOG_FILE);
  fi

  # print log msg to job log file (may not exists during first cycles)
  if $printToSTDout \
      || [ $processName == "qsub" ]; then
    # log file exists ?
    if [ -f $LOG_FILE ]; then
      echo -e "$color[$LOCALHOST|$(date +%H:%M:%S)|$processName|$logLevel]$NC $logMsg" |& tee -a $LOG_FILE;
    fi
    # print msg to the system log and to stdout/stderr
    logger "[$processName|$logLevel] $logMsg";
  else
    # print msg to the system log and to stdout/stderr
    logger "[$processName|$logLevel] $logMsg";
    echo -e "$color[$LOCALHOST|$(date +%H:%M:%S)|$processName|$logLevel]$NC $logMsg" &>> tee -a $LOG_FILE;
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
  if [ $# -ne 1 ] || [ "$1" != "rootNodeOnly" ]; then
    logDebugMsg "Skipping cleanup on sister node.";
  else # yes
    logDebugMsg "Cleaning up shared file system ";
    if [ -n "$(lsof | grep $SHARED_FS_JOB_DIR/$LOCALHOST)" ]; then
      # print info
      logErrorMsg "Shared file system '$SHARED_FS_JOB_DIR' is in use.";
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
# Kills all local VMs that are related to the current job
#
_killLocalJobVMs() {
  # kill all VMs that match the JOBID
  vmList=$(virsh list --all | grep $JOBID | grep -vE 'Id|Name|-----' | cut -d' ' -f2);
  for vm in $vmList; do
    if $DEBUG; then
      virsh $VIRSH_OPTS destroy $vm 2>/dev/null | tee -a $LOG_FILE;
    else
      virsh $VIRSH_OPTS destroy $vm 2>/dev/null;
    fi
  done
}


#---------------------------------------------------------
#
# Clear local arp cache
#
_flushARPcache() {
  if [ -f "$LOCAL_VM_IP_FILE" ]; then
    vmIPs=$(cat "$LOCAL_VM_IP_FILE");
    logDebugMsg "Clearing VM IPs from local arp cache: $vmIPs";
    if [ -n "$vmIPS" ]; then
      for vmIP in $vmIPs; do
        arp -d $vmIP |& tee -a $LOG_FILE;
      done
    fi
  fi
}


#---------------------------------------------------------
#
# Clean up after the job has ran.
#
cleanUp() {

  # clean up tmp files (images, etc)
  if $USE_RAM_DISK; then
    _cleanUpRAMDisk;
  else
    _cleanUpSharedFS $@;
  fi

  # kill running job VMs
  _killLocalJobVMs;

  # flush arp cache
  _flushARPcache;
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
    res=$?;
  } || { #catch
    logWarnMsg "Snap cannot tag task, skipping it.";
    res=-9;
  }
  return $res;
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
    res=$?;
    logDebugMsg "Snap task tag clearing return code: '$res'";
  } || { #catch
    logWarnMsg "Snap cannot clear tag from task, skipping it.";
    res=-9;
  }
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
  if $enabled \
      && [[ "$LOCALHOST" =~ ^$VRDMA_NODES$ ]]; then
    logDebugMsg "vRDMA is enabled, starting setup..";
    # try
    {
      # execute
      $VRDMA_SCRIPT_DIR/vrdma-start.sh;
      res=$?;
    } || { #catch
      logWarnMsg "vRDMA cannot be started, skipping it.";
      res=-9;
    }
  else
    logDebugMsg "vRDMA is disabled, either globally or by the user.";
    res=0;
  fi
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
  if $enabled \
      && [[ "$LOCALHOST" =~ ^$VRDMA_NODES$ ]]; then
    # try
    {
      # execute
      $VRDMA_SCRIPT_DIR/vrdma-stop.sh;
      res=$?;
      logDebugMsg "vRDMA tear down return code: '$res'";
    } || { #catch
      logWarnMsg "vRDMA cannot be stopped, skipping it.";
      res=-9;
    }
  else
    res=0;
  fi
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
  if $enabled \
      && [[ "$LOCALHOST" =~ ^$IOCM_NODES$ ]]; then
    logDebugMsg "IOcm is enabled, starting setup..";
    # try
    {
      # execute
      $IOCM_SCRIPT_DIR/iocm-start.sh;
      res=$?;
    } || { #catch
      logWarnMsg "IOcm cannot be started, skipping it.";
      res=-9;
    }
  else
    res=0;
  fi
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
  if $enabled \
      && [[ "$LOCALHOST" =~ ^$IOCM_NODES$ ]]; then
    # try
    {
      # execute
      $IOCM_SCRIPT_DIR/iocm-stop.sh;
      res=$?;
      logDebugMsg "IOcm tear down return code: '$res'";
    } || { #catch
      logWarnMsg "IOcm cannot be stopped, skipping it.";
      res=-9;
    }
  else
    res=0;
  fi
  return $res;
}


#---------------------------------------------------------
#
# Starts a given service and returns the result code.
#
startService() {

  if [ $# -ne 1 ]; then
    logErrorMsg "Function 'startService' called with '$#' arguments, '1' is expected.\nProvided params are: '$@'" 2;
  fi

  serviceName="$1";

  service $serviceName start;
  return $?;
}


#---------------------------------------------------------
#
# Stops a given service and returns the result code.
#
stopService() {

  if [ $# -ne 1 ]; then
    logErrorMsg "Function 'stopService' called with '$#' arguments, '1' is expected.\nProvided params are: '$@'" 2;
  fi

  serviceName="$1";

  service $serviceName stop;
  return $?;
}


#---------------------------------------------------------
#
# Determines count of local VMs for the job
#
getVMCountOnLocalhost() {
  return $("$VM_JOB_DIR/$LOCALHOST/*.xml" | wc -l);
}


#---------------------------------------------------------
#
# copy libvirt log from global logs dir to vm job dir (for vm jobs)
#
copyVMlogFile() {
  if [ -n "$(ls /var/log/libvirt/qemu/ | grep $JOBID | grep -E \.log$)" ]; then
    cp /var/log/libvirt/qemu/${JOBID}*.log "$VM_JOB_DIR/$LOCALHOST/";
    chown $USERNAME:$USERNAME "$VM_JOB_DIR/$LOCALHOST/${JOBID}*.log";
  fi
}


#---------------------------------------------------------
#
# qsub creates the symlink based on the jobID as soon as the job is submitted
# due to race-conditions it may be possible that we want to write the log file
# but the symlink is not in place, yet
#
waitUntilJobDirIsAvailable() {
  # we wait 3 sec, if there is still no dir it's not a VM job 
  # and we should run regardless of that dir
  timeout=3;
  startDate="$(date +%s)";
  while [ ! -e $VM_JOB_DIR ]; do
    sleep 1;
    logDebugMsg "Waiting for job dir symlink '$VM_JOB_DIR' to become available.."
    isTimeoutReached $timeout $startDate;
  done
}
