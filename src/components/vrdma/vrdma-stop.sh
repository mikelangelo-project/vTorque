#!/bin/bash
#
# Copyright 2016-2017 HLRS, University of Stuttgart
# Copyright 2016 Huawei Technologies Co., Ltd.
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
source $VRDMA_ABSOLUTE_PATH/vrdma-common.sh;



#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#


#---------------------------------------------------------
#
# Stops vRDMA (OVS and DHCP services)
#
stopQEMU() {

  # We need to make sure that all QEMU processes are terminated,
  # as there might be hanging processes which cannot be stopped by exiting libvirt
  logDebugMsg "Stopping qemu."
  [ -n '$(pidof qemu-system-x86_64)' ] && killall qemu-system-x86_64;
}


#---------------------------------------------------------
#
# Stops all OVS services
#
stopOVSservices() {
  #stop services
  logDebugMsg "Stopping OVS services.";
  [ -n '$(pidof ovs-vswitchd)' ] && killall ovs-vswitchd;
  [ -n '$(pidof qemu-system-x86_64)' ] && killall ovsdb-server;
}


#---------------------------------------------------------
#
# Stops the DHCP server dedicated to the vRDMA-bridge.
#
stopDHCPserver() {
  # stop DHCP server
  logDebugMsg "Stopping local DHCP server.";
  service isc-dhcp-server stop;
}



#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

# ensure everything is known / in place
checkVRDMAPreconditions;

# stop qemu
stopQEMU;

# stop all OVS services
stopOVSservices;

# remove vRDMA bridge
removeBridge;

# clean up files
cleanupFiles;

# stop DHCP server
stopDHCPserver;

# done
exit 0;
