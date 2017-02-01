#!/bin/bash
#
#


ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source "$ABSOLUTE_PATH/../common.sh";


#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#

#---------------------------------------------------------
#
# Releases the min/max amount of cores bound to IOcm.
#
unsetCores() {
  logDebugMsg "Releasing iocm cores..";
  $ABSOLUTE_PATH/dynamic-io-manager/src/stop_io_manager.py;
}

#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

# release cores managed by IOcm
unsetCores;

# pass on return code
exit $?;
