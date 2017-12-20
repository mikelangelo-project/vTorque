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
#         FILE: vmPrologue.parallel.sh
#
#        USAGE: n/a
#
#  DESCRIPTION: Template for user prologue.parallel script.
#               Executed by the vmPrologue on all nodes, including rank 0.
#               Prepares VM instantiation and waits for all guests to become
#               available.
#               As soon as the VMs are ready, locks are removed and polling
#               is stopped.
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Nico Struckmann, struckmann@hlrs.de
#      COMPANY: HLRS, University of Stuttgart
#      VERSION: 0.3
#      CREATED: Oct 2nd 2015
#     REVISION: Jul 10th 2017
#
#    CHANGELOG
#         v0.2: bug fixes and refactoring
#         v0.3: refactoring and clean up
#
#=============================================================================

# time measurements
START=$(date +%s.%N);

#============================================================================#
#                                                                            #
#                          GLOBAL CONFIGURATION                              #
#                                                                            #
#============================================================================#

# source the global profile
source /etc/profile.d/99-mikelangelo-hpc_stack.sh;

#
# Random unique ID used for connecting jobs with generated files
# (when we need to generate scripts there's no jobID, yet)
#
RUID=__RUID__;

#
# Guest image distro (redhat, debian, osv)
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
if [ $# -lt 2 ] \
    && [ -z ${PBS_JOBID-} ] \
    && [ -z ${USER-} ]; then
  logErrorMsg "\$PBS_JOBID is not set! usage: $(basename ${BASH_SOURCE[0]}) <jobID> <user>";
fi

#
# load config and constants
#
source "$VTORQUE_DIR/common/const.sh" $@;
source "$VTORQUE_DIR/common/config.sh";
source "$VTORQUE_DIR/common/functions.sh";



#============================================================================#
#                                                                            #
#                          SCRIPT CONFIGURATION                              #
#                                                                            #
#============================================================================#


# get list of domain XMLs
declare -a VM_DOMAIN_XML_LIST=();

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

  if [ ! -f "$CANCEL_FLAG_FILE" ] \
       && [ -e "$DOMAIN_XML_PATH_NODE" ]; then
    logTraceMsg "Preconditions check passed successfully.";
    return 0;
  fi

  logWarnMsg "Cancel flag file '$CANCEL_FLAG_FILE' found.";
  if $DEBUG; then
    logDebugMsg "Assuming test+debug, removing cancel flag file '$CANCEL_FLAG_FILE' ..";
    rm -f $CANCEL_FLAG_FILE;
  else
    logErrorMsg "Aborting now.";
  fi
  return 1;
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
    # check cancel flag
    checkCancelFlag;
    # wait for flag file
    logDebugMsg "Waiting for VM-files on '$LOCALHOST' to be placed in dir '$DOMAIN_XML_PATH_NODE' ..";
    sleep 1;
    # timeout reached ?
    isTimeoutReached $TIMEOUT $startDate;
  done

  # initialize list of domain XMLs
  if [ -d "$DOMAIN_XML_PATH_NODE" ]; then
    VM_DOMAIN_XML_LIST=($(ls $DOMAIN_XML_PATH_NODE/*.xml));
  fi

  # check if the domain XML file exists
  if [ -z ${VM_DOMAIN_XML_LIST-} ]; then
    logErrorMsg "No domain XML files found in dir '$DOMAIN_XML_PATH_NODE'.";
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
    logDebugMsg "Creating dir '$VM_NODEFILE_DIR' for VM's nodefile.";
    mkdir -p "$PBS_ENV_FILE_PREFIX/$LOCALHOST/$vHostName" \
      || logErrorMsg "Failed to create env file dir for VMs!";
  done

  # ensure dir exists
  if [ ! -e "$FLAG_FILE_DIR/$LOCALHOST" ]; then
    mkdir -p "$FLAG_FILE_DIR/$LOCALHOST" \
      || logErrorMsg "Failed to create flag file dir '$FLAG_FILE_DIR/$LOCALHOST'.";
  fi

  # create flag file to indicate root process to boot VMs now
  logDebugMsg "User prologue finished preparation, creating flag file '$FLAG_FILE_DIR/$LOCALHOST/.userPrologueDone'.";
  touch "$FLAG_FILE_DIR/$LOCALHOST/.userPrologueDone";
  # success ?
  if [ $# -ne 0 ]; then
    logErrorMsg "Failed to create flag file '$FLAG_FILE_DIR/$LOCALHOST/.userPrologueDone' !";
  else
    logDebugMsg "Created flag file '$FLAG_FILE_DIR/$LOCALHOST/.userPrologueDone'.";
  fi
}


#---------------------------------------------------------
#
# Waits until root process has booted VMs and they are available.
#
waitForVMs() {

  logDebugMsg "Waiting for boot of local VMs..";

  waitForRootPrologue $TIMEOUT;

  logDebugMsg "Local VMs are booting, waiting until they are ready..";

  # wait until all VMs are ready
  for domainXML in ${VM_DOMAIN_XML_LIST[@]}; do

    # grep the mac address from the domainXML
    mac=$(grep -i '<mac' $domainXML | cut -d"'" -f 2);
    vmName="$(grep '<name>' $domainXML | cut -d'>' -f2 | cut -d'<' -f1)";
    if [ ! -n "$mac" ]; then
      logErrorMsg "No MAC found for VM '$vmName' in domain XML file: '$domainXML' !";
    fi

    # wait until VM becomes available
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

    # dump core pinning info
    logTraceMsg "CPU pinning info for local VM '$vmName':\n-----\n$(virsh vcpuinfo $vmName)\n-----";

  done

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

  # cache VM's hostname
  local vhostName=$1;
  # ensure mac is lower case
  local mac=$(echo $2 | tr '[:upper:]' '[:lower:]');

  # cancelled meanwhile ?
  checkCancelFlag;

  # create lock file
  logDebugMsg "Waiting for VM '$vhostName' with MAC='$mac', using lock dir: '$LOCKFILES_DIR'";
  waitForNFS "$LOCKFILES_DIR";
  local lockFile="$LOCKFILES_DIR/$mac";
  touch $lockFile;

  # wait until it the VM has requested an IP
  local arpOut=$($ARP_BIN -an | grep -i "$mac"); #FIX for 'since a few days this binary can no longer be found'
  local startDate=$(date +%s);
  local vmIP=$(echo $arpOut | cut -d' ' -f2 | sed 's,(,,g' | sed 's,),,g');
  local msg="";
  local res;
  local tmp;
  local foundMac;

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
  local count=0;
  while [ $count -lt $VCPUS ]; do
    # when we request i.e. 16 vcpus we get 16 ranks
    # so use VCPUS for amount of ranks
    echo "$vmIP" >> $LOCAL_VM_IP_FILE;
    count=$((count + 1));
  done
  logTraceMsg "VM IPs cached in file '$LOCAL_VM_IP_FILE':\n-----\n$(cat $LOCAL_VM_IP_FILE)\n-----";

  local vmIsAvailCmd;
  local successCode;
  local protocol;

  # protocol and code for availability check depends on guest distro
  if [[ $DISTRO =~ $REGEX_OSV ]]; then
    vmIsAvailCmd="curl --connect-timeout 2 http://$vmIP:8000";
    successCode=200;
    protocol="HTTP";
  else
    vmIsAvailCmd="ssh -n -o BatchMode=yes -o ConnectTimeout=2 $vmIP exit";
    successCode=0;
    protocol="SSH";
  fi

  # wait for VM to become ready
  logDebugMsg "Distro is '$DISTRO', using protocoll '$protocol' to check if guest is available.";
  logTraceMsg "Command to check VM availability via '$protocol':\n $vmIsAvailCmd";
  while [ $($vmIsAvailCmd &>/dev/null; echo $?) -ne $successCode ]; do

    # cancelled meanwhile ?
    checkCancelFlag;

    # check remote hosts for errors and abort flag
    checkRemoteNodes;

    # wait a moment before checking again
    logDebugMsg "Waiting for VM ($mac / $vmIP) to become available via $protocol ..";
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

      # requires root rights usually,
      # but chmod is applied via metadata by cloud-init
      logDebugMsg "Fetching syslog from '$vmIP'".
      scp $SCP_OPTS $vmIP:$sysLogFile $VM_JOB_DIR/$LOCALHOST/syslog_$vhostName.log;

    # else:
    #   OSv doesn't have a dedicated cloud-init log.
    #   Relevant info is written to console
    fi
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

# ensure pre-conditions are met
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

# measure time ?
if $MEASURE_TIME; then
  printRuntime $0 $START;
fi

# return exit code
exit $res;

