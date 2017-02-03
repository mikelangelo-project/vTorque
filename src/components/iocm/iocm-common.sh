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

set -o nounset;
shopt -s expand_aliases;

# source the config and common functions
source /etc/profile.d/99-mikelangelo-hpc_stack.sh;
source "$SCRIPT_BASE_DIR/common/const.sh";
source "$SCRIPT_BASE_DIR/common/config.sh";
source "$SCRIPT_BASE_DIR/common/functions.sh";


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
  # check uname
  kernelVersion="$(uname -a)";
  if [[ $kernelVersion =~ ]]; then
    logDebugMsg "IOcm Kernel version: $kernelVersion";
  else
    logErrorMsg "No IOcm kernel available.";
  fi

}
