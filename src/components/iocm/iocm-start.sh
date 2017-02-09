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
# Generate IOCM config
#
generateConfig() {
  logDebugMsg "Generating IOCM config for node '$LOCALHOST'..";
  
  # determine min/max core count
  minCores=$(sed -n '1{p;q;}' "$FLAG_FILE_DIR/.iocm"); #grep first line
  maxCores=$(sed -n '2{p;q;}' "$FLAG_FILE_DIR/.iocm"); # grep second line
  logTraceMsg "IOCM minCores='$minCores' maxCores='$maxCores'";
  
  # determine total CPU count
  totalCores=$(grep -c ^processor /proc/cpuinfo);
  
  # generate config
  $SCRIPT_BASE_DIR/components/iocm/dynamic-io-manager/src/create_configuration_file.py \
    --config $IOCM_JSON_CONFIG \
    --min $minCores --max $maxCores \
    $totalCores $IOCM_INTERFACE_NAME;
  
  # log resulting file
  logDebugMsg "IOCM JSON config file generated '$IOCM_JSON_CONFIG'.";
  logTraceMsg "Generated IOCM JSON config file\n-----\n$(cat $IOCM_JSON_CONFIG)\n----";
}


#---------------------------------------------------------
#
# Configures the min/max amount of IOcm cores
#
setCores() {
  if [ ! -f "$FLAG_FILE_DIR/.iocm" ]; then
    logErrorMsg "No flag file found for IOCM, cannot setup IOCM!";
  fi
  $ABSOLUTE_PATH/dynamic-io-manager/src/start_io_manager.py -p -c $IOCM_JSON_CONFIG --min $minCores --max $maxCores;
}


#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

# generate config based on template
generateConfig;

# configure the IOcm cores
setCores;

# pass on return code
exit $?;
