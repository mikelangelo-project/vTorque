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
# Configures the min/max amount of IOcm cores
#
setCores() {
  echo "TODO impl iocm core set cmd dynamically";
  $ABSOLUTE_PATH/static-iomanager/set_iocores.py 0-2 3-7;
}


#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

# configure the IOcm cores
setCores;

# pass on return code
exit $?;