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
# Contains all common functions for the HPC integration of VMs.
#
##############################################################################
#                                                                            #
# IMPORTANT NOTE:                                                            #
# ===============                                                            #
#  Import the config.sh and const.sh before you import this file!            #
#                                                                            #
##############################################################################
#
#
set -o nounset;

#-----------------------------------------------------------------------------
#
# Signal traps for cancellation (VM clean ups)
#
# The abort function needs to override the dummie function '_abort' in each
# script that uses the functions.sh
#
trap abort SIGHUP SIGINT SIGTERM SIGKILL;



#---------------------------------------------------------
#
# override mapping function dummy
#
log4bsh_mapName() {

  local runningScript=$1;

  runningScript="${process%%.sh}"; # cut off .sh extension
  runningScript="${runningScript##-*}";  # cut off leading '-'
  runningScript="$(basename $runningScript)";

  if [[ "$runningScript" =~ "$JOBID.SC" ]]; then
    runningScript="jobWrapper";
  fi

  echo $runningScript;
}

#
# Exit hook, called if there's an error msg triggered.
#
log4bsh_exitHook() {
  abort;
}


#---------------------------------------------------------
#
# Checks if a path is available in the VM.
# If not creating it will be tried. In case of a failure we abort.
#
ensurePathExistsOnHost() {

  local cachedBashOpts="$-";
  _unsetXFlag $cachedBashOpts;

  dirToCheck="$1"; #path
  destinationHost="$2"; #FIRST_VM

  # check if we need to create the directory
  res=$(ssh $SSH_OPTS $destinationHost "if [ -d '$dirToCheck' ]; then echo 'OK'; fi");
  if [ "$res" != "OK" ]; then
    # this is not expected by the user, so let's tell him
    logWarnMsg "The path '$dirToCheck' cannot be found in the VM's file-system ! Creating it now..";
    # path not present, we need to create it
    ssh $SSH_OPTS $SSH_OPTS $destinationHost "mkdir -p $dirToCheck";
    if [ ! $? ]; then
      logErrorMsg "Path '$fileToCheck' not present in VM '$destinationHost' and creating it failed ! Aborting.";
    fi
  fi

  # renable if it was enabled before
  _setXFlag $cachedBashOpts;
}


#---------------------------------------------------------
#
# Checks if the job script is available in the VM.
# If not staging will be tried. In case of a failure we abort.
#
ensureFileIsAvailableOnHost() {

  local cachedBashOpts="$-";
  _unsetXFlag $cachedBashOpts;

  if [ $# -ne 2 ]; then
    logErrorMsg "Function 'ensureFileIsAvailableOnHost' expects '2' parameters, provided '$#'\nProvided params are: '$@'" 2;
  fi

  fileToCheck=$1; #JOB_SCRIPT
  destinationHost=$2; #FIRST_VM

  if [ ! -n "$destinationHost" ]; then
    logWarnMsg "No VMs found to ensure file '$fileToCheck' is available.";
    return 1;
  fi

  # check if we need to stage the file
  res=$(ssh $SSH_OPTS $destinationHost "if [ -f '$fileToCheck' ]; then echo 'OK'; fi");
  if [ "$res" != "OK" ]; then
    # this is not expected by the user, so let's tell him
    logWarnMsg "The file '$fileToCheck' cannot be found in the VM's file-system ! Staging missing file now..";
    # make sure path exists
    ensurePathExistsOnHost $(dirname $fileToCheck) $destinationHost;
    # job script not present, we need to stage it
    if $TRACE; then
      logTraceMsg "+++++++++++++++ SCP VERBOSE LOG START ++++++++++++++++";
      scp $SCP_OPTS $fileToCheck $destinationHost:$fileToCheck |& tee $LOG_FILE;
      logTraceMsg "+++++++++++++++ SCP VERBOSE LOG END +++++++++++++++++";
    else
      scp $SCP_OPTS $fileToCheck $destinationHost:$fileToCheck |& tee $LOG_FILE;
    fi
    if [ ! $? ]; then
      logErrorMsg "Job script '$fileToCheck' not present in VM '$destinationHost' and staging failed ! Aborting.";
    fi
  fi

  # re-enable verbose logging if it was enabled before
  _setXFlag $cachedBashOpts;

  return 0;
}


#---------------------------------------------------------
#
# Checks if timeout is reached. If yes it aborts with error
# msg.
#
# Param $1: timeout in sec
# Param $2: start date in sec (i.e. startDate=$(date +%s) )
#
#
isTimeoutReached() {

  # disable verbose logging
  local cachedBashOpts="$-";
  _unsetXFlag $cachedBashOpts;

  if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    logErrorMsg "Function 'isTimeoutReached' expects '2-3' parameters, provided '$#'\nProvided params are: '$@'" 2;
  fi

  timeout=$1;
  startDate=$2;
  if [ $# -eq 3 ]; then
    doNotExit=$3;
  else # default is false (exit process = yes)
    doNotExit=false;
  fi
  timeoutFlag=false;

  # timeout reached ?
  if [ $timeout -lt $(expr $(date +%s) - $startDate) ]; then
    msg="Timeout of '$timeout' seconds reached while waiting for remote processes to finish their work.!";
    # timeout reached, abort
    if $doNotExit; then
     logWarnMsg $msg;
     timeoutFlag=true;
    else # abort
     logErrorMsg $msg;
   fi
  fi

  # cancel flag ?
  if [ -f "$CANCEL_FLAG_FILE" ]; then
    logWarnMsg "Abort flag file '$CANCEL_FLAG_FILE' found, canceling wait sequence.";
    timeoutFlag=true;
  fi
  # re-enable verbose logging if it was enabled before
  _setXFlag $cachedBashOpts;
  if $timeoutFlag; then
    return 0;
  fi
  return 1;
}


#---------------------------------------------------------
#
# Creates lock files dir if not in place and puts the hostname
# into the global lock, so master process knows we are running
#
informRemoteProcesses() {

  # create lock files dir
  if [ ! -d $LOCKFILES_DIR ]; then # a sister process may have created it
    logTraceMsg "Creating lock files dir '$LOCKFILES_DIR'.";
    mkdir -p $LOCKFILES_DIR;
  fi

  # indicate master process we are running (workaround for remote processes finished to fast)
  if [ ! -f $LOCKFILE ] \
      || [ ! -n "$([ -f "$LOCKFILE" ] && grep $LOCALHOST $LOCKFILE)" ]; then
    if [ ! -f $LOCKFILE ]; then
      logDebugMsg "Creating lock file '$LOCKFILE'.";
    fi
    echo "$LOCALHOST" >> $LOCKFILE;
  fi
}


#---------------------------------------------------------
#
# Waits until all flag files are removed.
# Flag files are created/removed by the parallel scripts
# before boot/when the SSH server is available
# or in case of tear down when user disk is copied back and VM(s) destroyed
#
waitUntilAllReady() {

  startDate="$(date +%s)";

  logDebugMsg "Waiting for lock-file '$LOCKFILE' to be created..";
  logDebugMsg "And waiting for equal content in files \$PBS_NODEFILE='$PBS_NODEFILE' and \$LOCKFILE='$LOCKFILE' ..";


  #
  # wait for all remote processes to start their work
  # each remote process writes its hostname into the lock file,
  # so we can compare it to the PBS host list
  #
  while [ ! -f $LOCKFILE ] \
          || [ "$(cat $PBS_NODEFILE | sort | uniq)" != "$(cat $LOCKFILE | sort)" ]; do

    # abort ?
    if [ -f "$CANCEL_FLAG_FILE" ]; then
      logWarnMsg "Cancel flag file '$CANCEL_FLAG_FILE' found, aborting now.";
      abort;
    fi

    # check if an error occurred before lock files could be created
    checkRemoteNodes;

    # timeout reached ?
    isTimeoutReached $TIMEOUT $startDate true;
    res=$?;
    if [ $res -eq 0 ]; then
      # timeout reached, abort
      logErrorMsg "Timeout of '$timeout' seconds reached while waiting for \
remote processes to finish their work.!\nLock file content:\n---\n$(cat $LOCKFILE)\n---\n";
    fi

    # wait for a moment
    logTraceMsg "Waiting for lock-file '$LOCKFILE' to be created..";
    logTraceMsg "And waiting for equal content in files \$PBS_NODEFILE='$PBS_NODEFILE' and \$LOCKFILE='$LOCKFILE' ..";
    sleep 2;

  done

  logDebugMsg "lock-file '$LOCKFILE' is in place and content in files \$PBS_NODEFILE='$PBS_NODEFILE' and \$LOCKFILE='$LOCKFILE' is equal, continuing."

  # any locks remaining (clean up is fast!) ?
  while [ -d "$LOCKFILES_DIR" ] && [ -n "$(ls $LOCKFILES_DIR/)" ]; do

    # abort ?
    if [ -f "$CANCEL_FLAG_FILE" ]; then
      logWarnMsg "Abort flag file '$CANCEL_FLAG_FILE' found, aborting now.";
      abort;
    fi

    # check the lock files's content for any error msgs (non-empty file means error msg inside)
    checkRemoteNodes;

    # tell what's happening
    logDebugMsg "Waiting for '$(ls $LOCKFILES_DIR | wc -w)' locks to disappear from (shared-fs) dir '$LOCKFILES_DIR' ..";
    logTraceMsg "Locks still in place for MACs:\n---\n$(ls $LOCKFILES_DIR)\n---";
    # timeout reached ?
    isTimeoutReached $TIMEOUT $startDate true;
    res=$?;
    if [ $res -eq 0 ]; then
      # timeout reached, abort
      logErrorMsg "Timeout of '$timeout' seconds reached while waiting for \
remote processes to finish their work.!";
    fi

    # wait a short moment for lock files to disappear
    sleep 1;

  done

  checkRemoteNodes;

  if [ ! -f "$CANCEL_FLAG_FILE" ]; then
    # done, locks are gone - clean up locks dir
    logDebugMsg "Locks are gone, all remote processes have finished - removing LOCKFILES_DIR='$LOCKFILES_DIR' and LOCKFILE='$LOCKFILE'.";
    rm -Rf $LOCKFILES_DIR;
    rm -f $LOCKFILE;
  fi


}


#---------------------------------------------------------
#
# Indicates remote processes that an error occurred and abort
# with given error msg that is also writen into the lock file.
#
# Parameter $1: lock file
# Parameter $2: error msg
#
indicateRemoteError() {

  if [ $# -ne 2 ]; then
    logErrorMsg "Function 'indicateRemoteError' expects '2' parameter, '$#' are given.\nProvided params are: '$@'" 2;
  fi
  lockFile=$1;
  msg=$2;

  # write error msg into lockFile, parent process checks this
  echo "[$LOCALHOST|ERROR] $msg" > $lockFile;
  # abort with error code 2 to trigger a cleanup in the parent vm prologue: i.e. kill all running VMs
  logErrorMsg $msg 2;
}


#---------------------------------------------------------
#
# Returns a static MAC for each VM.
# The IP is calculated by the help of the host's IP
# and the number of the VMs on that host (x of vmsPerNode)
#
getStaticMAC() {

  if [ $# -ne 3 ]; then
    logErrorMsg "Function 'getStaticMAC' expects '3' parameters, provided '$#'\nProvided params are: '$@'" 2;
  fi

  hostName=$1;
  vmsPerHost=$2;
  vmNrOnHost=$3;

  # generate suffix and create MAC out of it
  hexchars="0123456789ABCDEF";
  end=$( for i in {1..6} ; do echo -n ${hexchars:$(( $RANDOM % 16 )):1} ; done | sed -e 's/\(..\)/:\1/g' );
  mac="${MAC_PREFIX}${end}";

  # done, print to STDOUT
  echo "$mac";
}


#---------------------------------------------------------
#
# Checks if there is an error on some remote process, aborts
# with error msg if this is the case
#
checkRemoteNodes() {

  # check if an error occured before lock files could be created
  checkErrorFlag;

  # check the lock files's content for any error msgs (non-empty file means error msg inside)
  if [ -d "$LOCKFILES_DIR" ] \
       && [ -n "$(ls $LOCKFILES_DIR/)" ] \
       && [ -n "$(ls -l $LOCKFILES_DIR | tr -s ' ' | cut -d ' ' -f5 | grep -E [0-9]+ | grep -vE ^0$)" ]; then
    # an error occured during boot on a remote node, abort
    logErrorMsg "Error occured during boot on remote nodes: '$(find $LOCKFILES_DIR/ -maxdepth 1  -type f ! -size 0)'\n\
Errors:\n$(cd $LOCKFILES_DIR/ && for file in $(ls -l | tr -s ' ' | cut -d ' ' -f9); do cat \$file; done 2>/dev/null)";
  fi

  # abort flag present ?
  if [ -f "$ABORT_FLAG" ]; then
    # yes, (very likely the) master process requests cancel
    abort;
  fi
}


#---------------------------------------------------------
#
# Generates a MAC address with prefix '$MAC_PREFIX' and prints it to STDOUT.
#
generateMAC() {
  if $STATIC_IP_MAPPING; then
    vmsPerHost=$1;
    number=$2;
    mac="$(getStaticMAC $LOCALHOST $vmsPerHost $(expr $number % $vmsPerHost))";
  else
    # http://superuser.com/questions/218340/how-to-generate-a-valid-random-mac-address-with-bash-shell
    hexchars="0123456789ABCDEF"
    end=$( for i in {1..6} ; do echo -n ${hexchars:$(( $RANDOM % 16 )):1} ; done | sed -e 's/\(..\)/:\1/g' );
    mac="${MAC_PREFIX}${end}"; # generate, use prefix '52:54:00'
  fi
  echo $mac;
}

#---------------------------------------------------------
#
# Checks whether the execution has caused an error meanwhile
# by a parallel or remote process.
#
checkErrorFlag() {

  if [ $# -gt 0 ]; then
    doNotExit=$1;
  else
    doNotExit=true;
  fi

  if [ -f "$ERROR_FLAG_FILE" ]; then
    logWarnMsg "Failure during start of parallel VM boot on a node.";
    [ ! $doNotExit ] && abort;
    return 1;
  fi
  return 0;
}


#---------------------------------------------------------
#
# Checks whether the execution has been canceled meanwhile
# by a parallel or remote process.
#
checkCancelFlag() {

  if [ $# -gt 0 ]; then
    doNotExit=$1;
  else
    doNotExit=false;
  fi

  if [ -f "$CANCEL_FLAG_FILE" ]; then
    logWarnMsg "Abort flag file '$CANCEL_FLAG_FILE' found, aborting now.";
    [ ! $doNotExit ] && abort;
    return 1;
  fi
  return 0;
}


#---------------------------------------------------------
#
# Abort function that is called by the (global) signal trap.
#
abort() {
  # tell all processes to abort
  touch $CANCEL_FLAG_FILE;
  # error coe provided ?
  if [ $# -eq 1 ]; then
    if ! [[ $1 =~ ^[0-9]+$ ]]; then
      logTraceMsg "Non-Numeric error code provided to function 'abort': value='$1' !";
      exitCode=1; # default
    else
      exitCode=$1;
    fi
  else
    exitCode=1; # default
  fi
  # call running script's abort function;
  _abort;
  res=$?;
  # exit with combo of error codes
  exit $(($exitCode + ($res * 10)));
}


#---------------------------------------------------------
#
# dummy in case a script doesn't need to implement it
# if implemented it is expected to return in an error case a 2 digit integer
# that is suffied by a '0', example: -90,-80,..,0,10,20,..,90
# '0' for success
#
_abort() {
  echo -n "";
  logDebugMsg "Dummy function '_abort' is called.";
  return 0;
}
