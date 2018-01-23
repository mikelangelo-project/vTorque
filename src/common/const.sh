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
#         FILE: const.sh
#
#        USAGE: Will be sourced by config.sh and others.
#
#  DESCRIPTION: vTorque constants.
#
#      OPTIONS: See doc/admin.md
# REQUIREMENTS: $RUID or $PBS_JOBID must be set.
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Nico Struckmann, struckmann@hlrs.de
#      COMPANY: HLRS, University of Stuttgart
#      VERSION: 0.2
#      CREATED: Oct 02nd 2015
#     REVISION: Jul 10th 2017
#
#    CHANGELOG
#         v0.2: more options added, refactoring and cleanup
#
#=============================================================================

set -o nounset;
ABSOLUTE_PATH_CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";


#
# set the job id (it's in the env when debugging in an interactive
# job or given as arg $1 when run by Torque)
#
if [ $# -gt 1 ]; then
  # passed on as parameters (root script/manually)
  # called by root {pro,epi}logue{.parallel,precancel}
  PBS_JOBID=$1;
  USER_NAME=$2;
  JOBID=$PBS_JOBID;
elif [ -z ${JOBID-} ] && [ -n "${PBS_JOBID-}" ]; then
  # in running jobs
  export JOBID=$PBS_JOBID;
elif [ -z ${PBS_JOBID-} ] && [ -n "${JOBID-}" ]; then
  # manual debugging (?)
  export PBS_JOBID=$JOBID;
elif [ -n "${RUID-}" ]; then
  # vsub only
  export JOBID=$RUID;
else
  echo "ERROR: Your installation seems broken, no '\$RUID' and no '\$PBS_JOBID' set!";
  echo "For debugging use $(basename ${BASH_SOURCE[0]}) <jobID> <username>"; # relevant if not executed by Torque, but manually
  return 1;
fi

#
# ensure USER_NAME is set
#
if [ -z ${USER_NAME-} ]; then
  if [ -n "${USERNAME-}" ]; then
    USER_NAME=$USERNAME;
  elif [ -n "${USER-}" ]; then
    USER_NAME=$USER;
  else
    echo "ERROR: Neither '\$USER' nor '\$USERNAME' is not defined and not passed on as argument.";
    return 1;
  fi
fi

#
# JOBID and PBS_JOBID differ ?
#
if [ ! -z ${PBS_JOBID-} ] \
    && [ ! -z ${JOBID-} ] \
    && [ "$PBS_JOBID" != "$JOBID" ]; then
  # JOBID is set and differs from PBS_JOBID - should not happen, abort
  echo "ERROR: JOBID and PBS_JOBID differ!";
  return 1;
fi

#
# defines location of generated files and logs for vm-jobs
# do not use $HOME as it is not set everywhere while '~' just works
#
if [ -z ${VM_JOB_DIR_PREFIX-} ]; then
  # root or user level ?
  if [ $(id -u) -eq 0 ]; then # root scripts
    if [ -n "${USER_NAME-}" ]; then
      VM_JOB_DIR_PREFIX="$(grep $USER_NAME /etc/passwd | cut -d':' -f6)/.vtorque";
    else # abort now, the file is sourced a second time when the var is set
      return 1;
    fi
  else # user scripts
    VM_JOB_DIR_PREFIX=~/.vtorque;
  fi
fi

#
# Directory to store the job related files that are going to be generated
#
if [ -z ${VM_JOB_DIR-} ]; then
  VM_JOB_DIR="$VM_JOB_DIR_PREFIX/$JOBID";
fi

#
# VTORQUE_DIR is already set in most cases, just in case it is not..
# it is defined in the profile.d/ file
#
if [ -z ${VTORQUE_DIR-} ] \
    || [ ! -d "${VTORQUE_DIR-}" ]; then
  echo "WARN: Your installation seems broken, environment variable '\$VTORQUE_DIR' is not set!";
  VTORQUE_DIR="$(realpath $(dirname ${BASH_SOURCE[0]})/..)";
  echo "INFO: Using '\$VTORQUE_DIR=$VTORQUE_DIR'";
fi

#
# enforce availability of JOBID and USER_NAME in subscripts
# (needed for snap-{start,stop}.sh, iocm-{start,stop}.sh, vrdma-{start,stop}.sh)
#
export JOBID=$JOBID;
export USER_NAME=$USER_NAME;


#============================================================================#
#                                                                            #
#                           GLOBAL CONSTANTS                                 #
#                             Do Not Edit.                                   #
#                                                                            #
#============================================================================#

#
# Flag that indicates the default filesystem type if not user defined
#
FILESYSTEM_TYPE_SFS="sharedfs";

#
# Filesystem type RAM disk
#
FILESYSTEM_TYPE_RD="ramdisk";

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
# Directory containing flag files used to pass on infos
# from user env to root scripts
#
FLAG_FILE_DIR="$VM_JOB_DIR/flags";

#
# Flag file indicating type of storage to use for the job
#
FILESYSTEM_FLAG_FILE="$FLAG_FILE_DIR/.filesystype";

#
# Indicates whether to use a shared-fs or ram-disk for (local) VM images
#
USE_RAM_DISK=$(\
  if [ -f "$FILESYSTEM_FLAG_FILE" ] \
      && [ "$(cat $FILESYSTEM_FLAG_FILE)" == "$FILESYSTEM_TYPE_RD" ]; then \
    echo 'true'; else echo 'false'; fi);

#
# short name of local host
#
LOCALHOST="$(hostname -s)";

#
# Directory that contain all wrapper template files
#
TEMPLATE_DIR="$VTORQUE_DIR/templates";

#
# Directory that contain all VM template files (domain.xml, metadata)
#
VM_TEMPLATE_DIR="$VTORQUE_DIR/templates-vm";

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
# Shared fs dir that contains init locks, one for each VM that is booting/destroyed.
#
LOCKFILES_INIT_DIR="$VM_JOB_DIR/locks-init";

#
# Shared fs dir that contains tear down locks, one for each VM that is booting/destroyed.
#
LOCKFILES_TRDWN_DIR="$VM_JOB_DIR/locks-trdwn";

#
# Location of cloud-init log inside VM (required to be in sync with the metadata-template(s))
#
CLOUD_INIT_LOG="/var/log/cloud-init.log";

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
#                                  VSUB                                      #
#                                                                            #
#============================================================================#

#
# User prologue wrapper template
#
SCRIPT_PROLOGUE_TEMPLATE="$TEMPLATE_DIR/vmPrologue.sh";

#
# User prologue.parallel template
#
SCRIPT_PROLOGUE_PARALLEL_TEMPLATE="$TEMPLATE_DIR/vmPrologue.parallel.sh";

#
# Job script wrapper template
#
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
# User prologue wrapper script (vsub output file)
#
SCRIPT_PROLOGUE="$VM_JOB_DIR/vmPrologue.sh";

#
# User prologue.parallel script (vsub output file)
#
SCRIPT_PROLOGUE_PARALLEL="$VM_JOB_DIR/vmPrologue.parallel.sh";

#
# Job script wrapper (vsub output file)
#
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

#
# Cache file that holds the job's RUID
#
RUID_CACHE_FILE="$VM_JOB_DIR/.ruid";

#
# initialize optional aliases mapping
#
declare -A ALIAS_MAP=();

# aliases file present ?
if [ -f "$ABSOLUTE_PATH_CONFIG/aliases" ]; then
  index=0;
  while read line; do
    ALIAS_MAP[$index]="$line";
    index=$(($index + 1));
  done < "$ABSOLUTE_PATH_CONFIG/aliases";
  unset index;
fi


#============================================================================#
#                                                                            #
#              VM [PRO|EPI]LOGUE[.PARALLEL] SCRIPTS                          #
#                                                                            #
#============================================================================#

#
# VM boot log
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
# Flag file indicating to continue execution.
#
FLAG_FILE_CONTINUE="$FLAG_FILE_DIR/.continue";

#
# Flag file indicating to cancel execution.
#
CANCEL_FLAG_FILE="$FLAG_FILE_DIR/.abort";

#
# Flag file indicating job ended.
#
JOB_ENDED_FLAG="$FLAG_FILE_DIR/.jobIsDone";

#
# Lock file that contains started remote processes
#
LOCKFILE_INIT="$FLAG_FILE_DIR/.remoteProcessesInit";

#
# Lock file that contains teared down remote processes
#
LOCKFILE_TRDWN="$FLAG_FILE_DIR/.remoteProcessesTrdwn";

#
# Indicates failures in parallel processes before lock files can be created
# When lock files are in place we write errors into these so we can identify
# the host and corresponding error msg easily
#
ERROR_FLAG_FILE="$FLAG_FILE_DIR/.error";

#
# Flag file indicating debug mode.
#
FLAG_FILE_DEBUG="$FLAG_FILE_DIR/.debug";

#
# Flag file indicating verbose mode.
#
FLAG_FILE_TRACE="$FLAG_FILE_DIR/.trace";

#
# Flag file for the root prologue indicating whether to enable vRDMA.
#
FLAG_FILE_VRDMA="$FLAG_FILE_DIR/.vrdma";

#
# Flag file for whether to enable UNCLOT.
#
FLAG_FILE_UNCLOT="$FLAG_FILE_DIR/.unclot";

#
# Flag file for the root prologue indicating whether to enable iocm.
# Min/Max core count to use are stored inside this file.
#
FLAG_FILE_IOCM="$FLAG_FILE_DIR/.iocm";

#
# Flag file indicating interactive jobs.
#
FLAG_FILE_X11="$FLAG_FILE_DIR/.x11";

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
DOMAIN_UNCLOT_XML_TEMPLATE="$VM_TEMPLATE_DIR/domain-fragment-unclot.xml";
DOMAIN_NUMA_XML_TEMPLATE="$VM_TEMPLATE_DIR/domain-fragment-numa.xml";


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
VM_NODEFILE_DIR="$VM_JOB_DIR/aux";

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
PBS_ENV_FILE_PREFIX="$VM_JOB_DIR"; #used this way => PBS_ENV_FILE=$PBS_ENV_FILE_PREFIX/$node/vmJobEnviornment

#
# Path to directory where all component ctrl script reside
#
COMPONENTS_DIR="$VTORQUE_DIR/components";


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
VRDMA_SCRIPT_DIR="$COMPONENTS_DIR/vrdma";


#============================================================================#
#                                                                            #
#                              SNAP MONITORING                               #
#                                                                            #
#============================================================================#

#
# location of snap management scripts
#
SNAP_SCRIPT_DIR="$COMPONENTS_DIR/snap";
