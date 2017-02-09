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

#=============================================================================
#
#         FILE: vmEpilogue.sh
#
#        USAGE: vmEpilogue [<jobID>]
#
#  DESCRIPTION: Stops a VM with the help of libvirt (virsh).
#               Image is deleted (if not DEBUG is set to true)
#
#      OPTIONS: jobID - Will be used for the VM's name as shown by virsh
#                        Accept only if it is not in the envionment.
#                        This is true in when not executed inside Torque jobs.
#
# REQUIREMENTS: --
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Nico Struckmann, struckmann@hlrs.de
#      COMPANY: HLRS, University of Stuttgart
#      VERSION: 0.4
#      CREATED: Sept 30th 2015
#     REVISION: Feb2 4th 2016
#
#    CHANGELOG
#         v0.2: Bugfixes
#         v0.3: Moved the metadata generation to the prologue
#         v0.4: Debug logging extended.
#
#=============================================================================


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
# PBS_JOBID set in environment ?
# relevant if not executed by Torque, but manually
#
if [ -z ${PBS_JOBID-} ] \
    || [ ! -n "$PBS_JOBID" ]; then
  # no, assuming debug/test execution
  if [ $# -lt 1 ]; then
    logErrorMsg "PBS_JOBID is not set! usage: $(basename ${BASH_SOURCE[0]}) <jobID>";
  else
    export PBS_JOBID=$1;
  fi
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


#
# optional disk
#
DISK=__DISK__;

#
# optional user Epilogue to wrap
#
EPILOGUE_SCRIPT=__EPILOGUE_SCRIPT__;

#
# optional user VM Epilogue
VM_EPILOGUE_SCRIPT=__VM_EPILOGUE_SCRIPT__;

# rank0 VM, will be set in validate parameter
FIRST_VM="";

# exit code for this script
RES=0;


#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#


#---------------------------------------------------------
#
# Checks whether a wrapped user VM/EPILOGUE is present.
#
validateParameter() {

  if [ -z $EPILOGUE_SCRIPT ] || [ "$EPILOGUE_SCRIPT" == "__EPILOGUE_SCRIPT__" ]; then
    logDebugMsg "Optional parameter EPILOGUE_SCRIPT for VM is undefined.";
    EPILOGUE_SCRIPT=""; # default no (or static mapping ?)
  fi
  logDebugMsg " EPILOGUE_SCRIPT='$EPILOGUE_SCRIPT'";

  if [ -z $VM_EPILOGUE_SCRIPT ] || [ "$VM_EPILOGUE_SCRIPT" == "__VM_EPILOGUE_SCRIPT__" ]; then
    logDebugMsg "Optional parameter VM_EPILOGUE_SCRIPT for VM is undefined.";
    VM_EPILOGUE_SCRIPT=""; # default no (or static mapping ?)
  fi
  logDebugMsg " VM_EPILOGUE_SCRIPT='$VM_EPILOGUE_SCRIPT'";

  # determine first/rank0 node
  if [ -z ${PBS_VM_NODEFILE-} ] \
      || [ ! -f "$PBS_VM_NODEFILE" ]; then
    logErrorMsg "No PBS VM node file ?!";
  else
    FIRST_VM="$(head -n1 $PBS_VM_NODEFILE)";
  fi
}


#---------------------------------------------------------
#
# Executes user epilogue script that can optionally be
# defined by the user via PBS resource requests
#  i.e. 'qsub -l epilogue=..,'
#
#
runUserEpilogueScript() {
  # epilogue script given ?
  if [ -x  "$EPILOGUE_SCRIPT" ]; then
    logDebugMsg "Executing user's VM epilogue script now..";
    logDebugMsg "================EPILOGUE_OUTPUT_BEGIN====================";
    if $DEBUG; then
      $EPILOGUE_SCRIPT |& tee -a $LOG_FILE;
    else
      $EPILOGUE_SCRIPT;
    fi
    exitCode=$?;
    logDebugMsg "=================EPILOGUE_OUTPUT_END=====================";
    logDebugMsg "Exit Code: '$exitCode'";
    return $exitCode;
  fi
  return 0;
}


#---------------------------------------------------------
#
# Executes user VM epilogue script that can optionally be
# defined by the user via PBS resource requests
#  i.e. 'qsub -vm epilogue=..,'
#
runUserVMEpilogueScript() {
  # user VM Epilogue script present ?
  if [ -n "$VM_EPILOGUE_SCRIPT" ] && [ -f "$VM_EPILOGUE_SCRIPT" ]; then
    # present in VM ?
    ensureFileIsAvailableOnHost "$VM_EPILOGUE_SCRIPT" $FIRST_VM;
    if [ $? -ne 0 ]; then
      return 0;
    else
      # execute
      logDebugMsg "Executing user's VM epilogue script now..";
      logDebugMsg "==============VM_EPILOGUE_OUTPUT_BEGIN===================";
      if $DEBUG; then
        ssh $SSH_OPTS $FIRST_VM "exec $VM_EPILOGUE_SCRIPT" |& tee -a $LOG_FILE;
      else
        ssh $SSH_OPTS $FIRST_VM "exec $VM_EPILOGUE_SCRIPT";
      fi
      exitCode=$?;
      logDebugMsg "===============VM_EPILOGUE_OUTPUT_END====================";
      logDebugMsg "Exit Code: '$exitCode'";
      if [ ! $exitCode ]; then
        # abort with error code 2
        logErrorMsg "Execution of user's VM Epilogue failed." 2;
      fi
      return $exitCode;
    fi
  fi
  return 0;
}


#---------------------------------------------------------
#
# Destroys all VMs on given host
#
# Param $1: the host where to clean up VMs / run the vmEpilogue.parallel.sh
#
_destroyVMsOnHost() {

  if [ $# -ne 1 ]; then
    logErrorMsg "Function '_destroyVMsOnHost' called with '$#' arguments, '1' is expected.\nProvided params are: '$@'" 2;
  fi
  node=$1;

  # destroy VMs
  logTraceMsg "Running parallel epilogue on node '$node'.";
  ssh $SSH_OPTS $node "exec $(realpath $(dirname ${BASH_SOURCE[0]}))/vmEpilogue.parallel.sh $JOBID;"; # blocking
  exitCode=$?;

  # successful vm destroy init ? (shutdown/destroy still takes place now)
  if [ $exitCode -ne 0 ]; then
    # cleanup required
    logWarnMsg "Destroying VMs on node '$node' failed. Exit code: '$exitCode'." $exitCode;
  else
    logDebugMsg "VMs on node '$node' are being destroyed.";
  fi

  return $exitCode;
}


#---------------------------------------------------------
#
# Cleans up all VMs on all nodes, by running the vmPrologue.parallel.sh script
#
cleanUpAllVMs() {

  if [ $# -ne 1 ]; then
    logErrorMsg "Function 'cleanUpAllVMs' called with '$#' arguments, '1' is expected.\nProvided params are: '$@'" 2;
  fi

  nodes=$1;

  if [ -n "$nodes" ]; then
    # destroy all VMs on all nodes
    logDebugMsg "Running vmEpilogue.parallel.sh on all nodes.";
    for computeNode in $nodes; do
      # destroy VMs
      logDebugMsg "Destroying VMs on host '$computeNode'.";
      if $PARALLEL; then
        _destroyVMsOnHost $computeNode & continue;
      else
        _destroyVMsOnHost $computeNode;
      fi
    done
    # wait for VMs to disappear
    waitUntilAllReady;
  else
    # in error case just clean up
    logWarnMsg "No VMs associated to the current job are known, cleaning up all VMs."
    for guest in $(virsh list | grep $JOBID); do
      virsh $VIRSH_OPTS destroy $guest;
    done
  fi
  # clean up
  logDebugMsg "VMs are shut down and the user-disk (if any) is copied back.'";
}


#---------------------------------------------------------
#
# Abort function that is called by the (global) signal trap.
#
_abort() {
  logWarnMsg "Canceling job execution.\nWill not have much effect since we are already tearing down everything";
}



#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

# debug log
logDebugMsg "***************** BEGIN OF JOB EPILOGUE ********************";

# ensure that we do not loose anything for debug.log
captureOutputStreams;

#
validateParameter;

# get nodes to process
nodes="$(cat $PBS_NODEFILE | uniq)";
amountOfNodes="$(cat $PBS_NODEFILE | uniq | wc -l)";
logDebugMsg "Compute nodes ($amountOfNodes):\n-------\n$nodes\n-----";

if [ -n "$FIRST_VM" ]; then
  #
  runUserVMEpilogueScript;
  RES=$?;
else
  RES=0;
fi

# clean up all VMs on all nodes
cleanUpAllVMs "$nodes";

if [ -n "$FIRST_VM" ]; then
  #
  runUserEpilogueScript;
  tmp=$?;
  RES=$(expr $RES + $tmp);

  # print running VMs
  if $DEBUG; then
    for computeNode in $nodes; do
      # debug log
      msg=$(ssh $SSH_OPTS $computeNode "virsh list --all | grep -v 'shut off'");
      logTraceMsg "\nRunning VMs on compute node '$computeNode' :\n-----------\n$msg\n";
    done
  fi
else
  RES=0;
fi

# if we're not debugging, remove all generated files
if ! $DEBUG; then
  # remove all VM related files if we are not Debugging
  rm -Rf $VM_JOB_DIR;
fi

# debug log
logDebugMsg "***************** END OF JOB EPILOGUE ********************";
logDebugMsg "Job '$JOBID' completed.";

# print the consumed time in debug mode
runTimeStats;

# done, pass back return code
exit $RES;
