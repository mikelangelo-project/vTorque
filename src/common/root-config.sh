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

#
# Contains all configuration options for the HPC integration of VMs.
#
# NOTE: source this file BEFORE the config.sh
#

##############################################################################
#                                                                            #
# IMPORTANT NOTE:                                                            #
# ===============                                                            #
#  $RUID and $PBS_JOBID is expected to be set.                               #
#                                                                            #
##############################################################################
#
set -o nounset;

# passed on as parameters ?
if [ $# -gt 0 ]; then
  if [ $# -lt 2 ]; then
    echo "For debugging use $(basename ${BASH_SOURCE[0]}) <jobID> <username>"; # relevant if not executed by Torque, but manually
    exit 1; # abort
  fi
  PBS_JOBID=$1;
  USERNAME=$2;
  export USERNAME=$USERNAME;
fi

#
# set the job id (it's in the env when debugging with the help of an
# interactive job, but given as arg when run by Torque or manually
#
if [ ! -z ${PBS_JOBID-} ] && [ -n "$PBS_JOBID" ]; then
  JOBID=$PBS_JOBID;
elif [ ! -z ${JOBID-} ] && [ -n "$JOBID" ]; then
  PBS_JOBID=$JOBID;
else #PBS_JOBID and JOBID is empty/not set
  echo "PBS_JOBID is not set! usage: $(basename ${BASH_SOURCE[0]}) <jobID>"; # relevant if not executed by Torque, but manually
  exit 1; # abort
fi

if [ "$PBS_JOBID" != "$JOBID" ]; then
  # JOBID is set and differs from PBS_JOBID - should not happen, abort
  echo "ERROR: JOBID and PBS_JOBID differ!";
  exit 1;
fi
export PBS_JOBID=$PBS_JOBID;

#
# mapping of RUID-2JOBID, we create a symlink as soon as we have a jobID
#
RUID=$JOBID;

#
# Set the user
#
if [ -z ${USERNAME-} ]; then
  if [ -z ${USER-} ]; then
    echo "USER or USERNAME needs to be set in environment or passed on!";
    exit 1;
  else
    USERNAME=$USER;
  fi
fi

#
# set the job dir based on passwd's user home
#
VM_JOB_DIR_PREFIX="$(grep $USERNAME /etc/passwd | cut -d':' -f6)/.vtorque";

#
# as last source the config.sh
#
ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source $ABSOLUTE_PATH/config.sh;
source $ABSOLUTE_PATH/const.sh;
