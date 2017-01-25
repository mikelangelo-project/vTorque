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

ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source "$ABSOLUTE_PATH/../../common/const.sh";
source "$ABSOLUTE_PATH/../../common/config.sh";
source "$ABSOLUTE_PATH/../../common/functions.sh";

#
# snap monitoring compute node bin dir
#
SNAP_BIN_DIR="/usr/local/bin/";


# construct the task tag
SNAP_TASK_TAG="snapTask-$USERNAME-$JOBID";


#
# snap task tag format
#
SNAP_TAG_FORMAT="snapTask-[username]-[jobid]";

#
# snap task ID file
#
SNAP_TASK_ID_FILE="$VM_JOB_DIR/$LOCALHOST/snapID"


#
# snap task template file
#
SNAP_TASK_TEMPLATE_FILE="$ABSOLUTE_PATH../../templates/snapTask.json"


#
# snap task template file
#
SNAP_TASK_JSON_FILE="$VM_JOB_DIR/$LOCALHOST/task.json"


# define bin paths
export SNAPCTL="$SNAP_BIN_DIR/snaptel";
export PATH="$PATH:$SNAP_BIN_DIR";



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
checkSnapPreconditions() {

  if [ -z ${DB_HOST-} ]; then
    logErrorMsg "Environment variable 'DB_HOST' is not set !";
  fi

  if [ -z ${DB_NAME-} ]; then
    logErrorMsg "Environment variable 'DB_NAME' is not set !";
  fi

  if [ -z ${DB_USER-} ]; then
    logErrorMsg "Environment variable 'DB_USER' is not set !";
  fi

  if [ -z ${DB_PASS-} ]; then
    logErrorMsg "Environment variable 'DB_PASS' is not set !";
  fi

  if [ ! -n "${TAGS-}" ]; then
    logErrorMsg "Environment variable 'TAGS' is not set !";
  fi

  if [ -z ${SNAPCTL-} ]; then
    logErrorMsg "Environment variable 'SNAPCTL' is not set !";
  fi

  if [ -z ${METRICS-} ]; then
    logErrorMsg "Environment variable 'METRICS' is not set !";
  fi

  if [ -z ${INTERVAL-} ]; then
    logErrorMsg "Environment variable 'INTERVAL' is not set !";
  fi

  if [ ! -n "$(echo $PATH | grep $SNAP_BIN_DIR)" ]; then
    logErrorMsg "'SNAP_BIN_DIR'='$SNAP_BIN_DIR' is not included in 'PATH' !";
  fi
}

