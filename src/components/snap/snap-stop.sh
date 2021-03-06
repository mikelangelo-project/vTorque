#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

#=============================================================================
#
#         FILE: iocm-stop.sh
#
#        USAGE: iocm-stop.sh
#
#  DESCRIPTION: Tear down logic for Snap Telemetry, needs to be executed as root.
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
SNAP_ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source "$SNAP_ABSOLUTE_PATH/snap-common.sh";



#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#


#---------------------------------------------------------
#
# Release job related tag from snap task.
#
untagTask() {


  # check if binaries are available and executable
  if [ ! -x $SNAPCTL ]; then
    logWarnMsg "Snap Monitoring is enabled, but its binaries cannot be found or executed! SNAP_BIN_DIR='$SNAP_BIN_DIR'";
    return -1;
  fi

  # release tag the snap monitoring task
  logDebugMsg "Release snap monitoring task for job '$JOBID' with tag '$SNAP_TASK_TAG' using format '$SNAP_TAG_FORMAT'";
  if [ ! -f "$SNAP_TASK_ID_FILE" ]; then
    logWarnMsg "Snap Task ID file '$SNAP_TASK_ID_FILE' not found.";
    return 1;
  fi
  # Get snap task name
  SNAP_TASK_ID="$(cat $SNAP_TASK_ID_FILE)"
  logDebugMsg "Looking into cached task id, file '$SNAP_TASK_ID_FILE' found id '$SNAP_TASK_ID'";

  # Stop task
  logDebugMsg "Stopping snap task with ID '$SNAP_TASK_ID'"
  snapCtlOutput="$($SNAPCTL task stop $SNAP_TASK_ID 2>&1)";
  res=$?;
  if [ $res -ne 0 ]; then
    logInfoMsg "Stopping snap task with ID '$SNAP_TASK_ID' failed with code '$res' and msg:\n\t$snapCtlOutput";
  fi

  # Remove task
  logDebugMsg "Removing snap task with ID '$SNAP_TASK_ID'";
  snapCtlOutput="$($SNAPCTL task remove $SNAP_TASK_ID 2>&1)";
  res=$?;
  if [ $res -ne 0 ]; then
    logWarnMsg "Removing snap task with ID '$SNAP_TASK_ID' failed:\n\t$snapCtlOutput";
  fi

  # pass on return code
  return $res;
}



#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

logInfoMsg "Stopping SNAP monitoring..";

# tag task
untagTask;
res=$?;

# success ?
if [ $res -eq 0 ]; then
  logInfoMsg "Stopping SNAP monitoring done.";
else
  logWarnMsg "Stopping SNAP failed, error code: '$res'";
fi

# pass on return code
exit $res;
