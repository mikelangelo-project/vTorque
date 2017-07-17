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
#         FILE: snap-common.sh
#
#        USAGE: source snap-common.sh
#
#  DESCRIPTION: Constants, configuration and functions for the snap telemtry
#               integration.
#      OPTIONS: ---
# REQUIREMENTS: Snap Telemetry must be installed.
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
source "$VTORQUE_DIR/common/const.sh" $@;
source "$VTORQUE_DIR/common/config.sh";
source "$VTORQUE_DIR/common/root-functions.sh";

#
# happens in case of manual debugging
#
if [ ! -f $LOG_FILE ]; then
  # prevents dir to be created as root
  LOG_FILE=/dev/null;
fi
if [ ! -d $VM_JOB_DIR ]; then
  # prevents snap to fail, the task template needs to be written
  VM_JOB_DIR=/tmp/;
fi


#============================================================================#
#                                                                            #
#                                CONFIG                                      #
#                                                                            #
#============================================================================#

# construct the task tag
SNAP_TASK_TAG="snapTask-$USER_NAME-$JOBID";

#
# snap task ID file
#
SNAP_TASK_ID_FILE="$VM_JOB_DIR/$LOCALHOST/snapID";

#
# snap task template file
#
SNAP_TASK_TEMPLATE_FILE="$VTORQUE_DIR/components/snap/snapTask.template.json";

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

