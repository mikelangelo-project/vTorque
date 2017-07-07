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
#         FILE: iocm-common.sh
#
#        USAGE: source iocm-common.sh
#
#  DESCRIPTION: Constants, configuration and functions for the IOcm integration.
#      OPTIONS: ---
# REQUIREMENTS: IOcm must be installed.
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Nico Struckmann, struckmann@hlrs.de
#      COMPANY: HLRS, University of Stuttgart
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
source /etc/profile.d/99-mikelangelo-hpc_stack.sh;
source "$VTORQUE_DIR/common/const.sh";
source "$VTORQUE_DIR/common/root-config.sh";
source "$VTORQUE_DIR/common/root-functions.sh";



#============================================================================#
#                                                                            #
#                                CONFIG                                      #
#                                                                            #
#============================================================================#

#
# iocm config file
#
IOCM_JSON_CONFIG="$VM_JOB_DIR/$LOCALHOST/iocm-config.json";

#
# Name of the network interface to be used for i/o operations
#
IOCM_INTERFACE_NAME="ib0";

#
# Debug log for iocm
#
IOCM_LOG_FILE="$VM_JOB_DIR/$LOCALHOST/iocm.log";



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
checkIOcmPreconditions() {
  # check for kernel mod 'stats'
  if [ -n "$(lsmod | grep stats)" ]; then
    logDebugMsg "IOcm Kernel detected, version: $kernelVersion";
  else
    logErrorMsg "No IOcm kernel available.";
  fi

}
