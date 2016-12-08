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

    # timeout is 150 sec
    isTimeoutReached 150 $startDate;

    # cancelled meanwhile ?
    checkCancelFlag;

  done
  if [ ! -n "$(ls $DOMAIN_XML_PATH_NODE/*.xml)" ]; then
    logErrorMsg "Files for node have been generated, but no domain XML files could be found.";
  fi
}


#---------------------------------------------------------
#
# Starts all the VM(s) dedicated to the current copmute nodes
# where the script is executed.
#
bootVMs() {

  # wait for needed files to come into place
  _waitForFiles;

  # check if there is an error on remote hosts
  checkRemoteNodes;

  # now the domain XMLs should be available
  declare -a VM_DOMAIN_XML_LIST=($(ls $DOMAIN_XML_PATH_NODE/*.xml));
  totalCount=${#VM_DOMAIN_XML_LIST[@]};

  # let remote processes know that we started our work
  informRemoteProcesses;

  # boot all VMs dedicated to the current node we run on
  i=1;
  for domainXML in ${VM_DOMAIN_XML_LIST[@]}; do

    # construct filename of metadata yaml file that was used to create the seed.img
    metadataFile="$VM_JOB_DIR/$LOCALHOST/${i}-metadata";
    # grep vhostname from metadata file
    vHostName=$(grep 'hostname: ' $metadataFile | cut -d' ' -f2);

    # create the dir that will be shared with VM
    logDebugMsg "Creating dir '$VM_NODE_FILE_DIR' for VM's nodefile.";
    mkdir -p $VM_ENV_FILE_DIR/$LOCALHOST/$vHostName || logErrorMsg "Failed to create env file dir for VMs!";

    # boot VM
    logDebugMsg "Booting VM number '$i/$totalCount' on compute node '$LOCALHOST' from domainXML='$domainXML'.";
    if $DEBUG; then
      vmLogFile=$VMLOG_FILE_PREFIX/$i-libvirt.log;
      output=$(virsh $VIRSH_OPTS --log $vmLogFile create $domainXML |& tee -a $LOG_FILE);
    else
      output=$(virsh $VIRSH_OPTS create $domainXML);
    fi
    res=$?;
    logDebugMsg "virsh create cmd output:\n'$output'";

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

    # grep the mac address from the domainXML
    mac=$(grep -i '<mac' $domainXML | cut -d"'" -f 2);
    if [ ! -n "$mac" ]; then
      logErrorMsg "No MAC found for VM '$vmName' in domain XML file: '$domainXML' !";
    fi

    # wait until SSH server becomes available
    if $PARALLEL; then
      # async
      _waitForVMtoBecomeAvailable "v$LOCALHOST-$i" "$mac" & echo -n "";
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
  logDebugMsg "Starting '$totalCount' VMs on node '$LOCALHOST' was successful, VMs are booting now..";

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

  # create lock file
  logDebugMsg "Waiting for VM '$vhostName' with MAC='$mac', using lock dir: '$LOCKFILES_DIR'";
  lockFile="$LOCKFILES_DIR/$mac";
  touch $lockFile;

  # wait until it the VM has requested an IP
  arpOut=$(/usr/sbin/arp -an | grep -i "$mac"); #FIX for 'since a few days this binary can no longer be found'
  startDate=$(date +%s);
  vmIP=$(echo $arpOut | cut -d' ' -f2 | sed 's,(,,g' | sed 's,),,g');
  msg="";

  # watch out for VM's MAC in arp's output (that appears together with its IP)
  while [ ! -n "$arpOut" ]; do

    # abort ?
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
    arpOut=$(/usr/sbin/arp -an | grep -i "$mac");
    logTraceMsg "Output of arp for vNode '$vhostName': '$arpOut'";

    # already found ?
    if [ -n "$arpOut" ]; then

      # grep VM's IP from arp output
      vmIP=$(echo -n $arpOut | cut -d' ' -f2 | sed 's,(,,g' | sed 's,),,g');
      if [ ! -n "$vmIP" ]; then
        logErrorMsg "Command 'arp -an' failed, output: '$arpOut'";
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
      fi

      # if we have found an IP let's check the mac of this host
      if [ -n "$vmIP" ]; then

        # check if arp knowns already the MAC for VM's IP
        tmp=$(/usr/sbin/arp -an | grep -i "$vmIP");

        # grep mac and make it lower case
        foundMac=$(echo $tmp | cut -d' ' -f5 | tr '[:upper:]' '[:lower:]');

        # any mac found ?
        if [ ! -n "$foundMac" ]; then
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
  while [ 255 -eq $(ssh -n -o BatchMode=yes -o ConnectTimeout=2 $vmIP exit; echo $?) ]; do

    # cancelled meanwhile ?
    checkCancelFlag;

    # check remote hosts for errors and abort flag
    checkRemoteNodes;

    # wait a moment before we try it again
    logDebugMsg "Waiting for VM's ($mac / $vmIP) SSH server to become available..";
    sleep 1;

    # timeout reached ?
    isTimeoutReached $TIMEOUT $startDate true;
    res=$?;
    if [ $res -eq 0 ]; then
      msg="Aborting.\n Timeout of '$TIMEOUT' sec reached \
and VM '$vhostName' with MAC='$mac' is still not available via SSH.";
      indicateRemoteError "$lockFile" "$msg";
    fi

  done

  # success
  logDebugMsg "VM's ($mac / $vmIP) SSH server is now available.";

  # fetch the cloud-init log if debugging
  if $DEBUG; then
    destFile="$VM_JOB_DIR/$LOCALHOST/cloud-init_$vhostName.log";
    logDebugMsg "Fetching cloud-init.log from '$vmIP' as '$destFile'.".
    scp $SCP_OPTS $vmIP:$CLOUD_INIT_LOG $destFile;
    # standard linux or OSv ?
    if [[ "$DISTRO" =~ REGEX_OSV ]]; then
      # TODO replace SSH by HTTP RESTful call
      ssh $SSH_OPTS $vmIP 'dmesg' > $VM_JOB_DIR/$LOCALHOST/syslog_$vhostName.log;
    else

      # determine syslog filename
      if [[ "$DISTRO" =~ REGEX_DEBIAN ]]; then
        sysLogFile=$SYS_LOG_FILE_DEBIAN;
      elif  [[ "$DISTRO" =~ REGEX_REDHAT ]]; then
        sysLogFile=$SYS_LOG_FILE_RH;
      else
        logErrorMsg "Unknown distro '$DISTRO'!";
      fi

      #requires root rights, chmod applied via metadata in cloud-init
      logDebugMsg "Fetching syslog from '$vmIP'".
      scp $SCP_OPTS $vmIP:$sysLogFile $VM_JOB_DIR/$LOCALHOST/syslog_$vhostName.log;
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

checkPreconditions;

# ensure that we do not loose anything for debug.log
captureOutputStreams;

# boot all (localhost) VMs
bootVMs;
res=$?;

# debug log
logDebugMsg "************** END OF JOB PROLOGUE.PARALLEL ******************";

# print the consumed time in debug mode
runTimeStats;

# return exit code
exit $res;

