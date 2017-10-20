#!/bin/bash
#
# Copyright 2016-2017 HLRS, University of Stuttgart
#           2016-2017 XLAB
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
#         FILE: jobWrapper.sh
#
#        USAGE: n/a
#
#  DESCRIPTION: Job wrapper template with various placeholders. Maps the
#               PBS envrionment into the guest and starts user's job script.
#               For standard Linux guests SSH, for OSv HTTP will be used.
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Nico Struckmann, struckmann@hlrs.de
#               Uwe Schilling, uwe.schilling@hlrs.de,
#               Justin Cinkelj, justin.cinkelj@xlab.si
#      COMPANY: HLRS, University of Stuttgart
#               XLAB
#      VERSION: 0.4
#      CREATED: Oct 2nd 2015
#     REVISION: Jan 16th 2017
#
#    CHANGELOG
#         v0.2: [US] implementation added
#         v0.3: [NS] refactoring and clean up
#         v0.4: [JC] OSv support
#
#=============================================================================

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
# Indicates to keep the VM alive after the job has ran.
#
KEEP_VM_ALIVE=__KEEP_VM_ALIVE__;

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
source "$VTORQUE_DIR/common/const.sh";
source "$VTORQUE_DIR/common/config.sh";
source "$VTORQUE_DIR/common/functions.sh";



##############################################################################
#                                                                            #
#                       GENERATED VALUES / VARIABLES                         #
#                                                                            #
##############################################################################


#
# The wrapped job script to execcute. In case of a STDIN job we cannot execute
# it directly, but need to cat its contents into the VM's shell
#
JOB_SCRIPT=__JOB_SCRIPT__;

#
# Job type to wrap. Will be set by vsub when the job specific script
# is generated based on this template.
# Valid job types are: @BATCH_JOB@, @STDIN_JOB@, @INTERACTIVE_JOB@
#
JOB_TYPE=__JOB_TYPE__;

#
# amomunt of VM cores that need to be applied as PBS_NUM_PPN into the VM's env
#
VCPUS=__VCPUS__;

#
# Amount of VMs per allocated physical node.
#
VMS_PER_NODE=__VMS_PER_NODE__;

#
# Value is used to determine how to contrl the VM -
# via ssh (SLG) or via HTTP REST API (OSv).
# This is determined at template instantiation time.
#
DISTRO=__DISTRO__;

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
    if $DEBUG \
        && [ -f "$VM_JOB_DIR/$LOCALHOST/pbsHostEnvironment" ]; then
      source $VM_JOB_DIR/$LOCALHOST/pbsHostEnvironment;
    else
      logErrorMsg "No PBS env available! Cannot run job!";
    fi
  elif $DEBUG; then
    env | grep PBS > $VM_JOB_DIR/$LOCALHOST/pbsHostEnvironment.dump;
    env > $VM_JOB_DIR/$LOCALHOST/fullHostEnvironment.dump;
  fi

  # ensure the PBS node file (vmIPs) is there
  if [ ! -f "$PBS_VM_NODEFILE" ]; then
    logErrorMsg "File PBS_VM_NODEFILE '$PBS_VM_NODEFILE' not found!";
  fi

  # VMs per node defined ?
  if [ ! -n "${VMS_PER_NODE-}" ] \
      || [ "$VMS_PER_NODE" == "__VMS_PER_NODE__" ]; then
    logErrorMsg "Parameter 'VMS_PER_NODE' not set: '$VMS_PER_NODE' !";
  fi

  # does the job dir exist ?
  if [ ! -d "$VM_JOB_DIR" ]; then # no, abort
    logErrorMsg "VM job data dir '$VM_JOB_DIR' does not exist, cannot run job!\nDir: \$VM_JOB_DIR='$VM_JOB_DIR'";
  fi

  # does the nodes file exist ?
  if [ -z ${PBS_NODEFILE-} ] \
      || [ ! -f "$PBS_NODEFILE" ]; then
    logErrorMsg "No PBS node file available, cannot run job!\nFile: \$PBS_NODEFILE='$PBS_NODEFILE'.";
  fi

  # does the vNodes file exist ?
  if [ -z ${PBS_VM_NODEFILE-} ] || [ ! -f "$PBS_VM_NODEFILE" ]; then
    logErrorMsg "No PBS VM node file available, cannot run job!\File: \$PBS_VM_NODEFILE='$PBS_VM_NODEFILE'.";
  fi

  # amount of virtual cores known and valid ?
  if [ -z ${VCPUS-} ] || [ $VCPUS -lt 1 ]; then
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

  local pbsVMsEnvFile;
  local number;
  local vNodeName;
  local destDir;

  # create for each VM an individual PBS environment file
  for computeNode in $(cat $PBS_NODEFILE | uniq); do

    logDebugMsg "Creating individual PBS env for VM(s) on host '$computeNode'.";
    # construct the file name to that we write the following exports
    pbsVMsEnvFile="$PBS_ENV_FILE_PREFIX/$computeNode/vmJobEnvironment";

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
      destDir="$PBS_ENV_FILE_PREFIX/$computeNode/$vNodeName";

      # ensure dir exists
      mkdir -p $destDir \
        || logErrorMsg "Creating destination dir '$destDir' for VM job environment failed!";

      # write file
      cat $pbsVMsEnvFile > "$destDir/vmJobEnvironment"; #name must be in sync with metadata file

      # increase coutner
      number=$(($number + 1));

      # logging
      logTraceMsg "Created PBS environment for VM '$vNodeName':¸\n-----\n$(cat $destDir/vmJobEnvironment)\n-----";

      # print complete VM env file
      logTraceMsg "\n~~~~~~~~PBS JOB ENVIRONMENT FILE for VMs on vhost '$vNodeName' START~~~~~~~~\n\
$(ssh $SSH_OPTS $vNodeName 'source /etc/profile; env;')\
\n~~~~~~~~PBS JOB ENVIRONMENT FILE for VMs on vhost '$vNodeName' END~~~~~~~~";

    done
  done
}


#---------------------------------------------------------
#
# Executes user's batch job script in first/rank0 (standard
# linux guest) VM.
#
runBatchJobOnSLG() {

  # the first node in the list is 'rank 0'
  logDebugMsg "Executing SLG BATCH job script '$JOB_SCRIPT' on first vNode '$FIRST_VM'.";

  # test if job script is available inside VM, if not stage it
  ensureFileIsAvailableOnHost $JOB_SCRIPT $FIRST_VM;

  # construct the command to execute via ssh
  local cmd="source /etc/profile; exec $JOB_SCRIPT;";

  # execute command
  logDebugMsg "Command to execute: 'ssh $SSH_OPTS $FIRST_VM \"$cmd\"'";
  logDebugMsg "===============JOB_OUTPUT_BEGIN====================";
  if $DEBUG; then
    ssh $FIRST_VM "$cmd"; # |& tee -a "$LOG_FILE";
  else
    ssh $FIRST_VM "$cmd"; # 2>> "$LOG_FILE";
  fi
  # store the return code (ssh returns the return value of the command in
  # question, or 255 if an error occurred in ssh itself.)
  local result=$?
  logDebugMsg "================JOB_OUTPUT_END=====================";

  return $result;
}


#---------------------------------------------------------
#
# Executes user's batch job script in first/rank0 OSv VM.
#
runJobOnOSv() {

  local jobType;
  local curlCmd;
  local result;

  if [ "$JOB_TYPE" == "@STDIN_JOB@" ]; then
    jobType="BATCH";
  else
    jobType="STDIN";
  fi

  # the first node in the list is 'rank 0'
  logDebugMsg "Executing OSv $jobType job script '$JOB_SCRIPT' on first vNode '$FIRST_VM'.";

  #-------------------------------------------------------------
  # copy $PBS_VM_NODEFILE to /pbs_vm_nodefile. User cmd is assumed to be like
  # "mpirun -np NP -hostfile /pbs_vm_nodefile mpi_app.so"
  # curl -v -X POST http://192.168.122.90:8000/file/%2Ftmp%2Faa --form file=@aa
  echo "----------------------------"
  curlCmd="curl --connect-timeout 2 \
            -X POST http://$FIRST_VM:8000/file//pbs_vm_nodefile \
            --form file=@\"$PBS_VM_NODEFILE\" \
            -v";
  logDebugMsg "Upload PBS_VM_NODEFILE '$PBS_VM_NODEFILE' to /pbs_vm_nodefile, cmd:\n$curlCmd";
  if $DEBUG; then
    $curlCmd |& tee -a "$LOG_FILE";
  else
    $curlCmd &>> "$LOG_FILE";
  fi
  result=$?;
  if [ $result -ne 0 ]; then
    logErrorMsg "Failed to upload PBS_VM_NODEFILE '$PBS_VM_NODEFILE', error code: $result";
  fi
  logTraceMsg "----------------------------\n\
$(curl --connect-timeout 2 -X GET http://$FIRST_VM:8000/file//pbs_vm_nodefile?op=GET -v) \
\n----------------------------";

  # copy PBS_* environment variables into VM.
  # PBS_VM_NODEFILE is actually available at /pbs_vm_nodefile, so take that into account.
  # And similar for PBS_NP - see createJobEnvironmentFiles() above:
  #   export PBS_NP='$VCPUS'; #'$PBS_NP';
  local myEnvVars=$(set | grep "^PBS_");
  local key;
  local value;
  for key_val in $MY_ENV_VARS; do
    # allow '=' in value
    key=$(echo "$key_val" | sed 's/=.*$//')
    value=$(echo "$key_val" | sed 's/^[^=]*=//')
    if [ "$key" == "PBS_VM_NODEFILE" ]; then
      value="/pbs_vm_nodefile"
    fi
    if [ "$key" == "PBS_NP" ]; then
      value="$VCPUS"
    fi
    logDebugMsg "Setting in OSv environ: key=$key value=$value"
    curlCmd="curl --connect-timeout 2 \
              -X POST http://$FIRST_VM:8000/env/$key?val=$value"
    if $DEBUG; then
      $curlCmd |& tee -a "$LOG_FILE";
    else
      $curlCmd &>> "$LOG_FILE";
    fi
  done

  #
  # run job script
  #
  local cmd=$(cat "$JOB_SCRIPT");
  # execute command
  logDebugMsg "Command to execute: 'PUT http://$FIRST_VM:8000/app \"$cmd\"'";
  local tid=$(curl -X PUT http://$FIRST_VM:8000/app/ --data-urlencode command="$cmd")
  result=$?;
  if [ $result -ne 0 ]; then
    logErrorMsg "Failed to start application!\nError code '$result', cmd:\n$cmd";
  fi
  tid=$(echo $tid | sed -e 's/^\"//' -e 's/\"$//')  # remove "" enclosing thread id.
  logDebugMsg "Command is running with tid=$tid";
  # Check that tid is actually a number
  if ! [[ $tid =~ ^[0-9]+$ ]]; then
    logErrorMsg "Returned tid='$tid' is not a number";
  fi

  logDebugMsg "===============JOB_OUTPUT_BEGIN====================";
  local console_log="$VM_JOB_DIR/`hostname`/1-console.log"
  exec {CON_FD}<$console_log
  local con_eof=0
  local con_part_line=''
  # wait on executed app to finish
  local app_finished=0;
  logDebugMsg "Command tid=$tid wait to finish...";
  while [ $app_finished -ne 1 ]; do
    if $DEBUG; then
      con_eof=0
      while [[ $con_eof -eq 0 ]]
      do
        # this will read also partial lines (with not \n at end)
        if read con_line <&$CON_FD; then
          # printf "CON: %s\n" "${con_part_line}${con_line}"
          logDebugMsg "CON: ${con_part_line}${con_line}";
          con_part_line=''
        else
          con_part_line+="$con_line"
          # printf "CON-part: %s\n" "${con_part_line}"
          con_eof=1
        fi
      done
    fi
    sleep 5;
    app_finished=$(\
      curl --connect-timeout 2 \
           -X GET http://$FIRST_VM:8000/app/finished \
           --data-urlencode tid="$tid"\
      | sed -e 's/^\"//' -e 's/\"$//');
    result=$?;
    if [ $result -ne 0 ]; then
      logErrorMsg "Failed to check if application with tid='$tid' is finished.";
    fi
  done
  exec {CON_FD}>&-
  logDebugMsg "Command tid=$tid finished";
  # store the return code (ssh returns the return value of the command in
  # question, or 255 if an error occurred in ssh itself.)
  # TODO what does curl return on error?
  # TODO how to detect that program was run, but failed immediately?
  # On OSv, HTTP REST will return 200/OK, and error is shown only on
  # stderr/console. So it seems we cannot detect failure at all.
  logDebugMsg "================JOB_OUTPUT_END=====================";
  return $result;
}


#---------------------------------------------------------
#
# Executes user's batch job script in first/rank0 (standard
# linux guest) VM.
#
runSTDINJobOnSLG() {

  # the first node in the list is 'rank 0'
  logDebugMsg "Executing SLG STDIN job script '$JOB_SCRIPT' on first vNode '$FIRST_VM'.";

  # test if job script is available inside VM, if not stage it
  ensureFileIsAvailableOnHost $JOB_SCRIPT $FIRST_VM;

  # construct the command to execute via ssh
  local cmd="source /etc/profile; $(cat $JOB_SCRIPT)";

  # execute command
  logDebugMsg "Command to execute: 'ssh $SSH_OPTS $FIRST_VM \"$cmd\"'";
  logDebugMsg "===============JOB_OUTPUT_BEGIN====================";
  if $DEBUG; then
    ssh $FIRST_VM "$cmd" |& tee -a "$LOG_FILE";
  else
    ssh $FIRST_VM "$cmd" 2>> "$LOG_FILE";
  fi
  # store the return code (ssh returns the return value of the command in
  # question, or 255 if an error occurred in ssh itself.)
  local result=$?;

  logDebugMsg "================JOB_OUTPUT_END=====================";
  return $result;
}


#---------------------------------------------------------
#
#
#
runInteractiveJobOnSLG(){

  # the first node in the list is 'rank 0'
  logDebugMsg "Executing INTERACTIVE job on first vNode '$FIRST_VM'.";

  # construct the command to execute via ssh
  local cmd="/bin/bash -i";

  # execute command
  logDebugMsg "Command to execute: 'ssh $FIRST_VM \"$cmd\"'";
  logDebugMsg "============INTERACTIVE_JOB_BEGIN==================";

  # check if we are running with 'qsub -I -X [...]'
  local sshOpts="";
  if [ -f "$FLAG_FILE_X11" ]; then
    sshOpts="-X";
  fi

  # debugging ?
  if $DEBUG; then
    ssh $FIRST_VM $sshOpts "$cmd" |& tee -a "$LOG_FILE";
  else
    ssh $FIRST_VM $sshOpts "$cmd" &>> "$LOG_FILE";
  fi
  # store the return code (ssh returns the return value of the command in
  # question, or 255 if an error occurred in ssh itself.)
  local result=$?;

  logDebugMsg "=============INTERACTIVE_JOB_END===================";
  return $result;
}


#---------------------------------------------------------
#
# Executes user's batch job.
#
runBatchJob(){
  if [[ $DISTRO =~ $REGEX_OSV ]]; then
    runJobOnOSv;
  else
    runBatchJobOnSLG;
  fi
  return $?;
}


#---------------------------------------------------------
#
# Executes user's batch job.
#
runSTDINJob(){
  if [[ $DISTRO =~ $REGEX_OSV ]]; then
    runJobOnOSv;
  else
    runSTDINJobOnSLG;
  fi
  return $?;
}


#---------------------------------------------------------
#
# Executes user's interactive job.
#
runInteractiveJob(){
  if [[ $DISTRO =~ $REGEX_OSV ]]; then
    logErrorMsg "Executing INTERACTIVE jobs on OSv is unsupported";
  else
    runInteractiveJobOnSLG;
  fi
  return $?;
}


#---------------------------------------------------------
#
# Executes user's job.
#
runJobInVM() {

  #
  # execute the actual user job (script)
  #
  logInfoMsg "Starting user job script in VM.";
  logDebugMsg "Job-Type to execute: $JOB_TYPE";

  local res;

  # what kind of job is it ? (interactive, STDIN, batch-script)
  if [ "$JOB_TYPE" == "@BATCH_JOB@" ]; then
    # batch
    logDebugMsg "Executing user's batch job script ..";
    runBatchJob;
    res=$?;
  elif [ "$JOB_TYPE" == "@STDIN_JOB@" ]; then
    # stdin
    logDebugMsg "Executing user's STDIN job script ..";
    runSTDINJob;
    res=$?;
  elif [ "$JOB_TYPE" == "@INTERACTIVE_JOB@" ]; then
    #interactive
    logDebugMsg "Executing user's interactive job ..";
    runInteractiveJob;
    res=$?;
  else
    echo "ERROR: unknown type of job: '$JOB_TYPE' !";
  fi

  # logging
  logDebugMsg "Job has been executed, return Code: $res";
  return $res;
}


#---------------------------------------------------------
#
# Keeps VMs live in debug mode and if env var 'KEEP_VM_ALIVE'
# is set to true. Allows to inspect what happend inside the VM.
#
keepVMsAliveIfRequested() {
  if $DEBUG \
      && $KEEP_VM_ALIVE; then
    logDebugMsg "Pausing job wrapper, it is requested to keep the VMs alive.";
    logInfoMsg "To continue execution, run cmd: 'touch $FLAG_FILE_CONTINUE'.";
    # wait for flag indicating to continue
    while [ ! -f "$FLAG_FILE_CONTINUE" ]; do
      logTraceMsg "Flag file '$FLAG_FILE_CONTINUE' not found, waiting ..";
      checkCancelFlag;
      sleep 1;
    done
    logInfoMsg "Flag file '$FLAG_FILE_CONTINUE' found, continuing execution.";
    logDebugMsg "Removing flag file '$FLAG_FILE_CONTINUE'";
    rm -f $FLAG_FILE_CONTINUE;
  fi
  return 0;
}


#---------------------------------------------------------
#
# Abort function that is called by the (global) signal trap.
#
_abort() {
  local exitCode=0;
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

# check if canceled meanwhile
checkCancelFlag;

# capture output streams in vTorque's log
captureOutputStreams;

# make sure everything needed is in place
checkPreConditions;

# cancelled meanwhile ?
checkCancelFlag;

# set rank0 VM
setRank0VM;

# create the file containing the required PBS VARs
createJobEnvironmentFiles;

# execute user's job in the first/rank0 VM
runJobInVM;
jobExitCode=$?;

# are we debugging and is keep alive requested ?
keepVMsAliveIfRequested;

# stop capturing
stopOutputCapturing;

# debug log
logDebugMsg "***************** END OF JOB WRAPPER ********************";

# print the consumed time in debug mode
runTimeStats;

# return job exit code
exit $jobExitCode;
