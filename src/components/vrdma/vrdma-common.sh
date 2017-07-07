#!/bin/bash
#
# Copyright 2016-2017 HLRS, University of Stuttgart
# Copyright 2016 Huawei Technologies Co., Ltd.
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
#         FILE: vrdma-common.sh
#
#        USAGE: source vrdma-common.sh
#
#  DESCRIPTION: Constants, configuration and functions for the vRDMA
#               integration.
#      OPTIONS: ---
# REQUIREMENTS: vRDMA support must be installed, in both host and guest.
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Nico Struckmann, struckmann@hlrs.de
#               Shiqing Fan, shiqing.fan@huawei.com
#      COMPANY: HLRS, University of Stuttgart
#               Huawei Technologies Co., Ltd.
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
source /etc/profile.d/99-mikelangelo-hpc_stack.sh;
source "$VTORQUE_DIR/common/const.sh";
source "$VTORQUE_DIR/common/root-config.sh";
source "$VTORQUE_DIR/common/root-functions.sh";


#
# Path to OVS (version should be at lease 2.4.0)
#
OVS_DIR="/opt/openVSwich";

#
# Path to libvirtd (version should be at lease 1.2.19)
#
LIBVIRT_DIR="/opt/libvirt/libvirt-1.2.19";

#
# Path to DPDK (version should be at lease 2.1.0)
#
DPDK_DIR="/opt/dpdk/dpdk-2.1.0";

#
# Path to QEMU (version should be at lease 2.2)
#
QEMU_DIR="/opt/qemu/qemu-2.3.0/";

#
# Name of bridge that is bound to the DPDK capable hardware
#
DPDK_BRIDGE_NAME="dpdk-bridge";

#
# bridge name that will be created by Open vSwitch
#
VRDMA_BRIDGE="vrdma-br";

#
# IB port in RoCE mode to be combined with Open vSwitch
# To bind multiple IB ports, please also update section "OVS port pairs"
#  IB0="dpdk0";
#  IB1=dpdk1
#
IB_PORT_PREFIX="dpdk";

#
# size of mem tables allocation for huge pages support in 2MB chunks
#
HUGE_TABLE_SIZE=4194304; # 4GB

#
# memory size to be attached to the interface
# (allocate memory on the same node as the InfinBand card is connected to, this will give better perforamnce)
#
SOCKET0_MEM=2048;
SOCKET1_MEM=0;

# on which CPU core the OVS daemon will run
# (be careful, wrong setting will make OVS not working correctly)
#PMD_CPU_MASK=0c0

#
# PCI address of the IB card | FIXME: determine automatically !!
#
IB_PCI_ADDR="0000:05:00.0";

#
# the DPDK target that has been built for vRDMA
#
RTE_TARGET="x86_64-ivshmem-linuxapp-gcc";

############################################################
# The following settings should reamin unmodified normally #
############################################################

#
# OVS related paths and files
#
OVS_SHARE_DIR="$OVS_DIR/share/openvswitch";
OVS_DATABASE="$OVS_DIR/etc/openvswitch/conf-$LOCALHOST.db";
OVS_SERVER_LOG="$OVS_DIR/var/log/openvswitch/ovs-server-$LOCALHOST.log";
OVS_DAEMON_LOG="$OVS_DIR/var/log/openvswitch/ovs-daemon-$LOCALHOST.log";
OVS_SERVER_PID_FILE="$OVS_DIR/var/log/openvswitch/ovs-server-$LOCALHOST.pid";
OVS_DAEMON_PID_FILE="$OVS_DIR/var/log/openvswitch/ovs-daemon-$LOCALHOST.pid";
OVS_DB_SCHEMA_VSWITCH="$OVS_SHARE_DIR/vswitch.ovsschema";

#
# NOTE: keep HOST_DB_SOCK in sync with the domain.xml fragment !
#
DB_SOCK_DIR="$OVS_DIR/var/run/openvswitch/";
HOST_DB_SOCK="$DB_SOCK_DIR/ovs-db-${LOCALHOST}-${JOBID}.sock";

#
# Libvirtd related paths and files
#
LIBVIRT_PID="$LIBVIRT_DIR/var/run/libvirtd-$LOCALHOST.pid";
LIBVIRT_ETC_DIR="$LIBVIRT_DIR/etc/libvirt";
LIBVIRT_CONFIG="$LIBVIRT_ETC_DIR/libvirtd-$LOCALHOST.conf";
LIBVIRT_RUN_DIR="$LIBVIRT_DIR/var/run/libvirt-$LOCALHOST";
LIBVIRT_URI="qemu+unix:///system?socket=$LIBVIRT_RUN_DIR/libvirt-sock";

#
# vRDMA network
#
VRDMA_NET="10.0.0.1/24";

#
# vRDAM bridge IP
#
VRDMA_BRIDGE_IP="10.0.0.1/24";

#
# ensure the correct binaries are found/used
#
export PATH="$LIBVIRT_DIR/bin:$LIBVIRT_DIR/sbin:$OVS_DIR/bin:$OVS_DIR/sbin:$QEMU_DIR/bin:$PATH";
export LD_LIBRARY_PATH="$LIBVIRT_DIR/lib:$OVS_DIR/lib:$QEMU_DIR/lib${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}";



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
checkVRDMAPreconditions() {

  if [ -z ${OVS_DIR-} ]; then
    logErrorMsg "Environment variable 'OVS_DIR' is not set !";
  elif [ ! -d $OVS_DIR ]; then
    logErrorMsg "Environment variable 'OVS_DIR=$OVS_DIR' is not pointing to an existing dir !";
  fi

  if [ -z ${OVS_SERVER_LOG-} ]; then
    logErrorMsg "Environment variable 'OVS_SERVER_LOG' is not set !";
  fi

  if [ -z ${OVS_DAEMON_LOG-} ]; then
    logErrorMsg "Environment variable 'OVS_DAEMON_LOG' is not set !";
  fi

  if [ -z ${OVS_SERVER_PID_FILE-} ]; then
    logErrorMsg "Environment variable 'OVS_SERVER_PID_FILE' is not set !";
  fi

  if [ -z ${OVS_DAEMON_PID_FILE-} ]; then
    logErrorMsg "Environment variable 'OVS_DAEMON_PID_FILE' is not set !";
  fi

  if [ -z ${HOST_DB_SOCK-} ]; then
    logErrorMsg "Environment variable 'HOST_DB_SOCK' is not set !";
  fi

  if [ -z ${LIBVIRT_RUN_DIR-} ]; then
    logErrorMsg "Environment variable 'LIBVIRT_RUN_DIR' is not set !";
  fi

  if [ -z ${VRDMA_BRIDGE-} ]; then
    logErrorMsg "Environment variable 'VRDMA_BRIDGE' is not set !";
  fi

  if [ -z ${VRDMA_NET-} ]; then
    logErrorMsg "Environment variable 'VRDMA_BRIDGE' is not set !";
  fi

  # check PATH variable
  if [ ! -n "$(echo $PATH | grep $LIBVIRT_DIR/bin | grep $LIBVIRT_DIR/sbin \
               | grep $OVS_DIR/bin | grep $OVS_DIR/sbin | grep $QEMU_DIR/bin)" ]; then
    logWarn "Environment variable 'PATH' is missing one of the requirements.";
    logError "One of these is missing:\n\t*LIBVIRT_DIR/bin\n\t*LIBVIRT_DIR/sbin \
\n\t*OVS_DIR/bin\n\t*OVS_DIR/sbin\n\t*QEMU_DIR/bin";
  fi
}


#---------------------------------------------------------
#
# Cleans up previously created / old files.
#
cleanupFiles() {

  # list of files to remove if present
  declare -a files=(\
                    "$OVS_SERVER_LOG" \
                    "$OVS_DAEMON_LOG" \
                    "$OVS_SERVER_PID_FILE" \
                    "$OVS_DAEMON_PID_FILE" \
                    "${VM_DB_SOCK_PREFIX-}*" \
                    );
  # logging
  logDebugMsg "Cleaning up files.";
  # cleanup
  for oldFile in ${files[@]}; do
    logTraceMsg "Removing (old) file '$oldFile' if exists.";
    [ -f "$oldFile" ] && rm $oldFile;
  done

}


#---------------------------------------------------------
#
# Prints the list of existing OVS DB sockets on STDOUT.
#
getSocketList() {
  if [ ! -d $(dirname $DB_SOCK_DIR) ]; then
    logErrorMsg "OVS DB sockets dir '$DB_SOCK_DIR' does not exist!";
  fi
  echo "$(ls ${DB_SOCK_DIR}*.sock)";
}


#---------------------------------------------------------
#
# Removes the vRDMA-bridge.
#
removeBridge() {
  # remove all ovs ports before killing the process, to avoid huge pages leaks
  logDebugMsg "Removing vRDMA bridge..";
  for dbSocket in $(getSocketList); do
    ovs-vsctl --db=unix:$dbSocket --no-wait del-br $VRDMA_BRIDGE;
    if [ $? -ne 0 ]; then
      logErrorMsg "Failed to remove vRDMA '$VRDMA_BRIDGE' bridge!";
    fi
  done
}

#---------------------------------------------------------
#
# Get IP of DPDK (vRDMA) bridge.
#
getBridgeIP() {
  echo "$(/sbin/ip route | grep $VRDMA_BRIDGE | tr -s ' ' | cut -d' ' -f9)";
}

