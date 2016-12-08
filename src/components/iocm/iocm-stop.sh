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
  $ABSOLUTE_PATH/static-iomanager/set_iocores.py -1;
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