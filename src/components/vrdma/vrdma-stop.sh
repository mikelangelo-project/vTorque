#!/bin/bash
#
# Copyright 2016-2017 HLRS, University of Stuttgart
# Copyright 2016-2017 Huawei Technologies Co., Ltd.
#
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
#         FILE: vrdma-stop.sh
#
#        USAGE: vrdma-stop.sh
#
#  DESCRIPTION: Tear down functionality for the vRDMA integration.
#      OPTIONS: ---
# REQUIREMENTS: vRDMA support must be installed, in both host and guest.
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Nico Struckmann, struckmann@hlrs.de
#               Shiqing Fan, shiqing.fan@huawei.com
#      COMPANY: HLRS, University of Stuttgart
#               Huawei Technologies Co., Ltd.
#      VERSION: 0.1
#      CREATED:
#     REVISION: ---
#
#    CHANGELOG
#         v0.2:
#
#=============================================================================
#
set -o nounset;
shopt -s expand_aliases;

# source the config and common functions
VRDMA_ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source "$VRDMA_ABSOLUTE_PATH/vrdma-common.sh";



#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#


#---------------------------------------------------------
#
# Removes all kernel modules that were loaded by vRDMA.
#
# Note:
#  Overlaps with previously loaded modules are not relevant
#  as the original list has been cached and will be restored.
#
removeKernelModules() {
  /sbin/rmmod vhost;
  /sbin/rmmod vhost_hyv;
  /sbin/rmmod mlx4_ib;
  /sbin/rmmod rdma_cm;
  /sbin/rmmod rdma_ucm;
  /sbin/rmmod vhost_rdmacm;
}


#---------------------------------------------------------
#
# Loads all kernel modules that were in place before.
#
reloadOrigModules() {
  for line in $(cat $VM_JOB_DIR/$LOCALHOST/kernel_modules); do
    moduleName="$(echo $line | xargs | cut -d' ' -f1)";
    /sbin/modprobe $moduleName;
    # success ?
    if [ $? -ne 0 ]; then
      logErrorMsg "Restoring previously loaded kernel module '$moduleName' failed!";
    fi
  done
}


#---------------------------------------------------------
#
# Restores IB port mode.
#
restoreIBmode() {

  # ensure we have 1 arg
  if [ $# -ne 1 ]; then
    logErrorMsg "Function 'restoreIBmode' expects '1' parameters, provided '$#'\nProvided params are: '$@'" 2;
  fi
  ibTargetPort=$1;

  # read the cached mode to apply
  ibTargetMode="$(cat $VM_JOB_DIR/$LOCALHOST/ib_mode_port$ibTargetPort)";
  switchIBmode $ibTargetPort $ibTargetMode;
}


#---------------------------------------------------------
#
# Tears down the vRDMA bridge.
#
tearDownBridge() {

  # release assigned IP
  /sbin/ifconfig $VRDMA_NIC_NAME 0;
  # disable IPoIB for the ib port
  /sbin/rmmod ib_ipoib;

  # release IPs
  /sbin/ifconfig $VRDMA_ROCE_PORT 0;
  /sbin/ifconfig $VRDMA_BRIDGE 0;

  # remove linux bridge and its roce port
  /sbin/brctl delif $VRDMA_BRIDGE $VRDMA_ROCE_PORT;
  /sbin/brctl delbr $VRDMA_BRIDGE;
}


#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

logInfoMsg "Tearing down vRDMA..";

# ensure everything is known / in place
checkVRDMAPreconditions;

# tear down bridge used by vRDMA
tearDownBridge;

# remove vRDMA modules
removeKernelModules;

# restore previous IB port mode
restoreIBmode $IB_TARGET_PORT;

# restore previously loaded kernel modules
reloadOrigModules;

logInfoMsg "Tearing down vRDMA done.";

# done
exit 0;
