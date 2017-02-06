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
source "$SCRIPT_BASE_DIR/common/root-config.sh";
source "$SCRIPT_BASE_DIR/common/root-functions.sh";


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
SNAP_TASK_ID_FILE="$VM_JOB_DIR/$LOCALHOST/snapID";

#
# snap task template file
#
SNAP_TASK_TEMPLATE_FILE="$SCRIPT_BASE_DIR/components/snap/snapTask.template.json";

#
# snap task template file
#
SNAP_TASK_JSON_FILE="$VM_JOB_DIR/$LOCALHOST/snapTask.json";


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

  if [ -z ${SNAPCTL-} ]; then
    logErrorMsg "Environment variable 'SNAPCTL' is not set !";
  fi
  
  if [ -z ${SNAP_BIN_DIR-} ]; then
    logErrorMsg "Environment variable 'SNAPCTL' is not set !";
  fi
  
  if [ -z ${SNAP_TASK_TAG-} ]; then
    logErrorMsg "Environment variable 'SNAP_TASK_TAG' is not set !";
  fi
  
  if [ -z ${SNAP_TAG_FORMAT-} ]; then
    logErrorMsg "Environment variable 'SNAP_TAG_FORMAT' is not set !";
  fi
  
  if [ -z ${SNAP_TASK_TEMPLATE_FILE-} ]; then
    logErrorMsg "Environment variable 'SNAP_TASK_TEMPLATE_FILE' is not set !";
  fi

  if [ ! -n "$(echo $PATH | grep $SNAP_BIN_DIR)" ]; then
    logErrorMsg "'SNAP_BIN_DIR'='$SNAP_BIN_DIR' is not included in 'PATH' !";
  fi
}

