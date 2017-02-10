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
VRDMA_ABSOLUTE_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";
source $VRDMA_ABSOLUTE_PATH/vrdma-common.sh;

#
# amount of VMs that are associated with the current job (if any)
#
VMS_PER_HOST=$(getVMCountOnLocalhost);


#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#


#---------------------------------------------------------
#
# Sets up Huge Pages support by the help of 2MB chunks,
# in case the kernel doesn't support them directly.
#
setupHugePages() {

  logDebugMsg "Setting up hugepages..";

  # kernel cmd line parameters contain 'hugepages' ?
  if [ -n "$(cat /proc/cmdline | grep hugepages)" ]; then

    logDebugMsg "Kernel supports 'hugepages'.";

  else # Kernel does not support hugetables

    logDebugMsg "Kernel does not support 'hugepages'.";

    # ensure the mount-point is ready
    if [ -d "/dev/hugepages" ] \
        && [ "" != "$(mount | grep /dev/hugepages)" ]; then
      umount /dev/hugepages;
    else
      mkdir -p /dev/hugepages;
    fi
    logInfoMsg "No real hugetables support available! Allocating 2MB instead, be patient..";
    noOfChunks=$(($HUGE_TABLE_SIZE / 2));
    logDebugMsg "Using '$HUGE_TABLE_SIZE' with a size of 2 MB each => '$noOfChunks' chunks in total."; #FIXME: we need to reserve the memory

    # one for each computeNode, this will be used for attaching the InfiniBand port to the OVS bridge.
    for i in {0..1}; do
      echo $noOfChunks > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages;
      if [ $? -ne 0 ]; then
        logErrorMsg "Failed to set hugepages to size of '$HUGE_TABLE_SIZE' MB with '$noOfChunks' chunks of 2MB for 'node$i' !";
      fi
    done

    # mount fs link
    mount -t hugetlbfs none /dev/hugepages;
    if [ $? -ne 0 ]; then
      logErrorMsg "Failed to setup hugetables!";
    fi
  fi
}


#---------------------------------------------------------
#
# Starts a customized libvirtd for the current job.
#
setupLibvirtd() {

  # logging
  logDebugMsg "Setting up libvirtd, copying config template '$LIBVIRT_ETC_DIR/libvirtd.conf' to '$LIBVIRT_CONFIG'.";

  # ensure libvirtd is ready
  if [ -n "$(pidof libvirtd)" ]; then
    killall libvirtd;
  fi
  [ ! -d '$LIBVIRT_RUN_DIR' ] && mkdir -p $LIBVIRT_RUN_DIR;

  # generate a customized config file (based on the template) for libvert daemon with the correct connection socket
  cp "$LIBVIRT_ETC_DIR/libvirtd.conf" "$LIBVIRT_CONFIG";
  if [ $? -ne 0 ]; then
    logErrorMsg "Failed to copy libvirtd.conf to '$LIBVIRT_CONFIG' !";
  fi

  # replace the default socket with the correct one
  sed -i "s,#unix_sock_dir = \"\/var\/run\/libvirt\",unix_sock_dir = \"$LIBVIRT_RUN_DIR\",g" $LIBVIRT_CONFIG;
  if [ $? -ne 0 ]; then
    logErrorMsg "Preparing libvirtd's config file '$LIBVIRT_CONFIG' failed!";
  fi

  # start the libvirt daemon with the generated config file
  libvirtd -d -p $LIBVIRT_PID -f $LIBVIRT_CONFIG;
}


#---------------------------------------------------------
#
# Sets up the OSV DB with the vswitch schema.
#
setupOVSDB() {


  # ensure it is not running
  if [ -n "$(pidof ovsdb-server)" ]; then
    killall ovsdb-server;
    if [ $? -ne 0 ]; then
      logErrorMsg "Failed to kill the running 'ovsdb-server' !";
    fi

    startDate=$(date +%s);
    # wait
    while [ -n "$(pidof ovsdb-server)" ]; do
      isTimeoutReached $TIMEOUT $startDate;
      sleep 1;
    done
  fi
  if [ -n "$(pidof ovs-vswitchd)" ]; then
    killall ovs-vswitchd;
    if [ $? -ne 0 ]; then
      logErrorMsg "Failed to kill the running 'ovs-vswitchd' !";
    fi
    startDate=$(date +%s);
    # wait
    while [ -n "$(pidof ovs-vswitchd)" ]; do
      isTimeoutReached $TIMEOUT $startDate;
      sleep 1;
    done
  fi


  # remove lock if it is still there
  [ -f "${OVS_DATABASE}.~lock~" ] && rm -f ${OVS_DATABASE}.~lock~;

  # clean up DB
  logDebugMsg "Cleaning up DB if present.";
  [ -f "$OVS_DATABASE" ] && rm $OVS_DATABASE;

  # re-create DB
  logDebugMsg "(Re-)creating DB";
  ovsdb-tool create $OVS_DATABASE $OVS_DB_SCHEMA_VSWITCH;
  if [ $? -ne 0 ]; then
    logErrorMsg "Failed to create OVS DB '$OVS_DATABASE' from schema $OVS_DB_SCHEMA_VSWITCH";
  fi
}


#---------------------------------------------------------
#
# Start OSV services.
#
startOVSservices() {

  # start OVS server (without SSL for now)
  logDebugMsg "Staring OVS service with DB-socket '$HOST_DB_SOCK'.";
  ovsdb-server $OVS_DATABASE --remote=punix:$HOST_DB_SOCK \
             --remote=db:Open_vSwitch,Open_vSwitch,manager_options \
             --pidfile=$OVS_SERVER_PID_FILE --detach \
             --log-file=$OVS_SERVER_LOG;
  if [ $? -ne 0 ]; then
    logErrorMsg "Starting OVS server with DB-socket '$HOST_DB_SOCK' failed!";
  fi

  # initialize the OVS server, and create the main database socket
  logDebugMsg "Initializing OVS server (creating DB socket '$HOST_DB_SOCK').";
  ovs-vsctl --db=unix:$HOST_DB_SOCK --no-wait init;
  if [ $? -ne 0 ]; then
    logErrorMsg "Initialization of OVS server, using DB-socket '$HOST_DB_SOCK', failed!";
  fi

  # start ovs daemon for Mellanox
  # multiple pci devices can be added via "-w 0000:0x:00.0"
  logDebugMsg "Starting OVS daemon (for Mellanox).";
  ovs-vswitchd --dpdk -c 0x1 -n 4 -w $IB_PCI_ADDR --socket-mem $SOCKET0_MEM,$SOCKET1_MEM \
               -- unix:$HOST_DB_SOCK --pidfile=$OVS_DAEMON_PID_FILE --detach \
               --log-file=$OVS_DAEMON_LOG;
  if [ $? -ne 0 ]; then
    logErrorMsg "Starting OVS daemon (for Mellanox) failed! Check log file '$OVS_DAEMON_LOG'.";
  fi

  # check and remove the bridge if it is still running since last session
  if [ ! -S "$HOST_DB_SOCK" ]; then
    logErrorMsg "Failed to create the DB socket '$HOST_DB_SOCK' !";
  else
    if [ -n "$(ovs-vsctl --db=unix:$HOST_DB_SOCK show | grep 'Bridge $VRDMA_BRIDGE')" ]; then
      removeBridge;
    fi
  fi

  # add the virtual bridge
  logDebugMsg "Adding virtual bridge '$VRDMA_BRIDGE', using DB-socket '$HOST_DB_SOCK'.";
  ovs-vsctl --no-wait --db=unix:$HOST_DB_SOCK add-br $VRDMA_BRIDGE -- set bridge $VRDMA_BRIDGE datapath_type=netdev;
  if [ $? -ne 0 ]; then
    logErrorMsg "Adding virtual bridge '$VRDMA_BRIDGE', using DB-socket '$HOST_DB_SOCK', failed!";
  fi
}


#---------------------------------------------------------
#
# Unloads the OSV kernel module that interferes with DPDK,
# when using DPDK for the datapath.
#
unloadOSVkernelModule() {
  # as we use DPDK for the datapath, this kernel module has to be unloaded to avoid conflicts
  if [ -n "$(lsmod | grep openvswitch)" ]; then
    logDebugMsg "Unloading kernel module 'openvswitch'."
    rmmod openvswitch;
    if [ $? -ne 0 ]; then
      logErrorMsg "Unloading kernel module 'openvswitch' failed!";
    fi
  fi
}


#---------------------------------------------------------
#
# Sets up the OVS ports for host and all guests.
# One port for each is added to the vRDMA bridge.
#
setupOVSports() {

  ###################
  #  OVS port pairs #
  ###################

  ###############################
  #  port pair for port: $IB0  #
  #  vhostuser port names are,  #
  #    for example:             #
  #     node0-vrdma0-0          #
  #     node0-vrdma0-1          #
  ###############################

  ###############################
  #  port pair for port: $IB1  #
  #  vhostuser port names are,  #
  #    for example:             #
  #     node0-vrdma1-0          #
  #     node0-vrdma1-1          #
  ###############################

  # construct socket name
  dpdkPortNumber=0; # ID of the physical port. By default, one InfiniBand card has two ports, but only one port is required
  dpdkPortName="${IB_PORT_PREFIX}${dpdkPortNumber}"; # Port name should be the same as the physical RoCE port name

  # port 1 / DPDK
  logDebugMsg "Adding DPDK-port '$dpdkPortName' to vRDMA-bridge '$VRDMA_BRIDGE', using DB socket '$HOST_DB_SOCK' for host.";
  ovs-vsctl --db=unix:$HOST_DB_SOCK --no-wait \
                  add-port $VRDMA_BRIDGE $dpdkPortName \
                  -- set Interface $dpdkPortName type=dpdk;
  if [ $? -ne 0 ]; then
    logErrorMsg "Adding DPDK-port '$dpdkPortName' to vRDMA-bridge '$VRDMA_BRIDGE', using DB socket '$HOST_DB_SOCK' failed!";
  fi

  # for each VM create a port and add it to the vRDMA bridge
  vmNo=1;
  while [ $vmNo -le $VMS_PER_HOST ]; do

    # construct db-socket name
    dbSocket="${VM_DB_SOCK_PREFIX}${vmNo}-${JOBID}.sock";
    logDebugMsg "DB socket name for VM '$vmNo/$VMS_PER_HOST' constructed: $dbSocket";

    # port 2 / the VM
    portName="${LOCALHOST}-${vmNo}-${PBS_JOBID}";
    logDebugMsg "Port name for VM '$vmNo/$VMS_PER_HOST' constructed: $portName";

    ovs-vsctl --db=unix:$HOST_DB_SOCK --no-wait \
                    add-port $VRDMA_BRIDGE $portName \
                    -- set Interface $portName type=dpdkvhostuser;
    if [ $? -ne 0 ]; then
      logErrorMsg "Failed to bind VM's '$vmNo/$VMS_PER_HOST' port '$portName' to bridge '$VRDMA_BRIDGE', using DB socket '$dbSocket' !";
    fi

    # count VM
    vmNo=$((vmNo + 1));
  done

  # bring link up
  logDebugMsg "Activating link '$dpdkPortName'.";
  ip link set $dpdkPortName up \
         && ip link set $dpdkPortName promisc on;
  if [ $? -ne 0 ]; then
    logErrorMsg "Failed to active link '$dpdkPortName'";
  fi
}


#---------------------------------------------------------
#
# Setup CPU binding
# At moment, OVS daemon is assigned to CPU core 0, only one core is needed
#
setupCPUbinding() {

  ###############
  # CPU binding #
  ###############
  # wrongly running this command will cause the network not working correctly
  #mike-ovs-vsctl set Open_vSwitch . other_config:pmd-cpu-mask=$PMD_CPU_MASK

  # if cpus are not isolated, the last command won't work, use following command instead.
  #taskset -acp 4 `pidof ovs-vswitchd`

  #TODO impl
  echo -n "setupCPUbinding not implemented";
}


#---------------------------------------------------------
#
# Activates the vRDMA bridge.
#
activateBridge() {

  # activate vRDMA bridge
  logDebugMsg "Activating vRDMA bridge '$VRDMA_BRIDGE'.";
  ip link set $VRDMA_BRIDGE up;
  if [ $? -ne 0 ]; then
    logErrorMsg "Failed to active the vRDMA bridge '$VRDMA_BRIDGE'!";
  fi

  # configure vRDMA bridge networking
  ip addr add $VRDMA_NET dev $VRDMA_BRIDGE;
  if [ $? -ne 0 ]; then
    logErrorMsg "Failed to configure the network '$VRDMA_NET' on vRDMA bridge '$VRDMA_BRIDGE'!";
  fi

  # give it a moment to come up
  startDate=$(date +%s);
  while [ ! -n "$(ip a | grep '$VRDMA_NET')" ]; do
    logDebugMsg "Waiting for net-assignment '$VRDMA_NET' to bridge '$VRDMA_BRIDGE' ..";
    isTimeoutReached 10 $startDate;
    sleep 1;
  done
}


#---------------------------------------------------------
#
# Starts an DHCP server for the vRDMA-bridge.
#
startlocalDHCPserver() {

  # ensure the DHCP server is not running, yet
  if [ -n "$(ps aux | grep dhcpd | grep -v grep)" ]; then
    stopService "isc-dhcp-server";
  fi

  # start the DHCP service
  logDebugMsg "Starting local DHCP server for vRDMA bridge '$VRDMA_BRIDGE' ..";
  startService "isc-dhcp-server";

  # wait until it is running
  while [ ! -n "$(ps aux | grep dhcpd | grep -v grep)" ]; do
    logDebugMsg "Waiting for isc-dhcp-server (dhcpd)..";
    sleep 1;
  done

  # remove ip from bridge (if there is alread a valid IP on the bridge, the DHCP will not assign for it again)
  logDebugMsg "Remove IP '$VRDMA_BRIDGE_IP' from vRDMA bridge '$VRDMA_BRIDGE'.";
  ip addr del $VRDMA_BRIDGE_IP dev $VRDMA_BRIDGE;
  if [ $? -ne 0 ]; then
    logErrorMsg "Failed to remove IP '$VRDMA_BRIDGE_IP' from vRDMA bridge '$VRDMA_BRIDGE' !";
  fi

  # wait until IP is gone
  while [ ! -n "$(ip a | grep '$BRIDGE_IP')" ]; do
    logDebugMsg "Waiting for IP '$VRDMA_BRIDGE_IP' assigned to bridge '$VRDMA_BRIDGE' to disappear..";
    sleep 1;
  done

  # ensure dhclient is not running
  if [ -n "$(ps aux | grep dhclient | grep -v grep)" ]; then
    killall dhclient;
  fi

  # start a dhclient for the bridge, so the DHCP server will assign an availabel IP to the bridge
  logDebugMsg "Enabling 'dhclient' for vRDMA bridge '$VRDMA_BRIDGE'.";
  dhclient $VRDMA_BRIDGE;
  if [ $? -ne 0 ]; then
    logErrorMsg "Failed to enable 'dhclient' for vRDMA bridge '$VRDMA_BRIDGE'.";
  fi
}


#---------------------------------------------------------
#
# vRDMA component's abort logic when a job is canceled while this script runs.
# Returns error/success code for the cleanup.
#
_abort() {
  $VRDMA_ABSOLUTE_PATH/vrdma-stop.sh;
  return $?;
}

#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#

logInfoMsg "Setting up vRDMA..";

# ensure everything is known / in place
checkVRDMAPreconditions;

# clean up old / previously created files
cleanupFiles;

# setup huge pages
setupHugePages;

# setup libvirt daemon
setupLibvirtd;

# setup OVS main database socket
setupOVSDB;

# unload the OVS kernel module, will be reloaded during startOVSservices
unloadOSVkernelModule;

# start OVS services
startOVSservices;

# set up OVS ports on vRDMA bridge
setupOVSports;

# add more properties to the bridge
activateBridge;

#setupCPUbinding;

# start DHCP
startlocalDHCPserver;
res=$?;

logInfoMsg "Setting up vRDMA done.";

# pass on return code
exit $res;
