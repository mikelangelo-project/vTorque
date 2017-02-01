#!/bin/bash
#
# filename: /usr/local/fixKernelOptions-iocm.sh
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
  $ABSOLUTE_PATH/dynamic-io-manager/src/start_io_manager.py -p -c $ABSOLUTE_PATH/iocm-conf.json --min 0 --max 2;
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
