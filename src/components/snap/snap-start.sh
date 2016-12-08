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
# Tags the snap task so it can be associated to the job.
#
tagTask() {

  # check if binaries are available and executable
  if [ ! -x $SNAP_BIN_DIR/snapcontroller ] \
      || [ ! -x $SNAP_BIN_DIR/snapctl ]; then
    logWarnMsg "Snap Monitoring is enabled, but its binaries cannot be found or executed! SNAP_BIN_DIR='$SNAP_BIN_DIR'";
    return -1;
  fi

  # tag the snap monitoring task
  logDebugMsg "Tagging snap monitoring task for job '$JOBID' with tag '$SNAP_TASK_TAG' using format '$SNAP_TAG_FORMAT'";
  logTraceMsg "~~~~~~~~~~Environment_Start~~~~~~~~~~\n$(env)\n~~~~~~~~~~~Environment_End~~~~~~~~~~~";

  #
  # dirty quick fix for:
  #  InfluxDB connector opens too many files and dies after ~30min
  #
  ulimit -n 6000; #INTEL uses 6000 successfully

  if $DEBUG; then
    # show what's happening
    $SNAP_BIN_DIR/snapcontroller --snapctl $SNAP_BIN_DIR/snapctl ct $SNAP_TASK_TAG |& tee -a $LOG_FILE;
  else
    # be quiet
    $SNAP_BIN_DIR/snapcontroller --snapctl $SNAP_BIN_DIR/snapctl ct $SNAP_TASK_TAG > /dev/null 2>&1;
  fi
  res=$?;

  # debug + trace logging
  logDebugMsg "Snap controller's return code: '$res'";
  logTraceMsg "Content of snap's JSON\
\n~~~~~~~~~~~Snap_Temp_File_BEGIN~~~~~~~~~~~\n\
$(cat /tmp/task_${SNAP_TASK_TAG}.json | python -m json.tool)\
\n~~~~~~~~~~~~Snap_Temp_File_END~~~~~~~~~~~~";

  # pass on return code
  return $res;
}



#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

logInfoMsg "Setting up SNAP monitoring..";

# ensure everything is known / in place
checkSnapPreconditions;

# tag task
tagTask;
res=$?;

logInfoMsg "Setting up SNAP monitoring done.";

# pass on return code
exit $res;