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
#

#=============================================================================
#
#         FILE: config.sh
#
#        USAGE: source config.sh
#
#  DESCRIPTION: vTorque configuration file.
#
#      OPTIONS: ---
# REQUIREMENTS: $RUID or $PBS_JOBID must be set and const.sh sourced.
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Nico Struckmann, struckmann@hlrs.de
#      COMPANY: HLRS, University of Stuttgart
#      VERSION: 0.3
#      CREATED: Oct 02nd 2015
#     REVISION: Jul 10th 2017
#
#    CHANGELOG
#         v0.2: more options added
#         v0.3: refactoring and cleanup
#
#=============================================================================
#
set -o nounset;

#
# determine absolute path to config file
#
ABSOLUTE_PATH_CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";


#============================================================================#
#                                                                            #
#                          CLUSTER CONFIGURATION                             #
#                                                                            #
#============================================================================#

#
# Regular expression for list of hosts where the VM jobs are disabled for submission
# for job submission, example:  DISABLED_HOSTS_LIST="frontend[0-9]"
#
DISABLED_HOSTS_LIST="";

#
# regex for hostnames of frontends, covers scenario:
#  front-ends and compute nodes have different paths to binaries
#
REGEX_FE="*";

#
# Torque's Home directory
#
TORQUE_HOME="/var/spool/torque";

#
# path to the real qsub binary on the front-ends
#
PBS_QSUB_ON_FE="/usr/bin/qsub";

#
# path to the real qsub binary on the compute nodes
#
PBS_QSUB_ON_NODES="/usr/bin/qsub";

#
# if user images are not allowed, the image must reside in this dir
#
VM_IMG_DIR="/opt/vm-images";

#
# Where suspended images are stored.
#
SUSPENDED_IMAGE_DIR="/opt/vm-images-suspended";

#
# Path to a fast shared file-system (used by jobs for intermediate data)
#
WS_DIR="/workspace/.vtorque";

#
# location for RAMdisks (if no shared fs for images is used)
#
RAMDISK_DIR="/ramdisk";

#
# NFS export for VM's "/home"
#
VM_NFS_HOME="nfs-server.my-domain.com:/nfs/homes/mikelangelo";

#
# NFS export for VM's "/workspace" (fast intermediate workspace, e.g. Lustre)
#
VM_NFS_WS="nfs-server.my-domain.com:/storage/mikelangelo/ssd_scratch";

#
# NFS export for VM's "/opt"
#
VM_NFS_OPT="nfs-server.my-domain.com:/nfs/shared-opt/mikelangelo";

#
# Full path to arp binary on the nodes.
#
ARP_BIN="/usr/sbin/arp";

#
# MAC prefix for VMs.
#
MAC_PREFIX="52:54:00"

#
# Amount of core reserved for the host OS
#
HOST_OS_CORE_COUNT=1;

#
# Amount of RAM dedicated to the physical host OS
#
HOST_OS_RAM_MB=2048;

#
# Indicates whether to submit VM jobs with '-l naccesspolicy=uniqueuser'.
# Not needed if there is a meta-scheduler on top ensuring it (i.e. MOAB)
#
PBS_EXCLUSIVE_NODE_ALLOC=true;

#
# Kills all user processes during the epilogue{.parallel}.
# Do not use if your nodes are NOT allocated exclusively or you are
# making use of NUMA domains for the scheduling in Torque
#
KILL_USER_PROCESSES_AFTER_JOB=true;


#============================================================================#
#                                                                            #
#                                TIMEOUTS                                    #
#                                                                            #
#============================================================================#

#
# SSH timeout
#
SSH_TIMEOUT=5;

#
# Timeout for polling processes during pro/epilogues
#
TIMEOUT=120;

#
# Timeout for processes that boot VMs and configure iocm
#
PROLOGUE_TIMEOUT=600;

#
# Timeout for files to appear on NFS
#
NFS_TIMEOUT=3;


#============================================================================#
#                                                                            #
#                       METADATA / DNS setup                                 #
#                                                                            #
#============================================================================#


#
# indicates whether we use DNS to assign IPs to VMs dynamically
#  or to use a static MAC-to-IP mapping
#
CUSTOM_IP_MAPPING=false;

#
# Script used to map MAC to IPs
#
IP_TO_MAC_SCRIPT="";

#
# DNS server
#
NAME_SERVER="name-server.my-domain.com";

#
# Domain
#
DOMAIN="my-domain.com";

#
# Search domain
#
SEARCH_DOMAIN="my-domain.com";


#============================================================================#
#                                                                            #
#                       METADATA / NTP setup                                 #
#                                                                            #
#============================================================================#

#
# NTP server #1
#
NTP_SERVER_1="ntp-server1.my-domain.com";

#
# NTP server #2
#
NTP_SERVER_2="ntp-server2.my-domain.com";


#============================================================================#
#                                                                            #
#                       METADATA / additional sw                             #
#                                                                            #
# NOTE:                                                                      #
# It is recommended to package the images with all sw required, however if   #
# a standard cloud image is used we need to install it during boot.          #
# If the software is already installed in the image, setup is skipped.       #
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
#                              VM DEFAULTS                                   #
#                                                                            #
#============================================================================#

#
# default file system type
# either ram disk (FILESYSTEM_TYPE_RD='ramdisk')
# or shared fs (FILESYSTEM_TYPE_SFS='sharedfs')
#
FILESYSTEM_TYPE_DEFAULT="$FILESYSTEM_TYPE_SFS";

#
# default image in case the user does not request one
# Name is relative to $GLOBAL_IMG_DIR
#
IMG_DEFAULT="ubuntu.x86_64.img";

#
# default distro, MUST match the IMG_DEFAULT
#
DISTRO_DEFAULT="debian";

#
# default virtual CPU architecture for guests
#
ARCH_DEFAULT="x86_64";

#
# default amount of vCPUs, mind the cores reserved for the host OS
#
VCPUS_DEFAULT="7";

#
# default for VCPU pinning (en/disabled)
#
VCPU_PINNING_DEFAULT=true;

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
# Default that is used in case there is no user defined value and it's enabled
# in the global config
#
VRDMA_ENABLED_DEFAULT=false;

#
# Default that is used in case there is no user defined value and it's enabled
# in the global config
#
UNCLOT_ENABLED_DEFAULT=false;

#
# Default amount of memory allocated for UNCLOT
#
UNCLOT_SHMEM_DEFAULT="1024M";

#
# Default that is used in case there is no user defined value and it's enabled
# in the global config
#
IOCM_ENABLED_DEFAULT=false;

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
#                                DEBUGGING                                   #
#                                                                            #
#============================================================================#

#
# DO NOT use it in production
#
ENABLE_DEV_MODE=false;

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


#============================================================================#
#                                                                            #
#                                LOGGING                                     #
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
# show log for batch jobs immediately after job submission
#
SHOW_LOG_DEFAULT=false;

#
# print to dedicated log file only
#
PRINT_TO_STDOUT=false;

#
# abort on error
#
ABORT_ON_ERROR=true;

#
# disable log rotate
#
LOG_ROTATE=true;

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
IOCM_ENABLED=false;

#
# Min amount of dedicated IO cores to be used
#
IOCM_MIN_CORES=0;

#
# Max amount of dedicated IO cores
# recommended amount is calculated by
#  ((allCores [divided by 2 if Hyper-Threading enabled])  minus 1 ForHostOS)
#
IOCM_MAX_CORES=12;

#
# list of nodes that have the iocm kernel in place
#
IOCM_NODES="*";


#============================================================================#
#                                                                            #
#                             DPDK/virtIO/vRDMA                              #
#                                                                            #
#============================================================================#

#
# Indicates whether RoCE is available/enabled (see MIN_IO_CORE_COUNT/MAX_IO_CORE_COUNT)
#
VRDMA_ENABLED=false;

#
# list of nodes supporting RoCE feature for Infiniband
#
VRDMA_NODES="*";


#============================================================================#
#                                                                            #
#                              UNCLOT (ivshmem)                              #
#                                                                            #
#============================================================================#

#
# Indicates whether UNCLOT is enabled
#
UNCLOT_ENABLED=false;


#============================================================================#
#                                                                            #
#                              SNAP MONITORING                               #
#                                                                            #
#============================================================================#

#
# Indicates whether the snap monitoring is enabled
#
SNAP_MONITORING_ENABLED=false;

#
# snap monitoring compute node bin dir
#
SNAP_BIN_DIR="/usr/local/bin/";

#
# snap task tag format
#
SNAP_TAG_FORMAT="snapTask-[username]-[jobid]";


##############################################################################
#                                                                            #
#                        DO NOT EDIT BELOW THIS LINE                         #
#                                                                            #
##############################################################################

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
if ${TRACE-false}; then
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
  KEEP_VM_ALIVE=false;
fi

#
# Path to shared workspace dir
#
SHARED_FS_JOB_DIR="$WS_DIR/$JOBID"; #user is not set in all scripts(?)

#
# Path for job's (optional) RAM disk.
#
RAMDISK="$RAMDISK_DIR/$JOBID";

#
# Path to the job submission tool binary 'qsub'.
#
if [[ "$LOCALHOST" =~ "$REGEX_FE" ]]; then
  # path on server
  PBS_QSUB="$PBS_QSUB_ON_FE";
else
  # path on compute nodes (may differ)
  PBS_QSUB="$PBS_QSUB_ON_NODES";
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
# In case of debugging, enable also virsh debugging
#
if $DEBUG; then
  VIRSH_OPTS="--debug 3";
elif $TRACE; then
  VIRSH_OPTS="--debug 4";
else
  VIRSH_OPTS="-q";
fi

#
# Allow users to override environment in dev mode ?
#
if $ENABLE_DEV_MODE; then
  if [ -n "${HOME-}" ]; then
    # user space
    homeDir="$HOME";
  elif [ $(id -u) -eq 0 ]; then
    # root pro/epilogue scripts (uid = 0)
    homeDir="$(grep $USER_NAME /etc/passwd | cut -d':' -f6)";
  else
    # user pro/epilouge scripts (uid != 0)
    homeDir="$(grep $(id -u -n) /etc/passwd | cut -d':' -f6)";
  fi
  # env file exists ?
  if [ -f "$homeDir/99-mikelangelo-hpc_stack.sh" ]; then
    source "$homeDir/99-mikelangelo-hpc_stack.sh";
  fi
else # security: enforce correct VTORQUE_DIR
  expectedDir="$(realpath $ABSOLUTE_PATH_CONFIG/..)";
  if [ "$expectedDir" != "$VTORQUE_DIR" ]; then # enforce correct path
    echo "ERROR: Using another vTorque installation than '\$VTORQUE_DIR' is not allowed.";
    VTORQUE_DIR=$expectedDir;
  fi
fi

#
# set debug mode, use export to make it in component script available
#
export DEBUG=$(\
  if ${DEBUG-false} || [ -e "$FLAG_FILE_DEBUG" ]; then \
    echo 'true'; else echo 'false'; fi);

#
# set trace mode, use export to make it in component script available
#
export TRACE=$(\
  if ${TRACE-false} || [ -e "$FLAG_FILE_TRACE" ]; then \
    echo 'true'; else echo 'false'; fi);

