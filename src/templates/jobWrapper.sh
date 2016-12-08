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
# FILE:
#  jobWrapper.sh
#
# DESCRIPTION:
#  Torque JobWrapper script that wraps the actual job script to be executed
#  in a running virtual machine.
#  It prepares the VM's environment and starts user's job script.
#
#
# Date         Version   Change             Author
#  20.10.2015    0.1      Skeleton           Nico Struckmann
#  15.10.2015    0.2      Implementation     Uwe Schilling
#  01.02.2016    0.3      BugFixes           Nico Struckmann
#
#
#
#
__INLINE_RES_REQUESTS__

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
# Indicates to keep the VM alive after the job has ran.
#
KEEP_VM_ALIVE=__KEEP_VM_ALIVE__;

#
# Amount of VMs per allocated physical node.
#
VMS_PER_NODE=__VMS_PER_NODE__;


# PBS_JOBID set in environment ?
if [ -z ${PBS_JOBID-} ] \
    || [ ! -n "$PBS_JOBID" ]; then
  # no, assuming debug/test execution
  if [ $# -lt 1 ]; then
    echo "PBS_JOBID is not set! usage: $(basename ${BASH_SOURCE[0]}) <jobID>"; # relevant if not executed by Torque, but manually
    exit 1;
  else
    export PBS_JOBID=$1;
  fi
fi


#
# load config and constants, after initialization of placeholder-vars above
#
source "$SCRIPT_BASE_DIR/common/const.sh";
source "$SCRIPT_BASE_DIR/common/config.sh";
source "$SCRIPT_BASE_DIR/common/functions.sh";


##############################################################################
#                                                                            #
#                       GENERATED VALUES / VARIABLES                         #
#                                                                            #
##############################################################################


#
# The wrapped job script to execcute. In case of a STDIN job we cannot execute it directly,
# but need to cat its contents into the VM's shell
#
JOB_SCRIPT=__JOB_SCRIPT__;

#
# Job type to wrap. Will be set by the qsub wrapper when the job specific script
# is generated based on this template.
# Valid job types are: @BATCH_JOB@, @STDIN_JOB@, @INTERACTIVE_JOB@
#
JOB_TYPE=__JOB_TYPE__;

#
# amomunt of VM cores that need to be applied as PBS_NUM_PPN into the VM's env
#
VCPUS=__VCPUS__;

#
# First VM in the VM node list, will be determined at runtime.
#
FIRST_VM="";


##############################################################################
#                                                                            #
#                              FUNCTIONS                                     #
#                                                                            #
##############################################################################


#----------------------------------------------------------
#
# Checks whether required env-vars,
# files, etc we need do exist.
#
#
checkPreConditions() {

  # do we have a PBS environment ?
  if [ ! -n "$(env | grep PBS)" ]; then # no
    # check if this is a debugging run and the env has been dumped before to disk
    if [ -f "$VM_JOB_DIR/pbsHostEnvironment" ]; then
      source $VM_JOB_DIR/pbsHostEnvironment;
    else
      logErrorMsg "No PBS env available! Cannot run job!";
    fi
  fi

  # ensure the PBS node file (vmIPs) is there
  if [ ! -f "$PBS_VM_NODEFILE" ]; then
    logErrorMsg "File PBS_VM_NODEFILE '$PBS_VM_NODEFILE' not found!";
  fi

  # dump the env when debugging (do not overwrite when debugging a failed run)
  if $DEBUG && [ ! -e "$VM_JOB_DIR/pbsHostEnvironment" ]; then
    env | grep PBS > $VM_JOB_DIR/pbsHostEnvironment.dump;
    env > $VM_JOB_DIR/fullHostEnvironment.dump;
  fi

  if [ ! -n "${VMS_PER_NODE-}" ] \
      || [ "$VMS_PER_NODE" == "__VMS_PER_NODE__" ]; then
    logErrorMsg "Parameter 'VMS_PER_NODE' not set: '$VMS_PER_NODE' !";
  fi

  # does the job dir exist ?
  if [ ! -d $VM_JOB_DIR ]; then # no, abort
    logErrorMsg "VM job data dir '$VM_JOB_DIR' does not exist, cannot run job!\nDir: \$VM_JOB_DIR='$VM_JOB_DIR'";
  fi

  # does the nodes file exist ?
  if [ -z $PBS_NODEFILE ] || [ ! -f $PBS_NODEFILE ]; then
    logErrorMsg "No PBS node file available, cannot run job!\nFile: \$PBS_NODEFILE='$PBS_NODEFILE'.";
  fi

  # does the vNodes file exist ?
  if [ -z $PBS_VM_NODEFILE ] || [ ! -f $PBS_VM_NODEFILE ]; then
    logErrorMsg "No PBS VM node file available, cannot run job!\File: \$PBS_VM_NODEFILE='$PBS_VM_NODEFILE'.";
  fi

  # amount of virtual cores known and valid ?
  if [ -z $VCPUS ] || [ $VCPUS -lt 1 ]; then
    logWarnMsg "No VCPUS available, using defaults.";
    # use default
    VCPUS=VCPUS_DEFAULT;
  fi

}


#---------------------------------------------------------
#
# Sets the first VM in the VM node list as '$FIRST_VM'.
#
setRank0VM() {
  FIRST_VM="$(head -n1 $PBS_VM_NODEFILE)";
  # ensure the rank0 VM is known (implies that the merged vNodesFile could be read)
  if [ -z ${FIRST_VM-} ]; then
    logErrorMsg "Rank0 VM is not set! PBS_VM_NODESFILE is '$PBS_VM_NODEFILE'";
      exit 1;
  fi
}


#---------------------------------------------------------
#
# Generates a file that contains the
# required VM's environment VARs on each bare metal host.
#
# see http://docs.adaptivecomputing.com/torque/6-0-1/help.htm#topics/torque/2-jobs/exportedBatchEnvVar.htm
createJobEnvironmentFiles() {

  logDebugMsg "Generating job's VM environment files";

  # create for each VM an individual PBS environment file
  for computeNode in $(cat $PBS_NODEFILE | uniq); do

    logDebugMsg "Creating individual PBS env for VM(s) on host '$computeNode'.";
    # construct the file name to that we write the following exports
    pbsVMsEnvFile="$VM_ENV_FILE_DIR/$computeNode/vmJobEnvironment";

    # write all PBS env vars into a dedicated vm job env file (one per physical host)
    echo "\
# even if we change it in the VM's env, mpirun still looks/checks for the path
# that is also stored in '$PBS_NODEFILE'
export PBS_NODEFILE='$PBS_NODEFILE';
export PBS_O_HOST='$PBS_O_HOST';
export PBS_O_QUEUE='$PBS_O_QUEUE';
export PBS_O_WORKDIR='$PBS_O_WORKDIR';
export PBS_ENVIRONMENT='$PBS_ENVIRONMENT';
export PBS_JOBID='$PBS_JOBID';
export PBS_JOBNAME='$PBS_JOBNAME';
export PBS_O_HOME='$PBS_O_HOME';
export PBS_O_PATH='$PBS_O_PATH';
export PBS_VERSION='$PBS_VERSION';
export PBS_TASKNUM='$PBS_TASKNUM';
export PBS_WALLTIME='$PBS_WALLTIME';
export PBS_GPUFILE='$PBS_GPUFILE';
#export PBS_MOMPORT='$PBS_MOMPORT';
export PBS_O_LOGNAME='$PBS_O_LOGNAME';
export PBS_O_LANG='$PBS_O_LANG';
export PBS_JOBCOOKIE='$PBS_JOBCOOKIE';
export PBS_NODENUM='$PBS_NODENUM';
export PBS_NUM_NODES='$PBS_NUM_NODES';
export PBS_O_SHELL='$PBS_O_SHELL';
export PBS_VNODENUM='$PBS_VNODENUM';
export PBS_MICFILE='$PBS_MICFILE';
export PBS_O_MAIL='$PBS_O_MAIL';
export PBS_NP='$VCPUS'; #'$PBS_NP';
export PBS_NUM_PPN='$PBS_NUM_PPN';
export PBS_O_SERVER='$PBS_O_SERVER';
# added
export PBS_VMS_PN='VMS_PER_NODE';" > $pbsVMsEnvFile;

    #
    # create one for each VM (multi VMs per host)
    # for each VM on computeNode generate an individual one,
    # based on the one per compute-node
    #
    number=1;
    while [ $number -le $VMS_PER_NODE ]; do

      # construct VM's name
      vNodeName="v${computeNode}-${number}";
      logDebugMsg "Creating individual PBS env for VM '$vNodeName'.";

      # construct dest dir name for VM's PBS env file
      destDir="$VM_ENV_FILE_DIR/$computeNode/$vNodeName";

      # ensure dir exists
      mkdir -p $destDir \
        || logErrorMsg "Creating destination dir '$destDir' for VM job environment failed!";

      # write file
      cat $pbsVMsEnvFile > "$destDir/vmJobEnvironment"; #name must be in sync with metadata file

      # increase coutner
      number=$(($number + 1));

      # logging
      logTraceMsg "Created PBS environment for VM '':¸\n-----\n$(cat $destDir/vmJobEnvironment)\n-----";

      # stage file in case file-sys is not shared with VMs
      #ensureFileIsAvailableOnHost $pbsVMsEnvFile $vNode; #FIXME: destination path is another one: see metadata mountpoint

      # print complete VM env file
      logTraceMsg "\n~~~~~~~~PBS JOB ENVIRONMENT FILE for VMs on vhost '$vNodeName' START~~~~~~~~\n\
$(ssh $SSH_OPTS $vNodeName 'source /etc/profile; env;')\
\n~~~~~~~~PBS JOB ENVIRONMENT FILE for VMs on vhost '$vNodeName' END~~~~~~~~";

    done
  done
}


#---------------------------------------------------------
#
# Executes user's batch job.
#
runBatchJob(){
  # the first node in the list is 'rank 0'
  logDebugMsg "Executing BATCH job script '$JOB_SCRIPT' on first vNode '$FIRST_VM'.";
  # test if job script is available inside VM, if not stage it
  ensureFileIsAvailableOnHost $JOB_SCRIPT $FIRST_VM;
  # construct the command to execute via ssh
  cmd="source /etc/profile; exec $JOB_SCRIPT;";
  # execute command
  logDebugMsg "Command to execute: 'ssh $SSH_OPTS $FIRST_VM \"$cmd\"'";
  logDebugMsg "===============JOB_OUTPUT_BEGIN====================";
  if $DEBUG; then
    ssh $FIRST_VM "$cmd" |& tee -a $LOG_FILE;
  else
    ssh $FIRST_VM "$cmd";
  fi
  # store the return code (ssh returns the return value of the command in
  # question, or 255 if an error occurred in ssh itself.)
  result=$?
  logDebugMsg "================JOB_OUTPUT_END=====================";
  return $result;
}


#---------------------------------------------------------
#
# Executes user's STDIN job.
#
runSTDinJob(){
  # the first node in the list is 'rank 0'
  logDebugMsg "Executing STDIN job '$JOB_SCRIPT' on first vNode '$FIRST_VM'.";
  # construct the command to execute via ssh
  cmd=$(echo -e "source /etc/profile;\n $(cat $JOB_SCRIPT)");
  # execute command
  logDebugMsg "Command to execute: 'ssh $SSH_OPTS $FIRST_VM \"$cmd\"'";
  logDebugMsg "===============JOB_OUTPUT_BEGIN====================";
  ssh $FIRST_VM "$cmd";
  # store the return code (ssh returns the return value of the command in
  # question, or 255 if an error occurred in ssh itself.)
  result=$?
  logDebugMsg "================JOB_OUTPUT_END=====================";
  return $result;
}


#---------------------------------------------------------
#
# Executes user's interactive job.
#
runInteractiveJob(){
  # the first node in the list is 'rank 0'
  logDebugMsg "Executing INTERACTIVE job on first vNode '$FIRST_VM'.";
  # construct the command to execute via ssh
  cmd='/bin/bash -i';
  # execute command
  logDebugMsg "Command to execute: 'ssh $FIRST_VM \"$cmd\"'";
  logDebugMsg "============INTERACTIVE_JOB_BEGIN==================";
  # check if we are running with 'qsub -I -X'
  xIsRequested=true;
  if $xIsRequested; then
    ssh -X $FIRST_VM "$cmd";
  else
    ssh $FIRST_VM "$cmd";
  fi
  # store the return code (ssh returns the return value of the command in
  # question, or 255 if an error occurred in ssh itself.)
  result=$?
  logDebugMsg "=============INTERACTIVE_JOB_END===================";
  return $result;
}


#---------------------------------------------------------
#
# Abort function that is called by the (global) signal trap.
#
_abort() {
  exitCode=0;
  # VM clean up happens in the vmEpilogue.sh
  logWarnMsg "Canceling job execution.";
  return $exitCode;
}




##############################################################################
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
##############################################################################

# debugging output
logDebugMsg "***************** START OF JOB WRAPPER ********************";

# make sure everything needed is in place
checkPreConditions;

# set rank0 VM
setRank0VM;

# create the file containing the required PBS VARs
createJobEnvironmentFiles;

#
# execute the actual user job
#
logDebugMsg "Job-Type to execute: $JOB_TYPE";

# what kind of job is it ? (interactive, STDIN, batch-script)
if [ "$JOB_TYPE" == "@BATCH_JOB@" ]; then
  # batch
  logDebugMsg "Executing user's job ..";
  runBatchJob;
  JOB_EXIT_CODE=$?;
elif [ "$JOB_TYPE" == "@STDIN_JOB@" ]; then
  # stdin
  logDebugMsg "Executing user's piped-in job script ..";
  runSTDinJob;
  JOB_EXIT_CODE=$?;
elif [ "$JOB_TYPE" == "@INTERACTIVE_JOB@" ]; then
  #interactive
  logDebugMsg "Executing user's interactive job ..";
  runInteractiveJob;
  JOB_EXIT_CODE=$?;
else
  echo "ERROR: unknown type of job: '$JOB_TYPE' !";
fi
logDebugMsg "Job has been executed, return Code: $JOB_EXIT_CODE";

# are we debugging and is keep alive requested ?
if $DEBUG && $KEEP_VM_ALIVE; then
  logDebugMsg "Pausing job wrapper, it is requested to keep the VMs alive.";
  logInfoMsg "To continue execution, run cmd: 'touch $FLAG_FILE_CONTINUE'.";
  breakLoop=false;
  while [ ! -f "$FLAG_FILE_CONTINUE" ]; do
    checkCancelFlag;
    sleep 1;
  done
  rm -f $FLAG_FILE_CONTINUE;
  logDebugMsg "Continuing execution.";
fi

# debug log
logDebugMsg "***************** END OF JOB WRAPPER ********************";

# print the consumed time in debug mode
runTimeStats;

# return job exit code
exit $JOB_EXIT_CODE;
