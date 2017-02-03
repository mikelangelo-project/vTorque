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
ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source "$ABSOLUTE_PATH/iocm-common.sh";



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
