#!/bin/bash
#
# Copyright 2016-2017 HLRS, University of Stuttgart
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

#=============================================================================
#
#         FILE: functions.sh
#
#        USAGE: source root-functions.sh
#
#  DESCRIPTION: Collection of vTorque helper functions executed as root.
#               NOTE: file 'functions.sh' must be sourced first.
#
#      OPTIONS: ---
# REQUIREMENTS: log4bsh must be available
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Nico Struckmann, struckmann@hlrs.de
#      COMPANY: HLRS, University of Stuttgart
#      VERSION: 0.2
#      CREATED: Oct 02nd 2015
#     REVISION: Jul 10th 2017
#
#    CHANGELOG
#         v0.2: refactoring and cleanup
#
#=============================================================================
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
# Checks if the shared fs prefix dir exists, if not it
# it will be created
#
checkSharedFS() {

  # shared root dir in place ?
  if [ ! -d $WS_DIR ]; then
    logDebugMsg "The shared fs root dir '$WS_DIR' does not exist, creating it.";
    if [ ! $(mkdir -p $WS_DIR) ]; then
    logErrorMsg "Shared workspace dir '$WS_DIR' doesn't exist and cannot be created.";
    fi
    # allow all users rw access to the workspace dir
    chmod 777 $WS_DIR;
  fi

  # if shared fs dir does not exist yet, create it quitely
  if [ ! -d $SHARED_FS_JOB_DIR ]; then
    su - $USER_NAME -c "mkdir -p '$SHARED_FS_JOB_DIR'" \
         > /dev/null 2>&1 \
     && chmod -R 775 $SHARED_FS_JOB_DIR;
  fi

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
    && chown $USER_NAME:$USER_NAME $RAMDISK;
}


#---------------------------------------------------------
#
# Cleans up hte shared fs dir, on the first allocated node in the list.
#
_cleanUpSharedFS() {

  # check if VMs are still running
  domainNames=$(echo ${VM_DOMAIN_XML_LIST[@]} | sed 's, ,|,g');
  vmsFound="$(virsh list --all | grep -E $domainNames)";
  if [ ! -z ${vmsFound-} ]; then
    logErrorMsg "VMs still not cleaned up: '$vmsFound'";
  fi

  # running inside root epilogue ?
  if [ $# -eq 0 ] \
      || ! $1; then
    logDebugMsg "Skipping cleanup on sister node as we have a shared fs.";
  else # yes
    logDebugMsg "Cleaning up shared file system on root node '$LOCALHOST'.";
    if [ -n "$(lsof | grep $SHARED_FS_JOB_DIR/$LOCALHOST)" ]; then
      # print info
      logErrorMsg "Cannot clean shared file system '$SHARED_FS_JOB_DIR', it is in use.";
    fi
    # clean up the image files for the local node
    ! $DEBUG \
      && rm -rf $SHARED_FS_JOB_DIR/$LOCALHOST;
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
  elif ! $DEBUG; then
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
# Blocks until all VMs are stopped.
#
_waitForVMsToStop() {
  domainNames=$(echo ${VM_DOMAIN_XML_LIST[@]} | sed 's, ,|,g');
  startDate=$(date +%s);
  while ! isTimeoutReached $TIMEOUT $startDate true \
      && [ -n "$(virsh list --all | grep -E $domainNames)" ]; do
    logDebugMsg "Job's VMs still alive, waiting..";
    sleep 1;
  done
}


#---------------------------------------------------------
#
# Clear local arp cache
#
_flushARPcache() {
  if [ -f "$LOCAL_VM_IP_FILE" ]; then
    vmIPs=$(cat "$LOCAL_VM_IP_FILE" | uniq);
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
# Checks whether the job is a VM job.
#
isVMJob() {
  return $([ -d "$VM_JOB_DIR" ]);
}


#---------------------------------------------------------
#
# Clean up after the job has ran.
#
cleanUpVMs() {

  # log shutdown
  logDebugMsg "Shutting down and destroying all local VMs now.";

  if [ -z ${DOMAIN_XML_PATH_NODE-} ] \
      || [ ! -d "$DOMAIN_XML_PATH_NODE" ]; then
    logWarnMsg "Skipping VM cleanup, no domain *.xml files found";
    return 0;
  fi
  declare -a VM_DOMAIN_XML_LIST=($(ls $DOMAIN_XML_PATH_NODE/*.xml));

  # domain XML(s) found ?
  if [ -z ${VM_DOMAIN_XML_LIST-} ]; then
      # no, abort
    logWarnMsg "No domain XML files can be found in dir '$DOMAIN_XML_PATH_NODE' !";
    return 0;
  fi

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
    # wait for VMs to stop
    _waitForVMsToStop;
  fi

  logDebugMsg "Destroyed ($vmNo) local VM, done.";

  # flush arp cache
  _flushARPcache;

  # kill all processes owned by user
  skill -KILL -u $USER_NAME;
}


#---------------------------------------------------------
#
# Run the original root scripts (prologue, epilogue, ...)
# that have been renamed to *.orig by the installer.
#
runScriptPreviouslyInPlace() {

  # check amount of params
  if [ $# -lt 3 ]; then
    logErrorMsg "Function 'runScriptPreviouslyInPlace' called with '$#' \
arguments, '3-8' are expected.\nProvided args are: '$@'" 2;
  fi

  # cache script name to execute
  scriptName=$1;
  # remove the first element from '$@'
  shift;

  # in case there was a script for this in the $TORQUE_HOME/mom_priv
  # that has been renamed (by the Makefile) to *.orig
  script="$TORQUE_HOME/mom_priv/$scriptName.orig";

  local res=0;
  if [ -x "$script" ]; then
    logDebugMsg "Running '$script' script that was in place previously.";
    exec $script $@;
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
  #logDebugMsg "Snap task tag return code: '$res'";
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
  #logDebugMsg "Snap task tag clearing return code: '$res'";
  return $res;
}


#---------------------------------------------------------
#
# Sets up vRDMA.
#
setUPvRDMA() {

  # enabled by admins (=config option) and requested by user (=flag file) ?
  if ! $VRDMA_ENABLED \
      || [ ! -f "$FLAG_FILE_VRDMA" ]; then
    logInfoMsg "vRDMA disabled, skipping setup.";
    return 0;
  # is the local node configured to be available for vRDMA ?
  elif (! [[ "$LOCALHOST" =~ ^$VRDMA_NODES$ ]]); then
    logWarnMsg "Node is not defined as vRDMA node, skipping setup.";
    return 0;
  fi

  logDebugMsg "vRDMA is enabled, starting setup..";
  # try
  {
    # execute
    $VRDMA_SCRIPT_DIR/vrdma-start.sh;
  } || { #catch
    logErrorMsg "vRDMA cannot be started, aborting.";
  }
  res=$?;
  #logDebugMsg "vRDMA setup return code: '$res'";
  return $res;
}


#---------------------------------------------------------
#
# this function tear-down shiquing prototype 1
#
tearDownvRDMA() {

  # enabled by admins (=config option) and requested by user (=flag file) ?
  if ! $VRDMA_ENABLED \
      || [ ! -f "$FLAG_FILE_VRDMA" ]; then
    logInfoMsg "vRDMA disabled, skipping tear down.";
    return 0;
  # is the local node configured to be available for vRDMA ?
  elif (! [[ "$LOCALHOST" =~ ^$VRDMA_NODES$ ]]); then
    logWarnMsg "Node is not defined as vRDMA node, skipping tear down.";
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
  #logDebugMsg "vRDMA tear down return code: '$res'";
  return $res;
}


#---------------------------------------------------------
#
# setup IOcm
#
setupIOCM() {

  # enabled by admins (=config option) and requested by user (=flag file) ?
  if ! $IOCM_ENABLED \
      || [ ! -f "$FLAG_FILE_IOCM" ]; then
    logInfoMsg "IOCM disabled, skipping setup.";
    return 0;
  # is the local node configured to be available for vRDMA ?
  elif (! [[ "$LOCALHOST" =~ ^$IOCM_NODES$ ]]); then
    logWarnMsg "Node is not defined as IOCM node, skipping setup.";
    return 0;
  fi

  logDebugMsg "IOcm is enabled, starting setup..";
  # try
  {
    # execute
    $IOCM_SCRIPT_DIR/iocm-start.sh;
  } || { #catch
    logErrorMsg "IOcm cannot be started, aborting.";
  }
  res=$?;
  #logDebugMsg "IOcm setup return code: '$res'";
  return $res;
}


#---------------------------------------------------------
#
# Tears down IOcm
#
teardownIOcm() {

  # enabled by admins (=config option) and requested by user (=flag file) ?
  if ! $IOCM_ENABLED \
      || [ ! -f "$FLAG_FILE_IOCM" ]; then
    logInfoMsg "IOCM disabled, skipping tear down.";
    return 0;
  # is the local node configured to be available for vRDMA ?
  elif (! [[ "$LOCALHOST" =~ ^$IOCM_NODES$ ]]); then
    logWarnMsg "Node is not defined as IOCM node, skipping tear down.";
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
  #logDebugMsg "IOcm tear down return code: '$res'";
  return $res;
}


#---------------------------------------------------------
#
# copy libvirt log from global logs dir to vm job dir (for vm jobs)
#
copyVMlogFile() {
  if [ -n "$(ls /var/log/libvirt/qemu/ | grep $JOBID | grep -E \.log$)" ]; then
    cp /var/log/libvirt/qemu/${JOBID}*.log "$VM_JOB_DIR/$LOCALHOST/";
    chown $USER_NAME:$USER_NAME "$VM_JOB_DIR/$LOCALHOST/"${JOBID}*.log;
  fi
}


#---------------------------------------------------------
#
# For non-VM jobs we need to change the log file env var,
# otherwise log4bsh will create it as root in users $HOME.
# In order to still have a log in the prologue{.parallel}
# print ot stdout is enforced.
#
ensureProperSettings() {
  # for non-vm jobs there is no log file
  if [ ! -e $LOG_FILE ]; then
    # happens in case of manual debugging
    # prevents log file dir to be created
    # as root by log4bsh
    LOG_FILE=/dev/null;
    PRINT_TO_STDOUT=true;
  fi
}


#---------------------------------------------------------
#
# vsub creates the symlink based on the jobID as soon as the job is submitted
# due to race-conditions it may be possible that we want to write the log file
# but the symlink is not in place, yet
#
waitUntilJobDirIsAvailable() {

  # ensure no error occurred so far
  checkCancelFlag;

  # we wait a moment if there is still no dir it's not a VM job
  # and we should run regardless of that dir
  startDate="$(date +%s)";
  cachedValue=$PRINT_TO_STDOUT;
  cachedLogFile=$LOG_FILE;
  PRINT_TO_STDOUT=true;
  LOG_FILE=/dev/null;
  logInfoMsg "Checking if this is a VM job...\nPlease be patient, it may take up to '$NFS_TIMEOUT' sec.";
  while [ ! -e "$VM_JOB_DIR" ] \
    && ! isTimeoutReached $NFS_TIMEOUT $startDate true; do
    sleep 1;
    logDebugMsg "Waiting for job dir symlink '$VM_JOB_DIR' to become available..";
  done
  # VM job ?
  if [ -e "$VM_JOB_DIR" ]; then
    # yes, revert logfile to original value
    PRINT_TO_STDOUT=$cachedValue;
    LOG_FILE=$cachedLogFile;
  fi
}


#---------------------------------------------------------
#
# Spawns a process that boots VMs and configures IOcm, vRDMA
#
#
spawnProcess() {
  # spawn
  {

    # time measurements
    start=$1;

    logDebugMsg "Spawning root process (pid=$$)..";
    # cache start date
    startDate="$(date +%s)";

    # ensure flag file dir exists
    if [ ! -e "$FLAG_FILE_DIR/$LOCALHOST" ]; then
      su - $USER_NAME -c "mkdir -p '$FLAG_FILE_DIR/$LOCALHOST'";
      [ $? -ne 0 ] \
        && logErrorMsg "Failed to create flag files dir '$FLAG_FILE_DIR/$LOCALHOST'.";
    fi

    # wait for userPrologue to generate VM files
    logDebugMsg "Waiting for flag file '$FLAG_FILE_DIR/$LOCALHOST/.userPrologueDone' to become available..";
    while [ ! -e "$FLAG_FILE_DIR/$LOCALHOST/.userPrologueDone" ]; do
      sleep 1;
      logDebugMsg "Waiting for flag file '$FLAG_FILE_DIR/$LOCALHOST/.userPrologueDone' to become available..";
      # timeout reached ? (if yes, we abort)
      isTimeoutReached $PROLOGUE_TIMEOUT $startDate;
      # cancelled meanwhile ?
      checkCancelFlag;
    done
    logDebugMsg "Flag file '$FLAG_FILE_DIR/$LOCALHOST/.userPrologueDone' found."

    # boot all (localhost) VMs
    bootVMs;

    # setup IOcm
    setupIOCM;

    # indicate work is done
    su - $USER_NAME -c "touch '$FLAG_FILE_DIR/$LOCALHOST/.rootPrologueDone'";
    if [ $? -ne 0 ]; then
      logErrorMsg "Failed to create flag file '$FLAG_FILE_DIR/$LOCALHOST/.rootPrologueDone' and change owner to '$USER_NAME'.";
    else
      logDebugMsg "Flag file '$FLAG_FILE_DIR/$LOCALHOST/.rootPrologueDone' has been created.";
    fi
    # measure time ?
    if $MEASURE_TIME; then
      printRuntime "<spawn VM boot process>" $start;
    fi
  } & return 0;
}


#---------------------------------------------------------
#
# Boots VMs.
#
#
bootVMs() {

  if [ -z ${DOMAIN_XML_PATH_NODE-} ] \
      || [ ! -d "$DOMAIN_XML_PATH_NODE" ]; then
    logWarnMsg "Skipping VM instantiation, no domain *.xml files found";
    return 0;
  fi

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


#---------------------------------------------------------
#
# Removes all tmp files created by vTorque,
# if not running in debug mode.
#
# I.e. all VM image files, metadata files, log, etc
#
cleanupTmpFiles() {

  # clean up files on shared storage ?
  if [ $# -eq 0 ]; then
    cleanupSharedFS=false;
  else
    cleanupSharedFS=$1;
  fi

  # remove local node's tmp file, like images
  if $USE_RAM_DISK; then
    _cleanUpRAMDisk;
  elif $cleanupSharedFS; then
    _cleanUpSharedFS $cleanupSharedFS;
  else
    # if there is no RAM disk to clean up, all is on a shared fs
    return $?;
  fi

  # do not clean up in debug mode
  if ! $DEBUG; then

    # dir to clean up exists ?
    if [ ! -e "$VM_JOB_DIR" ]; then
      logWarnMsg "vTorque job tmp dir '$VM_JOB_DIR' does not exist.";
    else

      # determine RUID for job
      ruid="$(cat $RUID_CACHE_FILE)";
      # reverse resolve symlink via RUID
      # ruidSymlink="$(find -L $VM_JOB_DIR_PREFIX/$ruid -samefile $VM_JOB_DIR_PREFIX/$JOBID 2>/dev/null | grep -v $VM_JOB_DIR_PREFIX/$ruid)";
      ruidDir="$VM_JOB_DIR_PREFIX/$ruid";
      # remove symlink
      rm -f "$VM_JOB_DIR_PREFIX/$JOBID";
      mv "$ruidDir" "$VM_JOB_DI_PREFIX/$JOBID";

      # remove all files ?
      if $MEASURE_TIME; then
        # remove all files and all dirs, but the debug.log
        find "$VM_JOB_DI_PREFIX/$JOBID" ! -name '$LOG_FILE' -type d -exec rm -rf {} +;
        find "$VM_JOB_DI_PREFIX/$JOBID" ! -name '$LOG_FILE' -type f -exec rm -f {} +
      else
	# yes, all
        rm -rf "$VM_JOB_DI_PREFIX/$JOBID";
      fi
    fi
  fi
}

