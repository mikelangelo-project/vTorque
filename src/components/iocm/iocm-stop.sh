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
#         FILE: iocm-stop.sh
#
#        USAGE: iocm-stop.sh
#
#  DESCRIPTION: Tear down logic for IOcm, needs to be executed as root.
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
IOCM_ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source "$IOCM_ABSOLUTE_PATH/iocm-common.sh";



#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#

#---------------------------------------------------------
#
# Releases the min/max amount of cores bound to IOcm.
#
unsetCores() {
  logDebugMsg "Releasing iocm cores..";
  $IOCM_ABSOLUTE_PATH/dynamic-io-manager/src/stop_io_manager.py;
  return $?;
}


#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

logInfoMsg "Stopping I/O Core Manager (IOCM)..";

# release cores managed by IOcm
unsetCores;
res=$?;

# in verbose mode print the file that is created if DEBUG is enabled
if $TRACE; then
  logTraceMsg "\
~~~~~~~~~~~~~~~~~IOcm log file start~~~~~~~~~~~~~~~\n\
$(cat $IOCM_LOG_FILE)\
\n~~~~~~~~~~~~~~~~~IOcm log file end~~~~~~~~~~~~~~~";
fi

# success ?
if [ $res -eq 0 ]; then
  logInfoMsg "Stopping IOCM done.";
else
  logWarnMsg "Stopping IOCM failed, error code: '$res'";
fi

# pass on return code
exit $res;
