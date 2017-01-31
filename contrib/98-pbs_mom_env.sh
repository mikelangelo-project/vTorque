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

if [ -z ${TORQUE_HOME-} ]; then
  export TORQUE_HOME="/var/spool/torque";
fi
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/opt/torque/current/client/lib";
export PATH="/opt/torque/current/client/bin:/opt/torque/current/client/sbin:$PATH";
