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
#         FILE: 99-mikelangelo-hpc_stack.sh
#
#        USAGE: source 99-mikelangelo-hpc_stack.sh
#
#  DESCRIPTION: Provides vTorque's $PATH to the environment, so it can be found.
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Nico Struckmann, struckmann@hlrs.de
#      COMPANY: HLRS, University of Stuttgart
#      VERSION: 0.1
#      CREATED: Oct 12 2015
#     REVISION:
#
#    CHANGELOG
#
#=============================================================================

#
# set to vTorque's installation directory
#
VTORQUE_DIR="/opt/dev/vTorque/src";


###### DO NOT EDIT BELOW THIS LINE ########

#
# ensure wrapper is the first match in the PATH
#
export PATH="$VTORQUE_DIR:$PATH";

