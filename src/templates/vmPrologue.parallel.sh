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
# DESCRIPTION
#  This file is called by the vmPrologue on all nodes.
#  It creates a lock file based on the VM's MAC address, boots it and then
#  waits for all to become available.
#  As soon as the VMs responds via SSH, the locks are removed and processes exited.
#


#============================================================================#
#                                                                            #
#                          GLOBAL CONFIGURATION                              #
#                                                                            #
#============================================================================#

# source the global profile, for getting DEBUG and TRACE flags if set
source /etc/profile.d/99-mikelangelo-hpc_stack.sh;

#
# Random unique ID used for connecting jobs with generated files
# (when we need to generate scripts there's no jobID, yet)
#
RUID=__RUID__;

#
# Indicates debug mode.
#
DEBUG=__DEBUG__;

#
# Indicates trace mode.
#
TRACE=__TRACE__;

#
DISTRO=__DISTRO__;

#
# Amount of virtual cores
#
VCPUS=__VCPUS__;

#
# PBS_JOBID set in environment ?
# relevant if not executed by Torque, but manually
#
if [ $# -lt 1 ] \
    && [ -z ${PBS_JOBID-} ] ; then
  logErrorMsg "PBS_JOBID is not set! usage: $(basename ${BASH_SOURCE[0]}) <jobID>";
elif [ $# -ge 1 ]; then
  #workaround until SendEnv is used for SSH
  export PBS_JOBID=$1;
fi

#
# load config and constants
#
source "$SCRIPT_BASE_DIR/common/const.sh";
source "$SCRIPT_BASE_DIR/common/config.sh";
source "$SCRIPT_BASE_DIR/common/functions.sh";



#============================================================================#
#                                                                            #
#                          SCRIPT CONFIGURATION                              #
#                                                                            #
#============================================================================#


# get list of domain XMLs
declare -a VM_DOMAIN_XML_LIST=($(ls $DOMAIN_XML_PATH_NODE/*.xml));

#
# prevent duplicate log msgs
#
PRINT_TO_STDOUT=false;



#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#


#---------------------------------------------------------
#
# Checks preconditions and aborts if sth is not in place.
#
checkPreconditions() {
  if [ -f "$CANCEL_FLAG_FILE" ]; then
    logWarnMsg "Cancel flag file '$CANCEL_FLAG_FILE' found.";
    if $DEBUG; then
      logDebugMsg "Assuming test+debug, removing it.";
      rm -f $CANCEL_FLAG_FILE;
    else
      logErrorMsg "Aborting now.";
    fi
  fi
}


#---------------------------------------------------------
#
# Waits for localhost VM files to be generated.
#
_waitForFiles() {

  startDate=$(date +%s);
  filesCreatedFlag="$DOMAIN_XML_PATH_NODE/.done";

  # init of VMs to boot is done
  while [ ! -f "$filesCreatedFlag" ]; do
    # wait
    logDebugMsg "Waiting for VM-files on '$LOCALHOST' to be placed in dir '$DOMAIN_XML_PATH_NODE' ..";
    sleep 1;
    # timeout (150sec) reached ?
    isTimeoutReached 150 $startDate;
  done

  # check if the domain XML file exists
  if [ ! -n "$(ls $DOMAIN_XML_PATH_NODE/*.xml)" ]; then
    logErrorMsg "Files for node have been generated, but no domain XML files could be found.";
  fi
}


#---------------------------------------------------------
#
# Creates env file dir for each local VM(s) and triggers
# boot via a flag file that is picked up by root prologue's
# spawned process.
#
prepareVMs() {

  logDebugMsg "Preparing VM boot..";

  # wait for needed files to come into place
  _waitForFiles;

  # check if there is an error on remote hosts
  checkRemoteNodes;

  # let remote processes know that we started our work
  informRemoteProcesses;

  # create env file dir for each VM
  i=1;
  for domainXML in ${VM_DOMAIN_XML_LIST[@]}; do

    # construct filename of metadata yaml file that was used to create the seed.img
    metadataFile="$VM_JOB_DIR/$LOCALHOST/${i}-metadata";

    # check if file exists
    [ ! -e "$metadataFile" ] \
      && logErrorMsg "Metadata file '$metadataFile' doesn't exist !";

    # grep vhostname from metadata file
    vHostName=$(grep 'hostname: ' $metadataFile | cut -d' ' -f2);

    # create the dir that will be shared with VM
    logDebugMsg "Creating dir '$VM_NODE_FILE_DIR' for VM's nodefile.";
    mkdir -p "$VM_ENV_FILE_DIR/$LOCALHOST/$vHostName" \
      || logErrorMsg "Failed to create env file dir for VMs!";
  done

  # ensure dir exists
  if [ ! -e "$FLAG_FILE_DIR/$LOCALHOST" ]; then
    mkdir -p "$FLAG_FILE_DIR/$LOCALHOST" \
      || logErrorMsg "Failed to create flag file dir '$FLAG_FILE_DIR/$LOCALHOST'.";
  fi

  # create flag file to indicate root process to boot VMs now
  touch "$FLAG_FILE_DIR/$LOCALHOST/.userPrologueDone";
}


#---------------------------------------------------------
#
# Waits until root process has booted VMs and they are available.
#
function waitForVMs() {

  logDebugMsg "Waiting for boot of local VMs..";

  startDate="$(date +%s)";
  while [ ! -f "$FLAG_FILE_DIR/$LOCALHOST/.rootPrologueDone" ]; do
    sleep 1;
    logDebugMsg "Waiting for flag file '$FLAG_FILE_DIR/$LOCALHOST/.rootPrologueDone' to become available..";
    # timeout reached ? (if yes, we abort)
    isTimeoutReached $TIMEOUT $startDate;
  done

  logDebugMsg "Local VMs are booting, waiting until they are ready..";

  # wait until all VMs are ready
  for domainXML in ${VM_DOMAIN_XML_LIST[@]}; do

    # grep the mac address from the domainXML
    mac=$(grep -i '<mac' $domainXML | cut -d"'" -f 2);
    vmName="$(grep '<name>' $domainXML | cut -d'>' -f2 | cut -d'<' -f1)";
    if [ ! -n "$mac" ]; then
      logErrorMsg "No MAC found for VM '$vmName' in domain XML file: '$domainXML' !";
    fi

    # wait until SSH server becomes available
    if $PARALLEL; then
      # async
      _waitForVMtoBecomeAvailable "v$LOCALHOST-$i" "$mac" & : ;
    else
      # blocking
      _waitForVMtoBecomeAvailable "v$LOCALHOST-$i" "$mac";
    fi

    # check if an error occurred before lock files could be created
    checkErrorFlag;

    # check if job has been cancled meanwhile
    checkCancelFlag;

  done

  # dump core pinning info
  logTraceMsg "CPU pinning info for local VMs:\n-----\n$(virsh vcpuinfo $vmName)\n-----";

  # print debug info
  totalCount=${#VM_DOMAIN_XML_LIST[@]};
  logDebugMsg "Starting '$totalCount' VMs on node '$LOCALHOST' was successful, VMs are ready now.";

  # indicate success
  return 0;
}


#---------------------------------------------------------
#
# Waits until the VMs is available via SSH.
#
# VM's MAC is fetched from the domain XML and via 'arp -an'
# (vm pings its physical host) the IP is resolved.
#
_waitForVMtoBecomeAvailable() {

  # check amount of params
  if [ $# -ne 2 ]; then
    logErrorMsg "Function '_waitForVMtoBecomeAvailable' called with '$#' \
arguments, '2' are expected.\nProvided params are: '$@'" 2;
  fi

  #
  vhostName=$1;
  # ensure mac is lower case
  mac=$(echo $2 | tr '[:upper:]' '[:lower:]');

  # cancelled meanwhile ?
  checkCancelFlag;

  # create lock file
  logDebugMsg "Waiting for VM '$vhostName' with MAC='$mac', using lock dir: '$LOCKFILES_DIR'";
  lockFile="$LOCKFILES_DIR/$mac";
  touch $lockFile;

  # wait until it the VM has requested an IP
  arpOut=$($ARP_BIN -an | grep -i "$mac"); #FIX for 'since a few days this binary can no longer be found'
  startDate=$(date +%s);
  vmIP=$(echo $arpOut | cut -d' ' -f2 | sed 's,(,,g' | sed 's,),,g');
  msg="";

  # watch out for VM's MAC in arp's output (that appears together with its IP)
  while [ ! -n "$arpOut" ]; do

    # cancelled meanwhile ?
    checkCancelFlag;

    # check remote hosts for errors and abort flag
    checkRemoteNodes;

    # timeout reached ?
    isTimeoutReached $TIMEOUT $startDate true;
    res=$?;
    if [ $res -eq 0 ]; then
      msg="Aborting.\n Timeout of '$TIMEOUT' sec reached \
and VM '$vhostName' with MAC='$mac' is still not available.";
      logWarnMsg "$msg";
      indicateRemoteError "$lockFile" "$msg";
    fi

    # logging
    logTraceMsg "VM '$vhostName' with MAC='$mac' has not been seen until now.";

    # wait a moment before checking arp again
    sleep 1;
    arpOut=$($ARP_BIN -an | grep -i "$mac");
    logTraceMsg "Output of arp for vNode '$vhostName': '$arpOut'";

    # already found ?
    if [ -n "$arpOut" ]; then

      # grep VM's IP from arp output
      vmIP=$(echo -n "$arpOut" | cut -d' ' -f2 | sed 's,(,,g' | sed 's,),,g');
      if [ ! -n "$vmIP" ]; then
        logErrorMsg "Command '$ARP_BIN -an' failed, output: '$arpOut'";
      fi
      logDebugMsg "IP for VM '$vhostName' found via 'arp -an': $vmIP";

      # done, we got what we need
      break;

    else

      # let's try to ping the vmIP, since it may be an old one from the local cache or so
      logTraceMsg "Let's try to ping VM's hostname '$vhostName'.";
      vmIP="$(ping -c1 -W1 $vhostName 2>/dev/null | grep -v 'Destination Host Unreachable' \
| grep -E 'PING|, 0% packet loss' | cut -d' ' -f3 | grep -v transmitted \
| cut -d'(' -f2 | cut -d')' -f1)";

      # found ?
      if [ -n "$vmIP" ]; then
        logTraceMsg "Seems like we can ping VM's hostname '$vhostName' and it resolves to '$vmIP'";

        # check if arp knowns already the MAC for VM's IP
        tmp=$($ARP_BIN -an | grep -i "$vmIP");

        # grep mac and make it lower case
        foundMac=$(echo $tmp | cut -d' ' -f4 | tr '[:upper:]' '[:lower:]');

        # any mac found ?
        if [ ! -n "$foundMac" ] \
            || [[ "$foundMac" =~ incomplete ]]; then
          logDebugMsg "Seems we still need to wait. We have an (old?) IP \
'$vmIP' for the VM '$vhostName', but no MAC can be found for it, yet.";
          logTraceMsg "arp output: '$tmp'";
          continue;
        elif [ "$mac" != "$foundMac" ]; then
          # maybe an old cached one
          logDebugMsg "MAC found '$foundMac' for the IP '$vmIP' of vHostName \
'$vhostName', does not match expected MAC '$mac'. Waiting..";
        else
          # everything is fine, exit loop
          break;
        fi
      fi

      #maybe check if VM is still running (virsh list)

    fi
  done

  # success ?
  if [ ! -n "$vmIP" ]; then
    [ -n "$msg" ] && logWarnMsg "$msg";
    logErrorMsg "Resolving VM's '$vhostName' IP failed.";
  fi

  # write VM's IP into localhost's vmIPs file
  logDebugMsg "VM with MAC='$mac' is now online, IP: '$vmIP'";
  count=0;
  while [ $count -lt $VCPUS ]; do
    # when we request i.e. 16 cores we get 16 ranks
    # so use VCPUS for amount of ranks
    echo "$vmIP" >> $LOCAL_VM_IP_FILE;
    count=$((count + 1));
  done
  logTraceMsg "VM IPs cached in file '$LOCAL_VM_IP_FILE':\n-----\n$(cat $LOCAL_VM_IP_FILE)\n-----";

  # now wait until the VM becomes available via SSH
  if [[ $DISTRO =~ $REGEX_OSV ]]; then
    logDebugMsg "DISTRO '$DISTRO' is OSv, using HTTP check";
    CONN_TEST_CMD="curl --connect-timeout 2 http://$vmIP:8000";
    ERR_CODE_TIMEOUT=28;
    protocol="HTTP";
  else
    logDebugMsg "DISTRO '$DISTRO' is linux, using SSH check";
    CONN_TEST_CMD="ssh -n -o BatchMode=yes -o ConnectTimeout=2 $vmIP 'exit 0;'";
    ERR_CODE_TIMEOUT=255;
    protocol="SSH";
  fi

  # wait for VM to become ready
  while [ $($CONN_TEST_CMD &>/dev/null; echo $?) -eq $ERR_CODE_TIMEOUT  ]; do

    # cancelled meanwhile ?
    checkCancelFlag;

    # check remote hosts for errors and abort flag
    checkRemoteNodes;

    # wait a moment before checking again
    logDebugMsg "Waiting for VM's ($mac / $vmIP) to become available via $protocol ..";
    sleep 1;

    # timeout reached ?
    isTimeoutReached $TIMEOUT $startDate true;
    res=$?;
    if [ $res -eq 0 ]; then
      msg="Aborting.\n Timeout of '$TIMEOUT' sec reached \
and VM '$vhostName' with MAC='$mac' is still not available via $protocol.";
      indicateRemoteError "$lockFile" "$msg";
    fi

  done

  # success, VM is available now
  logDebugMsg "VM's ($mac / $vmIP) $protocol server is now available.";

  # fetch the cloud-init log if debugging
  if $DEBUG; then
    destFile="$VM_JOB_DIR/$LOCALHOST/cloud-init_$vhostName.log";
    logDebugMsg "Fetching cloud-init.log from '$vmIP' as '$destFile'.".
    # standard linux or OSv ?
    if [[ "$DISTRO" =~ $SUPPORTED_STANDARD_LINUX_GUESTS ]]; then

      # fetch cloud init log file
      scp $SCP_OPTS $vmIP:$CLOUD_INIT_LOG $destFile;

      # determine syslog filename
      if [[ "$DISTRO" =~ $REGEX_DEBIAN ]]; then
        sysLogFile=$SYS_LOG_FILE_DEBIAN;
      elif  [[ "$DISTRO" =~ $REGEX_REDHAT ]]; then
        sysLogFile=$SYS_LOG_FILE_RH;
      else
        logErrorMsg "Unknown distro '$DISTRO'!";
      fi

      #requires root rights, chmod applied via metadata in cloud-init
      logDebugMsg "Fetching syslog from '$vmIP'".
      scp $SCP_OPTS $vmIP:$sysLogFile $VM_JOB_DIR/$LOCALHOST/syslog_$vhostName.log;
    fi
  # else: OSv doesn't have a dedicated cloud-init log.
    # Relevant info is written to console
  fi

  # remove lock file
  logDebugMsg "Removing lock file for VM ($mac / $vmIP).";
  rm -f "$lockFile";

  # done
  return 0;
}


#---------------------------------------------------------
#
# Abort function that is called by the (global) signal trap.
#
_abort() { # it should not happen that we reach this function, but in case..
  # nothing else to do, since the root vmPrologue controls the clean up.
  logWarnMsg "Canceling job execution.";
}



#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

# debug log
logDebugMsg "************* BEGIN OF JOB PROLOGUE.PARALLEL *****************";
logInfoMsg "User prologue.parallel wrapper script started.";

checkPreconditions;

# ensure that we do not loose anything for debug.log
captureOutputStreams;

# prepare files for VMs
prepareVMs;

# wait for VMs to become available
waitForVMs;
res=$?;

# debug log
logDebugMsg "************** END OF JOB PROLOGUE.PARALLEL ******************";
logInfoMsg "User prologue.parallel wrapper script finished.";

# print the consumed time in debug mode
runTimeStats;

# return exit code
exit $res;

