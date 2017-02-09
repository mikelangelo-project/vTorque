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
##############################################################################
#                                                                            #
# IMPORTANT NOTE:                                                            #
# ===============                                                            #
#  $RUID or $PBS_JOBID is expected to be set.                               #
#                                                                            #
##############################################################################
#
set -o nounset;
ABSOLUTE_PATH_CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";


#
# set the job id (it's in the env when debugging with the help of an
# interactive job, but given as arg when run by Torque or manually
#
if [ -z ${JOBID-} ] && [ -n "${PBS_JOBID-}" ]; then
  export JOBID=$PBS_JOBID;
elif [ -z ${PBS_JOBID-} ] && [ -n "${JOBID-}" ]; then
  export PBS_JOBID=$JOBID;
elif [ $# -gt 0 ]; then #called by root {pro,epi}logue{.parallel,precancel}
  export JOBID=$1;
elif [ -n "${RUID-}" ]; then
  export JOBID=$RUID;
fi
# differ JOBID and PBS_JOBID ?
if [ ! -z ${PBS_JOBID-} ] \
    && [ ! -z ${JOBID-} ] \
    && [ "$PBS_JOBID" != "$JOBID" ]; then
  # JOBID is set and differs from PBS_JOBID - should not happen, abort
  echo "ERROR: JOBID and PBS_JOBID differ!";
  exit 1;
fi

# RUID set ?
if [ -z ${RUID-} ]; then
  # no, use the jobID instead
  RUID=$JOBID;
fi

#
# SCRIPT_BASE_DIR is already set in most cases, just in case it is not..
# it is defined in the profile.d/ file
#
if [ -z ${SCRIPT_BASE_DIR-} ] \
    || [ ! -n "${SCRIPT_BASE_DIR-}" ] \
    || [ ! -d "${SCRIPT_BASE_DIR-}" ]; then
  logWarnMsg "Environment variable '\$SCRIPT_BASE_DIR' is not set.";
  SCRIPT_BASE_DIR="$(realpath $(dirname ${BASH_SOURCE[0]}))/..";
fi



#============================================================================#
#                                                                            #
#                               CONSTANTS                                    #
#                              Do Not Edit.                                  #
#                                                                            #
#============================================================================#

#
# Flag that indicates the default filesystem type if not user defined
#
FILESYSTEM_TYPE_SFS="sharedfs"; # shared file system

#
# Filesystem type RAM disk
#
FILESYSTEM_TYPE_RD="ramdisk"; #ram disk

#
# Regexpr to validate Debian and Ubuntu
#
REGEX_DEBIAN="DEBIAN|UBUNTU|Debian|Ubuntu|debian|ubuntu";

#
# Regexpr to validate RedHat and CentOS
#
REGEX_REDHAT="REDHAT|RedHat|Redhat|redhat|CENTOS|CentOS|centos";

#
# Regexpr to validate OSv
#
REGEX_OSV="OSV|OSv|osv";

#
# RegExpr for supported Standard Linux OS
#
SUPPORTED_STANDARD_LINUX_GUESTS="$REGEX_DEBIAN|$REGEX_REDHAT";

#
# RegExpr for supported container OS
#
SUPPORTED_CONTAINER_OS="$REGEX_OSV";

#
# RegExpr for supported OS
#
SUPPORTED_OS="$SUPPORTED_STANDARD_LINUX_GUESTS|$SUPPORTED_CONTAINER_OS";

#
# defines location of generated files and logs for vm-jobs
# do not use $HOME as it is not set everywhere while '~' just works
#
if [ -z ${VM_JOB_DIR_PREFIX-} ]; then
  if [ $(id -u) -eq 0 ]; then # root scripts
    if [ -n "${USERNAME-}" ]; then
      VM_JOB_DIR_PREFIX="$(grep $USERNAME /etc/passwd | cut -d':' -f6)/.vtorque";
    else # abort now, the file is sourced a second time when the var is set
      return 0;
    fi
  else # user scripts
    VM_JOB_DIR_PREFIX=~/.vtorque;
  fi
fi

#
# Directory to store the job related files that are going to be generated
#
if [ -z ${VM_JOB_DIR-} ]; then
  VM_JOB_DIR="$VM_JOB_DIR_PREFIX/$RUID";
fi

#
# Directory containing flag files used to pass on infos
# from user env to root scripts
#
FLAG_FILE_DIR="$VM_JOB_DIR/flags";

#
# Flag file indicating type of storage to use for the job
#
FILESYSTEM_FLAG_FILE="$FLAG_FILE_DIR/.filesystype";

#
# Note: in the qsub wrapper, this file does not exist yet
#
USE_RAM_DISK=$(if [ -f "$FILESYSTEM_FLAG_FILE" ] && [ "$(cat $FILESYSTEM_FLAG_FILE)" == "$FILESYSTEM_TYPE_RD" ]; then echo 'true'; else echo 'false'; fi);

#
# File containing job submission aliases
#
ALIASES_FILE="$ABSOLUTE_PATH_CONFIG/aliases";

#
# initialize aliases mapping
#
declare -A ALIAS_MAP;

# aliases file present ?
if [ -f ALIASES_FILE ]; then
  index=0;
  while read line; do
    ALIAS_MAP[$index]="$line";
  index=$(($index + 1));
  done < $ALIASES_FILE;
  unset index;
fi

#
# short name of local host
#
LOCALHOST=$(hostname -s);

#
# Directory that contain all wrapper template files
#
TEMPLATE_DIR="$SCRIPT_BASE_DIR/templates";

#
# Directory that contain all VM template files (domain.xml, metadata)
#
VM_TEMPLATE_DIR="$SCRIPT_BASE_DIR/templates-vm";

#
# Template (fragment), used to generate the cpu pinning file
#
PINNING_FILE="$VM_JOB_DIR/$LOCALHOST/pinning_frag.txt"; #DO NOT name it .xml



#============================================================================#
#                                                                            #
#                             FILEs AND DIRs                                 #
#                                                                            #
#============================================================================#

#
# VM's XML-definition file, one for each VM per node
#
#used this way: domainXML=$DOMAIN_XML_PREFIX/$computeNode/${parsedParams[$vmNo, NAME]}.xml
DOMAIN_XML_PREFIX=$VM_JOB_DIR;

#
# Shared fs dir that contains locks, one for each VM that is booting/destroyed.
#
LOCKFILES_DIR="$VM_JOB_DIR/locks";

#
# Location of cloud-init log inside VM (required to be in sync with the metadata-template(s))
#
CLOUD_INIT_LOG="/var/log/cloud-init-output.log";

#
# Path to syslog file on redhat based operating systems
#
SYS_LOG_FILE_RH="/var/log/messages";

#
# Path to syslog file on debian based operating systems
#
SYS_LOG_FILE_DEBIAN="/var/log/syslog";



#============================================================================#
#                                                                            #
#                              QSUB WRAPPER                                  #
#                                                                            #
#============================================================================#



#
# Template files
#
SCRIPT_PROLOGUE_TEMPLATE="$TEMPLATE_DIR/vmPrologue.sh";
SCRIPT_PROLOGUE_PARALLEL_TEMPLATE="$TEMPLATE_DIR/vmPrologue.parallel.sh";
SCRIPT_EPILOGUE_TEMPLATE="$TEMPLATE_DIR/vmEpilogue.sh";
SCRIPT_EPILOGUE_PARALLEL_TEMPLATE="$TEMPLATE_DIR/vmEpilogue.parallel.sh";
JOB_SCRIPT_WRAPPER_TEMPLATE="$TEMPLATE_DIR/jobWrapper.sh";

#
# Metadata template file for debian based OS
#
METADATA_TEMPLATE_DEBIAN="$VM_TEMPLATE_DIR/metadata.debian.yaml";

#
# Metadata template file for redhat based OS
#
METADATA_TEMPLATE_REDHAT="$VM_TEMPLATE_DIR/metadata.redhat.yaml";

#
# Metadata template file for OSv
#
METADATA_TEMPLATE_OSV="$VM_TEMPLATE_DIR/metadata.osv.yaml";

#
# qsub-wrapper output files
#
SCRIPT_PROLOGUE="$VM_JOB_DIR/vmPrologue.sh";
SCRIPT_PROLOGUE_PARALLEL="$VM_JOB_DIR/vmPrologue.parallel.sh";
SCRIPT_EPILOGUE="$VM_JOB_DIR/vmEpilogue.sh";
SCRIPT_EPILOGUE_PARALLEL="$VM_JOB_DIR/vmEpilogue.parallel.sh";
JOB_SCRIPT_WRAPPER="$VM_JOB_DIR/jobWrapper.sh";

#
# subdir on shared fs ($HOME) where the linked user job script is placed
#
VM_JOB_USER_SCRIPT_DIR="$VM_JOB_DIR/userJobScript";

#
# tmp file for job script contents (used for '#PBS' parsing)
#
TMP_JOB_SCRIPT="$VM_JOB_USER_SCRIPT_DIR/jobScript.tmp";

#
# file that collects all '^#PBS ' lines inside the given job
#
JOB_WRAPPER_RES_REQUEST_FILE="$VM_JOB_DIR/pbsResRequests.tmp";

#
# pbs flag parameter that have no value
#
PBS_FLAG_PARAMETERS="f|F|h|I|n|V|x|X|z";

#
# pbs key/value parameter
#
PBS_KV_PARAMETERS="a|A|b|c|C|d|D|e|j|k|K|l|L|m|M|N|o|p|P|q|r|S|t|u|v|w|W";


#============================================================================#
#                                                                            #
#              VM [PRO|EPI]LOGUE[.PARALLEL] SCRIPTS                          #
#                                                                            #
#============================================================================#

#
# vm boot log
#
VMLOG_FILE_PREFIX="$VM_JOB_DIR/$LOCALHOST";

#
# Prefix for generated domain.xml files
#
DOMAIN_XML_PATH_PREFIX="$VM_JOB_DIR";

#
# construct the template for the provided parameter combination
#
DOMAIN_XML_PATH_NODE="$DOMAIN_XML_PATH_PREFIX/$LOCALHOST";

#
# path prefix for file that contains all VM-IPs
#
VM_IP_FILE_PREFIX="$VM_JOB_DIR";

#
# name of file that contains all VM-IPs
#
VM_IP_FILE_NAME="vmIPs";

#
# path to file that contains all VM-IPs on the local host
#
LOCAL_VM_IP_FILE="$VM_IP_FILE_PREFIX/$LOCALHOST/$VM_IP_FILE_NAME";

#
# Indicates vmPrologue.parallel.sh to abort
#
ABORT_FLAG="$VM_JOB_DIR/.abortFlag";

#
# Lock file that contains started remote processes
#
LOCKFILE="$VM_JOB_DIR/.remoteProcesses";

#
# Indicates failures in parallel processes before lock files can be created
# When lock files are in place we write errors into these so we can identify
# the host and corresponding error msg easily
#
ERROR_FLAG_FILE="$VM_JOB_DIR/.error";


#-----------------------------------------------------------------------------
#
# vmPrologue only
#

#
# vm template with place holders
#
DOMAIN_XML_TEMPLATE_SLG="$VM_TEMPLATE_DIR/domain.slg.xml"; #slg = standard linux guest
DOMAIN_XML_TEMPLATE_OSV="$VM_TEMPLATE_DIR/domain.osv.xml";
DOMAIN_METADATA_XML_TEMPLATE="$VM_TEMPLATE_DIR/domain-fragment-metadata.xml";
DOMAIN_DISK_XML_TEMPLATE="$VM_TEMPLATE_DIR/domain-fragment-disk.xml";
DOMAIN_VRDMA_XML_TEMPLATE="$VM_TEMPLATE_DIR/domain-fragment-vrdma.xml";


#============================================================================#
#                                                                            #
#                               JOB WRAPPER                                  #
#                                                                            #
#============================================================================#

#
# intended  for debug+testing when there is no PBS_NODEFILE set
#
if [ -z ${PBS_NODEFILE-} ] || [ ! -n "$PBS_NODEFILE" ]; then
  if [ -z ${TORQUE_HOME-} ]; then
    TORQUE_HOME="/var/spool/torque";
  fi
  PBS_NODEFILE="$TORQUE_HOME/aux/$JOBID";
fi

#
# VM nodefile, it is required to be called '$PBS_JOBID'
#
PBS_VM_NODEFILE="$VM_JOB_DIR/$JOBID";

#
# directory that is mounted into the VM and contains the PBS_NODEFILE
#
VM_NODE_FILE_DIR="$VM_JOB_DIR/aux";

#
# directory that is mounted into the VM and contains the PBS job environment vars
#
VM_ENV_FILE_DIR="$VM_JOB_DIR";

#
# Dir that contains all job related files that are relevant inside the VMs,
# like the PBS environment file that is host specific
#
VM_DIR="$VM_JOB_DIR/$LOCALHOST";

#
# Prefix for the host env files that are host specific
#
PBS_ENV_FILE_PREFIX="$VM_ENV_FILE_DIR"; #used this way => PBS_ENV_FILE=$PBS_ENV_FILE_PREFIX/$node/vmJobEnviornment

#
# Path to directory where all component ctrl script reside
#
COMPONENTS_DIR="$SCRIPT_BASE_DIR/components";



#============================================================================#
#                                                                            #
#                                  IOcm                                      #
#                                                                            #
#============================================================================#

#
# location of iocm scripts
#
IOCM_SCRIPT_DIR="$COMPONENTS_DIR/iocm";



#============================================================================#
#                                                                            #
#                             DPDK/virtIO/vRDMA                              #
#                                                                            #
#============================================================================#

#
# location of vRDMA management scripts
#
VRDMA_SCRIPT_DIR="$COMPONENTS_DIR/vrdma/";



#============================================================================#
#                                                                            #
#                              SNAP MONITORING                               #
#                                                                            #
#============================================================================#

#
# location of snap management scripts
#
SNAP_SCRIPT_DIR="$COMPONENTS_DIR/snap";

