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
#
#=============================================================================
#
#         FILE: setup.sh
#
#        USAGE: setup.sh <parameters>
#
#  DESCRIPTION: Un/Installer for vTorque layer.
#
#      OPTIONS: ---
# REQUIREMENTS: Working PBS Torque installation.
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: Nico Struckmann, struckmann@hlrs.de
#      COMPANY: HLRS, University of Stuttgart
#      VERSION: 0.1
#      CREATED: July 07th 2017
#     REVISION:
#
#    CHANGELOG
#
#=============================================================================

#============================================================================#
#                                                                            #
#                          SCRIPT CONFIGURATION                              #
#                              DO NOT MODIFY                                 #
#                                                                            #
#============================================================================#

#
# Base dir from where the files are copied.
#
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";

#
# Default action to carry out.
#
DEFAULT_ACTION="setup";

#
# Default prefix for the installation.
#
DEFAULT_PREFIX="/opt";

#
# User provided action to carry out.
# Default is '$DEFAULT_ACTION'.
#
ACTION="";

#
# User provided prefix for the installation.
# Default is '$DEFAULT_PREFIX'.
#
PREFIX="";

#
# Destination dir for the installation.
# Default is '$PREFIX/vTorque'
#
DEST_DIR="";

#
# vTorque's config file
#
VTORQUE_CONFIG_FILE="";


#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#

#---------------------------------------------------------
#
# set permissions for production
#
_setPermissions() {
  chown -R root:root $DEST_DIR;
  chmod -R 555 $DEST_DIR;
  chmod 444 $DEST_DIR/contrib/*;
  chmod 444 $DEST_DIR/doc/*.md;
  chmod 444 $DEST_DIR/src/common/*;
  chmod 500 $DEST_DIR/src/scripts/*;
  chmod 500 $DEST_DIR/src/scripts-vm/*;
  chmod 444 $DEST_DIR/src/templates/*;
  chmod 444 $DEST_DIR/src/templates-vm/*;
  echo "Permissions applied to installed files.";
}


#
# asks user for networking settings that are applied to VMs
#
_configureVMnetworking() {

  echo "Please provide network settings, applied to VMs.";

  echo -n "Domain: ";
  read DOMAIN;

  echo -n "Search-Domain: ";
  read SEARCH_DOMAIN;

  echo -n "Name server IP: ";
  read NAME_SERVER;

  echo -n "NFS 'server:/path' for \$HOME: ";
  read NFS_HOME;

  echo -n "NFS 'server:/path' for '/opt': ";
  read NFS_OPT;

  echo -n "NFS 'server:/path' for intermediate workspace: ";
  read VM_NFS_WS;

  echo -n "NTP server (1/2) IP: ";
  read NTP_SERVER_1;

  echo -n "NTP server (2/2) IP: ";
  read NTP_SERVER_2;

  sed -i -e "s,NAME_SERVER=.*,NAME_SERVER=\"$NAME_SERVER\";,g" $VTORQUE_CONFIG_FILE;
  sed -i -e "s,DOMAIN=.*,DOMAIN=\"$DOMAIN\";,g" $VTORQUE_CONFIG_FILE;
  sed -i -e "s,SEARCH_DOMAIN=.*,SEARCH_DOMAIN=\"$SEARCH_DOMAIN\";,g" $VTORQUE_CONFIG_FILE;
  sed -i -e "s,NTP_SERVER_1=.*,NTP_SERVER_1=\"$NTP_SERVER_1\";,g" $VTORQUE_CONFIG_FILE;
  sed -i -e "s,NTP_SERVER_2=.*,NTP_SERVER_2=\"$NTP_SERVER_1\";,g" $VTORQUE_CONFIG_FILE;
  sed -i -e "s,VM_NFS_HOME=.*,VM_NFS_HOME=\"$NFS_HOME\";,g" $VTORQUE_CONFIG_FILE;
  sed -i -e "s,VM_NFS_OPT=.*,VM_NFS_OPT=\"$NFS_OPT\";,g" $VTORQUE_CONFIG_FILE;
  sed -i -e "s,VM_NFS_WS=.*,VM_NFS_WS=\"$NFS_WS\";,g" $VTORQUE_CONFIG_FILE;

  echo "VM networking settings applied.";
}


#---------------------------------------------------------
#
# prints out available targets
#
usage() {
  echo "usage: $0 [--prefix|-p <PREFIX>] [--uninstall|-u]";
}


#---------------------------------------------------------
#
#
#
setupServer() {
  cd $BASE_DIR;
  # check if destination dir exists, if not create it
  if [ -e $DEST_DIR ]; then
    if [ ! -d $DEST_DIR ]; then
      echo "Destination dir '$DEST_DIR' is not a directory.";
      exit 1;
    else
      mkdir -p $DEST_DIR;
    fi
  fi
  #copy files to destination
  cp -r ./lib $DEST_DIR/;
  cp -r ./src/* $DEST_DIR/;
  cp -r ./doc $DEST_DIR/;
  cp -r ./test $DEST_DIR/;
  cp ./contrib/99-mikelangelo-hpc_stack.sh /etc/profile.d/;
  cp ./LICENSE $DEST_DIR/;
  cp ./NOTICE $DEST_DIR/;
  cp ./README* $DEST_DIR/;
  # fix relative paths in doc/*
  sed -i 's,../src/,../,g' $DEST_DIR/doc/*;
  # set PATH
  sed -i -e "s,VTORQUE_DIR=.*,VTORQUE_DIR=\"$DEST_DIR\";,g" /etc/profile.d/99-mikelangelo-hpc_stack.sh;
  # apply network settings
  _configureVMnetworking;
  # apply correct and secure permissions
  _setPermissions;
  echo "Setup server done.";
}


#---------------------------------------------------------
#
#
#
cleanupServer() {
  rm -Rf $DEST_DIR;
  rm -f /etc/profile.d/99-mikelangelo-hpc_stack.sh;
  echo "Server clean up done.";
}


#---------------------------------------------------------
#
# rename current/orig scripts in place
#
setupMoms() {
  pdsh -a "\
    cd $BASE_DIR;\
    cp ./contrib/99-mikelangelo-hpc_stack.sh /etc/profile.d/;\
    sed -i -e \"s,VTORQUE_DIR=.*,VTORQUE_DIR=$DEST_DIR,g\" /etc/profile.d/99-mikelangelo-hpc_stack.sh;\
    rename -v 's/(.*)\$$$\/\$$$\1.orig/' /var/spool/torque/mom_priv/{pro,epi}logue{.user,}{.parallel,.precancel,};\
  ln -sf $DEST_DIR/src/scripts/{prologue{,.parallel},epilogue{,.parallel,.precancel}} /var/spool/torque/mom_priv/;";
  echo "Mom setup done";
}


#---------------------------------------------------------
#
# put original scripts back in place
#
cleanupMoms() {
  pdsh -a "\
    rm -f /etc/profile.d/99-mikelangelo-hpc_stack.sh;\
    rm -f /var/spool/torque/mom_priv/{pro,epi}logue{.user,}{.parallel,.precancel,};\
    rename 's/\.orig\$$$\//' /var/spool/torque/mom_priv/{pro,epi}logue{.user,}{.parallel,.precancel,}.orig;";
  echo "Mom clean up done";
}




#============================================================================#
#                                                                            #
#                                 MAIN                                       #
#                                                                            #
#============================================================================#


# check if user has the required rights
if [ $(id -u) -ne 0 ]; then
  echo "Run as root.";
  exit 1;
fi

#
# parse arguments
#
while [[ $# -gt 1 ]]; do

  case $1 in

    --prefix|-p)
      PREFIX="$2";
      shift;
      ;;

    --uninstall|-u)
      ACTION="cleanup";
      shift;
      ;;

    *)
      usage;
      ;;

  esac
  shift;
done

# prefix provided ?
if [ -z ${PREFIX-} ]; then
  # no, use default
  PREFIX=$DEFAULT_PREFIX;
fi
DEST_DIR="$PREFIX/vtorque";
VTORQUE_CONFIG_FILE="$DEST_DIR/common/config.sh";


#
# what to do ?
#
case $ACTION in

  setup)
    # setup server
    setupServer;
    # setup moms
    setupMoms;
    ;;

  cleanup)
    # cleanup server
    cleanupServer;
    # cleanup moms
    cleanupNodes;
    ;;

  *)
    usage;
    ;;

esac

# print summary
echo "Setup done.";
