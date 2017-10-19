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
#         FILE: vrdma-common.sh
#
#        USAGE: source vrdma-common.sh
#
#  DESCRIPTION: Constants, configuration and functions for the vRDMA
#               integration.
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

set -o nounset;
shopt -s expand_aliases;

# source the config and common functions
source /etc/profile.d/99-mikelangelo-hpc_stack.sh;
source "$VTORQUE_DIR/common/const.sh";
source "$VTORQUE_DIR/common/config.sh";
source "$VTORQUE_DIR/common/root-functions.sh";

#
# happens in case of manual debugging
#
if [ ! -f $LOG_FILE ]; then
  # prevents logfile's dir to be created as root
  LOG_FILE=/dev/null;
fi


#
# File that contains the IB node guid.
#
# Note:
#  counterpart is defined in the domain-fragment-vrdma.xml
#
VRDMA_CONFIGFILE="$VM_JOB_DIR/$LOCALHOST/vrdma.conf";

#
# Networking for vRDMA bridge
#
VRDMA_BRDIGE_ADDRESS=10.0.0.100/24;

#
# Bridge to use for vRDMA
#
VRDMA_BRIDGE=br0;

#
# IB target port for vRDMA setup
#
IB_TARGET_PORT=1; # always pick the first IB port for vRDMA

#
# IB port mode to use for vRDMA.
#
VRDMA_IB_PORT_MODE="AutoSense";

#
# Name of the ROCE port used by vRDMA
#
VRDMA_ROCE_PORT="roce0";

#
# Name of the IB interface that will be bridged
#
VRDMA_NIC_NAME="ib0";


#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#


#---------------------------------------------------------
#
# Ensures all environment variables are in place.
# If not it aborts with an error.
#
checkVRDMAPreconditions() {
  if [ ! -d "$VM_JOB_DIR" ]; then
    logDebugMsg "Skipping vRDMA. No job dir found, assuming non-VM job.";
    exit 1;
  fi
}


#---------------------------------------------------------
#
# Prints the IB bus address to STDOUT.
#
# Parameter
#  none
#
# Returns
#  nothing
#
getBusAddress() {
  echo "$(lspci | grep Mellanox | awk '{print $1}')";
}


#---------------------------------------------------------
#
# Prints the current mode for the requested IB port to
# STDOUT.
# Valid modes are: Infiniband, Ethernet or AutoSense.
#
# Parameter
#  $1: IB target port (i.e. 1 or 2)
#  $2: IB target mode, one of: Infiniband, Ethernet, AutoSense
#
# Returns
#  nothing
#
getIBMode() {

  # ensure we have 1 arg
  if [ $# -ne 1 ]; then
    logErrorMsg "Function 'getIBMode' expects '1' parameter, provided '$#'\nProvided params are: '$@'" 2;
  fi

  ibTargetPort=$1;
  ibBusAddr="$(getBusAddress)";

  # print to STDOUT
  cat /sys/bus/pci/devices/0000:$ibBusAddr/mlx4_port$ibTargetPort;
}


#---------------------------------------------------------
#
# Switches the mode of the IB port.
#
# Parameter
#  $1: IB target port (i.e. 1 or 2)
#  $2: IB target mode, one of: Infiniband, Ethernet, AutoSense
#
# Returns
#  nothing
#
switchIBmode() {

  # ensure we have 2 args
  if [ $# -ne 2 ]; then
    logErrorMsg "Function 'switchIBmode' expects '2' parameters, provided '$#'\nProvided params are: '$@'" 2;
  fi

  ibTargetPort=$1; # port number, i.e. '1'
  ibTargetMode=$2; # mode, one of: Infiniband, Ethernet, AutoSense

  ibBusAddr="$(getBusAddress)";
  ibCurrentMode="$(getIBMode $ibTargetPort)";

  # switch if needed
  logDebugMsg "Current mode of IB port '$ibTargetPort' is '$ibCurrentMode'";
  if [ "$ibCurrentMode" == "$ibTargetMode" ]; then
    logDebugMsg "No changes for mode on IB port '$ibTargetPort'";
  else
    echo $ibTargetMode > /sys/bus/pci/devices/0000:$ibBusAddr/mlx4_port$ibTargetPort;
    logInfoMsg "Mode of IB port '$ibTargetPort' is changed to '$ibTargetMode'";
  fi
}

