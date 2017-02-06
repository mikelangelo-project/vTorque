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
#

set -o nounset;
shopt -s expand_aliases;

# source the config and common functions
ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source $ABSOLUTE_PATH/snap-common.sh;



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
  logTraceMsg "~~~~~~~~~~Environment_Start~~~~~~~~~~\n$(env)\n~~~~~~~~~~~Environment_End~~~~~~~~~~~";

  # Get snap task name
  SNAP_TASK_ID="$(cat $SNAP_TASK_ID_FILE)"
  logDebugMsg "Looking into cached task id, file '$SNAP_TASK_ID_FILE' found id '$SNAP_TASK_ID'";

  # Stop task
  logDebugMsg "Stopping snap task with ID '$SNAP_TASK_ID'"
  snapCtlOutput="$($SNAPCTL task stop ${SNAP_TASK_ID})";
  res=$?;
  if [ $res -ne 0 ]; then
    logInfoMsg "Stopping snap task with ID '$SNAP_TASK_ID' failed:\n\t$snapCtlOutput";
  fi

  # Remove task
  logDebugMsg "Removing snap task with ID '$SNAP_TASK_ID'";
  snapCtlOutput="$($SNAPCTL task remove ${SNAP_TASK_ID})";
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

# tag task
untagTask;

# pass on return code
exit $?;
