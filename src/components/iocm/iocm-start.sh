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
#         FILE: iocm-start.sh
#
#        USAGE: iocm-start.sh
#
#  DESCRIPTION: Startup logic for IOcm, needs to be executed as root.
#      OPTIONS: ---
# REQUIREMENTS: IOcm must be installed.
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
IOCM_ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source "$IOCM_ABSOLUTE_PATH/iocm-common.sh";



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
  minCores=$(sed -n '1{p;q;}' "$FLAG_FILE_IOCM"); #grep first line
  maxCores=$(sed -n '2{p;q;}' "$FLAG_FILE_IOCM"); # grep second line
  logDebugMsg "IOCM minCores='$minCores' maxCores='$maxCores'";

  # determine total CPU count
  totalCores=$(grep -c ^processor /proc/cpuinfo);

  # generate config
  $VTORQUE_DIR/components/iocm/dynamic-io-manager/src/create_configuration_file.py \
    --config $IOCM_JSON_CONFIG \
    --min $minCores --max $maxCores \
    $totalCores $IOCM_INTERFACE_NAME;

  # allow user to read it (for debugging purposes)
  chown $USER_NAME:$USER_NAME "$IOCM_JSON_CONFIG";

  # log resulting file
  if [ $? -eq 0 ]; then
    logDebugMsg "IOCM JSON config file generated '$IOCM_JSON_CONFIG'.";
    logTraceMsg "Generated IOCM JSON config file\n-----\n$(cat $IOCM_JSON_CONFIG)\n----";
  else
    logWarnMsg "IOCM JSON config file generation failed.";
  fi
}


#---------------------------------------------------------
#
# Configures the min/max amount of IOcm cores
#
setCores() {

  if [ ! -f "$FLAG_FILE_IOCM" ]; then
    logErrorMsg "No flag file found for IOCM, cannot setup IOCM!";
  fi

  logInfoMsg "IOCM starting..";

  # debugging mode ?
  if $DEBUG; then
    logDebugMsg "IOCM log file: '$IOCM_LOG_FILE'.";
    su - $USER_NAME -c "touch '$IOCM_LOG_FILE'";
    {
      # call in debug mode as process (forground and all stdout/err printed)
      $IOCM_ABSOLUTE_PATH/dynamic-io-manager/src/start_io_manager.py \
        --process \
        --config $IOCM_JSON_CONFIG \
          &>> $IOCM_LOG_FILE;
    } & : ;
    logDebugMsg "IOCM started as process.";
    return 0;
  fi

  # start iocm as background process
  $IOCM_ABSOLUTE_PATH/dynamic-io-manager/src/start_io_manager.py \
    --config $IOCM_JSON_CONFIG &>> $IOCM_LOG_FILE;
  return $?;
}


#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

logInfoMsg "Setting up I/O Core Manager (IOCM)..";

# generate config based on template
generateConfig;

# configure the IOcm cores
setCores;

# success ?
res=$?;
if [ $res -eq 0 ]; then
  logInfoMsg "Setting up IOCM done.";
else
  logWarnMsg "Setting up IOCM failed.";
fi

# pass on return code
exit $res;
