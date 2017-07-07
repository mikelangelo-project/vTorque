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



#============================================================================#
#                                                                            #
#                               FUNCTIONS                                    #
#                                                                            #
#============================================================================#


#---------------------------------------------------------
#
# prints out available targets
#
usage() {
  echo "usage: $0 [--prefix|-c <PREFIX>] [--uninstall|-u]";
}


#---------------------------------------------------------
#
#
#
setupServer() {
  cd $BASE_DIR;
  cp -r ./lib $DEST_DIR/;
  cp -r ./src/* $DEST_DIR/;
  cp -r ./doc $DEST_DIR/;
  cp -r ./test $DEST_DIR/;
  cp ./contrib/97-pbs_server_env.sh /etc/profile.d/;
  cp ./contrib/99-mikelangelo-hpc_stack.sh /etc/profile.d/;
  cp ./LICENSE $DEST_DIR/;
  cp ./NOTICE $DEST_DIR/;
  cp ./README* $DEST_DIR/;
  _setPermissions;
}


#---------------------------------------------------------
#
#
#
cleanupServer() {
  rm -Rf $DEST_DIR;
  rm -f /etc/profile.d/97-pbs_server_env.sh;
  rm -f /etc/profile.d/99-mikelangelo-hpc_stack.sh;
}


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
}


#---------------------------------------------------------
#
# rename current/orig scripts in place
#
setupMoms() {
  cd $BASE_DIR;
  cp ./contrib/98-pbs_mom_env.sh /etc/profile.d/;
  cp ./contrib/99-mikelangelo-hpc_stack.sh /etc/profile.d/;
  rename -v 's/(.*)\$$$\/\$$$\1.orig/' /var/spool/torque/mom_priv/{pro,epi}logue{.user,}{.parallel,.precancel,};
  ln -sf $DEST_DIR/src/scripts/{prologue{,.parallel},epilogue{,.parallel,.precancel}} /var/spool/torque/mom_priv/;
  echo "Done";
}


#---------------------------------------------------------
#
# put original scripts back in place
#
cleanupMoms() {
  rm -f /etc/profile.d/98-pbs_mom_env.sh;
  rm -f /etc/profile.d/99-mikelangelo-hpc_stack.sh;
  rm -f /var/spool/torque/mom_priv/{pro,epi}logue{.user,}{.parallel,.precancel,};
  rename 's/\.orig\$$$\//' /var/spool/torque/mom_priv/{pro,epi}logue{.user,}{.parallel,.precancel,}.orig;
  echo "Done";
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
DEST_DIR="$PREFIX/vTorque";


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
