#!/bin/bash
#
# Copyright 2016-2017 HLRS, University of Stuttgart
# Copyright 2016-2017 Huawei Technologies Co., Ltd.
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
#         FILE: vrdma-start.sh
#
#        USAGE: vrdma-start.sh
#
#  DESCRIPTION: Startup functionality for the vRDMA integration.
#      OPTIONS: ---
# REQUIREMENTS: vRDMA support must be installed, in both host and guest.
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Nico Struckmann, struckmann@hlrs.de
#               Shiqing Fan, shiqing.fan@huawei.com
#      COMPANY: HLRS, University of Stuttgart
#               Huawei Technologies Co., Ltd.
#      VERSION: 0.2
#      CREATED:
#     REVISION: ---
#
#    CHANGELOG
#         v0.2: vRDMA prototype 2 support
#
#=============================================================================
#
set -o nounset;
shopt -s expand_aliases;

# source the config and common functions
VRDMA_ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source "$VRDMA_ABSOLUTE_PATH/vrdma-common.sh";

#
# amount of VMs that are associated with the current job (if any)
#
VMS_PER_HOST=$(getVMsPerNode);


#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#


#---------------------------------------------------------
#
# vRDMA component's abort logic when a job is canceled while this script runs.
# Returns error/success code for the cleanup.
#
_abort() {
  $VRDMA_ABSOLUTE_PATH/vrdma-stop.sh;
  return $?;
}


#---------------------------------------------------------
#
# Creates the configuration file needed for libvirt.
#
createConfig() {

  logDebugMsg "Creating vRDMA config file for libvirt...";

  # ensure we have 1 arg
  if [ $# -ne 1 ]; then
    logErrorMsg "Function 'switchIBmode' expects '1' parameters, provided '$#'\nProvided params are: '$@'" 2;
  fi
  ibTargetPort=$1;

  logDebugMsg "Creating libvirt configuration file for IB port '$ibTargetPort'";

  # ensure kernel module 'ib_uverbs' &is available, required by idv_devinfo
  if [ ! -n "$(ibv_devinfo |& grep 'Function not implemented')" ]; then
    logDebugMsg "Kernel module 'ib_uverbs' not loaded, trying to do so now..";
    modprobe ib_uverbs;
    if [ $? -eq 0 ]; then
      logDebugMsg "Kernel module 'ib_uverbs' successfully loaded.";
    else
      logErrorMsg "Required kernel module 'ib_uverbs' is not available and cannot be loaded.";
    fi
  fi

  # determine node's guid
  ibNodeGUID="$(ibv_devinfo | grep node_guid | xargs | cut -d' ' -f2)";

  # ensure user cannot alter the file
  touch $VM_JOB_DIR/$LOCALHOST/ib_mode_port$ibTargetPort;
  chmod 600 $VM_JOB_DIR/$LOCALHOST/ib_mode_port$ibTargetPort;

  # create configuration file
  echo "$ibNodeGUID" > $VRDMA_CONFIGFILE;
  logTraceMsg "\
~~~~~~~~~~~~~~~vRDMA config file start~~~~~~~~~~~~~\n\
$(cat $VRDMA_CONFIGFILE)\
\n~~~~~~~~~~~~~~~~vRDMA config file end~~~~~~~~~~~~~~";
}


#---------------------------------------------------------
#
# Caches the currently loaded kernel modules in a flat file.
#
cacheLoadedModules() {

  logDebugMsg "Caching currently loaded modules..";

  # ensure user cannot alter the file
  touch $VM_JOB_DIR/$LOCALHOST/kernel_modules;
  chmod 600 $VM_JOB_DIR/$LOCALHOST/kernel_modules;

  # cache list of loaded modules
  lsmod > $VM_JOB_DIR/$LOCALHOST/kernel_modules;
  logTraceMsg "\
~~~~~~~~~~~~~~~list of loaded kernel modules file start~~~~~~~~~~~~~\n\
$(cat $VM_JOB_DIR/$LOCALHOST/kernel_modules)\
\n~~~~~~~~~~~~~~~~list of loaded kernel modules file end~~~~~~~~~~~~~~";
}


#---------------------------------------------------------
#
# Caches the current IB mode in a flat file.
#
cacheIBmode() {

  # ensure we have 1 arg
  if [ $# -ne 1 ]; then
    logErrorMsg "Function 'switchIBmode' expects '1' parameters, provided '$#'\nProvided params are: '$@'" 2;
  fi
  ibTargetPort=$1;

  logDebugMsg "Caching current IB mode for port '$ibTargetPort'.";

  # ensure user cannot alter the file
  touch $VM_JOB_DIR/$LOCALHOST/ib_mode_port$ibTargetPort;
  chmod 600 $VM_JOB_DIR/$LOCALHOST/ib_mode_port$ibTargetPort;

  # write cache file
  echo $(getIBMode $ibTargetPort) > $VM_JOB_DIR/$LOCALHOST/ib_mode_port$ibTargetPort;
}


#---------------------------------------------------------
#
# Loads kernel modules required for vRDMA.
#
loadKernelModules() {

  logDebugMsg "Loading required kernel modules for vRDMA...";

  # ensure there is no local subnet manager running
  service opensm stop;

  # remove conflicting kernel modules (use for all rmmod xyz '2> /dev/null' in case of non-debugging)
  listOfConflictingModules="\
    rdma_ucm\
    ib_ucm\
    ib_ipoib\
    vhost_rdmacm\
    rdma_cm\
    ib_cm\
    mlx4_ib\
    ib_sa\
    iw_cm\
    ib_umad\
    ib_mthca \
    ib_mad\
    ib_uverbs\
    ib_ipoib\
    vhost_rdmacm\
    rdma_cm\
    mlx4_ib\
    mlx5_ib\
    vhost_hyv\
    ib_core
  ";

  # remove kernel modules
  for module in $listOfConflictingModules; do
    # ignore errors, since not all modules may be loaded
    /sbin/rmmod $module 2> /dev/null;
  done

  # reload ib_core module
  /sbin/modprobe ib_core;
  # success ?
  if [ $? -ne 0 ]; then
    logErrorMsg "vRDMA setup failed, due to errors when loading required kernel module 'ib_core'";
  fi

  # load vhost and necessary host modules \
  /sbin/modprobe vhost \
  && /sbin/modprobe vhost_hyv \
  && /sbin/modprobe mlx4_ib \
  && /sbin/modprobe rdma_cm \
  && /sbin/modprobe rdma_ucm \
  && /sbin/modprobe vhost_rdmacm;
  # success ?
  if [ $? -ne 0 ]; then
    logErrorMsg "vRDMA setup failed, due to errors when loading required kernel modules.";
  fi

  # used by ibv_devinfo
  /sbin/modprobe ib_uverbs;
  # success ?
  if [ $? -ne 0 ]; then
    logErrorMsg "vRDMA setup failed, due to errors when loading required kernel module 'ib_uverbs'.";
  fi

  # load kernel module ib_umad
  /sbin/modprobe ib_umad;
  # success ?
  if [ $? -ne 0 ]; then
    logErrorMsg "vRDMA setup failed, due to errors when loading required kernel module 'ib_umad'.";
  fi

  # start opensm service [TODO] on first node, only
  service opensm start;

  # success ?
  if [ $? -ne 0 ]; then
    logErrorMsg "vRDMA setup failed, due to errors when starting IB subnet manager service 'opensm'";
  fi
}


#---------------------------------------------------------
#
# Sets up the bridge needed for vRDMA.
#
setupBridge() {

  logDebugMsg "Creating vRDMA bridge...";

  # create a linux bridge over roce port
  /sbin/brctl addbr $VRDMA_BRIDGE \
  && /sbin/brctl addif $VRDMA_BRIDGE $VRDMA_ROCE_PORT;
  # success ?
  if [ $? -ne 0 ]; then
    logErrorMsg "vRDMA bridge setup failed.";
  fi

  # configure network bridge (remove IP from roce port)
  /sbin/ifconfig $VRDMA_ROCE_PORT 0 \
  && /sbin/ifconfig $VRDMA_BRIDGE $VRDMA_BRDIGE_ADDRESS;
  # success ?
  if [ $? -ne 0 ]; then
    logErrorMsg "vRDMA bridge setup failed.";
  fi

  # enable IPoIB for the IB port
  /sbin/modprobe ib_ipoib;
  # success ?
  if [ $? -ne 0 ]; then
    logErrorMsg "vRDMA setup failed, due to errors when loading required kernel module 'ib_ipoib'.";
  fi

  /sbin/ifconfig $VRDMA_NIC_NAME $VRDMA_BRDIGE_ADDRESS;
  # success ?
  if [ $? -ne 0 ]; then
    logErrorMsg "vRDMA setup failed, due to errors when assigning address '$VRDMA_BRDIGE_ADDRESS' to interface '$VRDMA_NIC_NAME'.";
  fi
}



#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

logInfoMsg "Setting up vRDMA..";

# ensure everything is known / in place
checkVRDMAPreconditions;

# create config file needed by libvirt
createConfig $IB_TARGET_PORT;

# cache the list of currently loaded modules in order to be able to revert it
cacheLoadedModules;

# load kernel modules
loadKernelModules;

# remember the current IB port's mode in order to restore it
cacheIBmode $IB_TARGET_PORT;

# ensure IB port is is mode 'AutoSense'
switchIBmode $IB_TARGET_PORT $VRDMA_IB_PORT_MODE;

# setup the vRDMA bridge
setupBridge;

logInfoMsg "Setting up vRDMA done.";

# setup done
exit 0;
