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




# construct the task tag
SNAP_TASK_TAG="snapTask-$USERNAME-$JOBID";

# construct the task tag
SNAP_TASK_TAG="snapTask-$USERNAME-$JOBID";

#
# snap monitoring compute node bin dir
#
SNAP_BIN_DIR="/etc/snap/custom-v0.02/bin";

#
# DB host for snap monitoring
#
SNAP_DB_HOST="172.18.2.74";

#
# Name of snap DB
#
SNAP_DB_NAME="snap";

#
# Name of snap DB user
#
SNAP_DB_USER="admin";

#
# PAssword for snap DB user
#
SNAP_DB_PASS="admin";

#
# Snap task tag format
#
SNAP_TAG_FORMAT="experiment:experiment:nr, job_number: $JOBID";

#
# Interval for update monitoring data
#
SNAP_UPDATE_INTERVALL="2s";

#
# enabled snap plug-ins
#
METRIC_PLUGINS="/intel/linux/iostat/device/sda/avgqu-sz,\
/intel/linux/iostat/device/sda/avgrq-sz,\
/intel/linux/iostat/device/sda/%util,\
/intel/linux/iostat/avg-cpu/%user,\
/intel/linux/iostat/avg-cpu/%idle,\
/intel/linux/iostat/avg-cpu/%system,\
/intel/psutil/net/eth0/bytes_recv,\
/intel/psutil/net/eth0/bytes_sent,\
/intel/psutil/net/eth1/dropin,\
/intel/psutil/net/eth1/dropout,\
/intel/psutil/net/eth1/errin,\
/intel/psutil/net/eth1/errout,\
/intel/psutil/load/load1,\
/intel/psutil/load/load15,\
/intel/psutil/load/load5";



# define DB connection
export DB_HOST="$SNAP_DB_HOST";
export DB_NAME="$SNAP_DB_NAME";
export DB_USER="$SNAP_DB_USER";
export DB_PASS="$SNAP_DB_PASS";

# define tag format
export TAGS="$SNAP_TAG_FORMAT";

# define bin paths
export SNAPCTL="$SNAP_BIN_DIR/snapctl";
export PATH="$PATH:$SNAP_BIN_DIR";

# define the plugins
export METRICS=$METRIC_PLUGINS;

# define the update interval
export INTERVAL=$SNAP_UPDATE_INTERVALL;



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

