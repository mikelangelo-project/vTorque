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
#  $RUID or $PBS_JOBID is expected to be set.                                #
#                                                                            #
##############################################################################
#
set -o nounset;

ABSOLUTE_PATH_CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source "$ABSOLUTE_PATH_CONFIG/../../lib/log4bsh/src/log4bsh.sh";

#============================================================================#
#                                                                            #
#                          GLOBAL DEFAULT CONFIG                             #
#                    (may be overriden by user env vars)                     #
#                                                                            #
#============================================================================#

#
# en/disable DEBUG globally
#
DEBUG_DEFAULT=false;

#
# en/disable TRACE globally
#
TRACE_DEFAULT=false;

#
# if debugging is enabled,
# keep the VMs alive after the user job script has been executed
#
KEEP_VM_ALIVE_DEFAULT=true;

#
# show log for batch jobs immediately after job submission
#
SHOW_LOG_DEFAULT=false;

#
# enables multiple developers to work on the same cluster,
# DO NOT use it in production
#
ENABLE_DEV_MODE=true;


#============================================================================#
#                                                                            #
#                          GLOBAL CONFIGURATION                              #
#                                                                            #
#============================================================================#

#
# regex for hostnames of pbs_servers, covers scenario:
#  front-ends and compute nodes have different OS
#
SERVER_HOSTNAME="vsbase2";

#
# path to the real qsub binary on the front-ends
#
REAL_QSUB_ON_SERVER="/opt/torque/current/server/bin/qsub";

#
# path to the real qsub binary on the compute nodes
#
REAL_QSUB_ON_NODES="/opt/torque/current/client/bin/qsub";

#
# Torque's Home directory
#
TORQUE_HOME="/var/spool/torque";

#
# MAC prefix for VMs.
#
MAC_PREFIX="52:54:00"

#
# Regular expression for list of hosts where the VM jobs are disabled for submission
# for job submission, only relevant if DISABLE_MIKELANGELO_HPCSTACK is set to true
#  example value 'frontend[0-9]'
#
DISABLED_HOSTS_LIST="*";

# Indicates whether to run vmPro/Epilogues in parallel, default is true.
# False is useful for debugging, only. Do not use in production.
#
PARALLEL=true;

#
# Allows users to define custom images.
# NOTE: introduces security implications, may allow users to mount NFS shares
#       with chosen uids
#
ALLOW_USER_IMAGES=false;

#
# Amount of core reserved for the host OS
#
HOST_OS_CORE_COUNT=1;

#
# Amount of RAM dedicated to the physical host OS
#
HOST_OS_RAM_MB=2048;

#
# if user images are not allowed, the image must reside in this dir
#
VM_IMG_DIR="/images/pool";

#
# indicates whether we use DNS to resolve VM IPs dynamically
#  or if we have configured our DNS to use a VM-MAC to Static-IP mapping
#
STATIC_IP_MAPPING=true;

#
# Timeout for remote processes in pro/epilogues
#
TIMEOUT=600;

#
# Timeout for processes that boot VMs and configure iocm
#
ROOT_PROLOGUE_TIMEOUT=600;

#
# Path to a fast shared file-system (used by jobs for intermediate data)
#
SHARED_FS_ROOT_DIR="/scratch/.vtorque";

#
# location/prefix for the RAMdisks
#
RAMDISK_DIR_PREFIX="/ramdisk";

#
# forces debug output also to the job's STDOUT file
#
DEBUG_TO_STDOUT=true;

#
# Indicates whether to submiot the jobs with '-l naccesspolicy=uniqueuser' or not
#
PBS_EXCLUSIVE_NODE_ALLOC=true;

#
# Full path to arp binary on the nodes.
#
ARP_BIN="/usr/sbin/arp";


#============================================================================#
#                                                                            #
#                            PROCESS ENV VARs                                #
#                             Do Not Edit                                    #
#============================================================================#

#
# SSH timeout
#
SSH_TIMEOUT=5;

#============================================================================#
#                                                                            #
#                      METADATA / NFS Shares                                 #
#                                                                            #
#============================================================================#

#
# NFS export for VM's "/home"
#
VM_NFS_HOME="172.18.2.6:/nfs/homes/mikelangelo";

#
# NFS export for VM's "/opt"
#
VM_NFS_OPT="172.18.2.6:/nfs/shared-opt/mikelangelo";

#
# NFS export for VM's "/workspace" (scratch-fs)
#
VM_NFS_WS="172.18.2.3:/storage/mikelangelo/ssd_scratch";


#============================================================================#
#                                                                            #
#                       METADATA / DNS setup                                 #
#                                                                            #
#============================================================================#

#
# DNS server
#
NAME_SERVER="172.18.2.2";

#
# Search domain
#
SEARCH_DOMAIN="rus.uni-stuttgart.de";

#
# Domain
#
DOMAIN="rus.uni-stuttgart.de";


#============================================================================#
#                                                                            #
#                       METADATA / NTP setup                                 #
#                                                                            #
#============================================================================#

#
# NTP server #1
#
NTP_SERVER_1="rustime01.rus.uni-stuttgart.de";

#
# NTP server #2
#
NTP_SERVER_2="rustime02.rus.uni-stuttgart.de";


#============================================================================#
#                                                                            #
#                       METADATA / additional sw                             #
#                                                                            #
# NOTE:                                                                      #
# It is recommended to package the images with all sw required, however if   #
# a standard cloud image is used we need to install it during boot.          #
# If the software is already installed in the image, there are no impacts.   #
#============================================================================#

#
# List of default sw packages for debian systems required (for standard cloud-images)
#
SW_PACKAGES_DEBIAN=('nfs-common' 'libnfs1' 'openmpi-bin' 'libopenmpi-dev' 'libmetis5' 'libmetis-dev' '9mount');

#
# List of default sw packages for redhat systems required (for standard cloud-images)
#
SW_PACKAGES_REDHAT=('nfs-common' 'libnfs1' 'nfs-utils' 'openmpi' 'openmpi-devel' 'metis' 'metis-devel' 'nfs-ganesha-mount-9P');




#============================================================================#
#                                                                            #
#                                DEFAULTS                                    #
#                                                                            #
#============================================================================#

#
# default file sys type
# either ram disk (='ramdisk') or shared fs (='sharedfs')
#
FILESYSTEM_TYPE_DEFAULT="sharedfs";

#
# default image in case the user does not request one
# Name is relative to $GLOBAL_IMG_DIR
#
IMG_DEFAULT="ubuntu_bones-compressed_cloud-3.img";

#
# default distro, MUST match the IMG_DEFAULT
#
DISTRO_DEFAULT="debian";

#
# default virtual CPU architecture for guests
#
ARCH_DEFAULT="x86_64";

#
# default for VCPU pinning (en/disabled)
#
VCPU_PINNING_DEFAULT=true;

#
# default amount of vCPUs
#
VCPUS_DEFAULT="8";

#
# Default RAM for VMs in MB
#
RAM_DEFAULT="24576";

#
# default amount of VMs per node
#
VMS_PER_NODE_DEFAULT="1";

#
# Optional default disk mounted on rank0, used if none is given at sumission time
#
DISK_DEFAULT="";

#
# kvm|skvm
#
HYPERVISOR_DEFAULT="kvm";

#
# Default that is used in case there is no user defined value and it's enabled
# in the global config
#
VRDMA_ENABLED_DEFAULT=true;

#
# Default that is used in case there is no user defined value and it's enabled
# in the global config
#
IOCM_ENABLED_DEFAULT=true;

#
# Default that is used in case there is no user defined value and it's enabled
# in the global config
#
IOCM_MIN_CORES_DEFAULT=1;

#
# Default that is used in case there is no user defined value and it's enabled
# in the global config
#
IOCM_MAX_CORES_DEFAULT=4;


#============================================================================#
#                                                                            #
#                                logging                                     #
#                                                                            #
#============================================================================#

#
# print to dedicated log file only
#
PRINT_TO_STDOUT=false;

# abort on error
ABORT_ON_ERROR=true;

# disable log rotate
LOG_ROTATE=false;

#
# VM job's debug log
#
LOG_FILE="$VM_JOB_DIR/debug.log";


#============================================================================#
#                                                                            #
#                                  IOcm                                      #
#                                                                            #
#============================================================================#

#
# IOcm enabled
#
IOCM_ENABLED=true;

#
# Min amount of dedicated IO cores to be used
#
IOCM_MIN_CORES=0;

#
# Max amount of dedicated IO cores
# recommended amount is calculated by
#  ((allCores [divided by 2 if Hyper-Threading enabled])  minus 1 ForHostOS)
#
IOCM_MAX_CORES=7;

# list of nodes that have the iocm kernel in place
IOCM_NODES="omtnode.*";


#============================================================================#
#                                                                            #
#                             DPDK/virtIO/vRDMA                              #
#                                                                            #
#============================================================================#

#
# Indicates whether RoCE is available/enabled (see MIN_IO_CORE_COUNT/MAX_IO_CORE_COUNT)
#
VRDMA_ENABLED=true;

#
# list of nodes supporting RoCE feature for Infiniband
#
VRDMA_NODES='c3tnode0.*';


#============================================================================#
#                                                                            #
#                              SNAP MONITORING                               #
#                                                                            #
#============================================================================#

#
# Indicates whether the snap monitoring is enabled
#
SNAP_MONITORING_ENABLED=true;


##############################################################################
#                                                                            #
#                        DO NOT EDIT BELOW THIS LINE                         #
#                                                                            #
##############################################################################

#
# flag to disable the VM jobs completely, may be useful for troubleshooting
# used by the qsub wrapper only
#
if [ -z ${DISABLE_MIKELANGELO_HPCSTACK-} ]; then
  # not set in environment, apply config value
  DISABLE_MIKELANGELO_HPCSTACK=false;
# else: allow the user to set it in his environment
fi


#
# TRACE already set in the environment ?
#
if [ -z ${TRACE-} ] || [ "$TRACE" == "__TRACE__" ]; then
  TRACE=$TRACE_DEFAULT;
fi

#
# TRACE set in the environment ?
# if so enable debugging
#
if [ -z ${TRACE-} ] && $TRACE; then
  # if TRACE is enabled, debug is set to true
  DEBUG=true;
elif [ -z ${DEBUG-} ] || [ "$DEBUG" == "__DEBUG__" ]; then
  DEBUG=$DEBUG_DEFAULT;
fi

#
# Should we, in case of debugging enabled, keep the VM running for further
# investigations ?
# NOTE: this blocks until the user cancels with 'ctrl+c' or the walltime is hit
#
if [ -z ${KEEP_VM_ALIVE-} ]; then
  KEEP_VM_ALIVE=$KEEP_VM_ALIVE_DEFAULT;
fi



#
# path to shared workspace dir
#
SHARED_FS_JOB_DIR="$SHARED_FS_ROOT_DIR/$JOBID"; #user is not set in all scripts(?)

#
# NOTE: $RUID cannot be used for this as it is used in the root pro/epilogue scripts, too
#
RAMDISK="$RAMDISK_DIR_PREFIX/$JOBID";


#
# Path to the job submission tool binary 'qsub'.
#
if [[ "$LOCALHOST" =~ $SERVER_HOSTNAME ]]; then
  # path on server
  REAL_QSUB=$REAL_QSUB_ON_SERVER;
else
  # path on compute nodes (may differ)
  REAL_QSUB=$REAL_QSUB_ON_NODES;
fi



# '-n' do not read STDIN
# '-t[t]' Force pseudo-terminal allocation (multiple -t options force tty allocation, even if ssh has no local tty.)
# the -t, is useful for i.e. ssh non-tty mode fails to report pipes correctly ( => [[ -p /dev/stdout ]])
SSH_OPTS="-t -n -o BatchMode=yes -o ConnectTimeout=$SSH_TIMEOUT";
# '-B' batch mode (do not ask for pw)
SCP_OPTS="-B -o ConnectTimeout=$SSH_TIMEOUT";

# debugging enabled ?
if ! $DEBUG; then
  # '-q' quiet
  SSH_OPTS="$SSH_OPTS -q";
  SCP_OPTS="$SCP_OPTS -q";
fi

#
# In case of debugging, enable virsh debugging
#
if $DEBUG; then
  VIRSH_OPTS="--debug 3";
elif $TRACE; then
  VIRSH_OPTS="--debug 4";
else
  VIRSH_OPTS="-q";
fi

#
# allow to override env in dev mode
#
if $ENABLE_DEV_MODE; then
  if [ -n "${HOME-}" ]; then
    # user space
    homeDir="$HOME";
  elif [ $(id -u) -eq 0 ]; then
    # root pro/epilogue scripts (uid = 0)
    homeDir="$(grep $USERNAME /etc/passwd | cut -d':' -f6)";
  else
    # user pro/epilouge scripts (uid != 0)
    homeDir="$(grep $(id -u -n) /etc/passwd | cut -d':' -f6)";
  fi
  # env file exists ?
  if [ -f "$homeDir/99-mikelangelo-hpc_stack.sh" ]; then
    source "$homeDir/99-mikelangelo-hpc_stack.sh";
  fi
fi

