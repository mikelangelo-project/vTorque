#!/bin/bash

set -o nounset;

ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source "$ABSOLUTE_PATH/../../common/const.sh";
source "$ABSOLUTE_PATH/../../common/config.sh";
source "$ABSOLUTE_PATH/../../common/functions.sh";


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
checkIOcmPreconditions() {
  # check uname
  kernelVersion="$(uname -a)";
  if [[ $kernelVersion =~ ]]; then
    logDebugMsg "IOcm Kernel version: $kernelVersion";
  else
    logErrorMsg "No IOcm kernel available.";
  fi

}
