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
# Tags the snap task so it can be associated to the job.
#
tagTask() {

  # check if binaries are available and executable
  if [ ! -x $SNAPCTL ]; then
    logWarnMsg "Snap Monitoring is enabled, but its binaries cannot be found or executed! SNAP_BIN_DIR='$SNAP_BIN_DIR'";
    return -1;
  fi

  # tag the snap monitoring task
  logDebugMsg "Tagging snap monitoring task for job '$JOBID' with tag '$SNAP_TASK_TAG' using format '$SNAP_TAG_FORMAT'";
  logTraceMsg "~~~~~~~~~~Environment_Start~~~~~~~~~~\n$(env)\n~~~~~~~~~~~Environment_End~~~~~~~~~~~";

  # ensure dir exists
  destDir=$(dirname SNAP_TASK_JSON_FILE);
  if [ ! -d $destDir ] ;then
    logDebugMsg "Creating destination dir '$destDir' for snap task template file.";
    mkdir -p $destDir || logErrorMsg "Failed to create destination dir for snap task template file '$SNAP_TASK_JSON_FILE'.";
    chown $USERNAME:$USERNAME $destDir;
  fi

  # move template
  logDebugMsg "Moving template file '$SNAP_TASK_TEMPLATE_FILE' to job folder '$SNAP_TASK_JSON_FILE'";
  cp $SNAP_TASK_TEMPLATE_FILE $SNAP_TASK_JSON_FILE;
  # create Task from template
  sed -i "s,__SNAP_TASK_NAME__,$SNAP_TASK_TAG,g" $SNAP_TASK_JSON_FILE;
  logTraceMsg "~~~~~~~~~~SNAP_TASK_JASON_Start~~~~~~~~~~\n$(cat $SNAP_TASK_JSON_FILE | python -m json.tool)\n~~~~~~~~~~SNAP_TASK_JASON_End~~~~~~~~~~";

  # create Task
  logDebugMsg "Tagging snap monitoring task for job '$JOBID' with tag '$SNAP_TASK_TAG' using format '$SNAP_TAG_FORMAT'";
  logTraceMsg "~~~~~~~~~~Environment_Start~~~~~~~~~~\n$(env)\n~~~~~~~~~~~Environment_End~~~~~~~~~~~";

  # verbose logging
  logTraceMsg "Content of snap's JSON config file\
\n~~~~~~~~~~~Snap_Config_File_BEGIN~~~~~~~~~~~\n\
$(cat $SNAP_TASK_TEMPLATE_FILE | python -m json.tool)\
\n~~~~~~~~~~~~Snap_Config_File_END~~~~~~~~~~~~";

  # create and start task
  snapCtlOutput="$($SNAPCTL task create -t $SNAP_TASK_JSON_FILE)"
  res=$?

  # logging
  if [ $res -ne 0 ]; then
    logWarnMsg "Snap task creation failed:\n\t$snapCtlOutput\nreturn code is '$res'";
  else
    logDebugMsg "Snap task successfully created: $snapCtlOutput";

    # determine snap task's name
    snapTaskName="$(echo $snapCtlOutput | grep Name)"

    # determine task ID
    logDebugMsg "Snap task '$snapTaskName' created and started";
    snapTaskID=$(echo ${snapTaskName} | awk -F'Name: Task-' '{print $2}')
    logDebugMsg "Snap task 'snapTaskName' has ID '$snapTaskID'";

    # cache task ID
    echo $snapTaskID > $SNAP_TASK_ID_FILE;
    logTraceMsg "Caching Snap ID '$snapTaskID' in file '$SNAP_TASK_ID_FILE'";
    logTraceMsg "~~~~~~~~~~SNAP_TASK_ID_FILE_Start~~~~~~~~~~\n$(cat $SNAP_TASK_ID_FILE)\n~~~~~~~~~~~SNAP_TASK_ID_FILE_End~~~~~~~~~~~";
  fi
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