# vTorque Administrator Manual

## Introduction

The **MIKELANGELO HPC Infrastructure** has been designed to introduce the **benefits of virtualization into the domain of high performance computing (HPC)**. These benefits comprise besides abstraction of the actual execution environment, providing portability and thus enabling application packaging, flexibility and fault-tolerance for the application execution, e.g. live migration away from degrading hardware or suspend and resume capabilities.
MIKELANGELO also improves the **I/O performance of virtual environments** crucial for the use in HPC infrastructures.

The aim of vTorque is, to extend [Torque Resource Manager](http://www.adaptivecomputing.com/products/open-source/torque/) with capabilities for the management of virtual guests. vTorque enables Torque to deploy and execute job scripts in virtual machines, transparently to the user.

vTorque consists of a set of bash scripts, several templates and new command line tools. It is independent of a specific version of Torque, thanks to its non-invasive nature.


## Table of contents

* [Directory Structure](#directory-structure)
* [Requirements](#requirements)
  * [HPC Infrastructure](hpc-infrastructure)
  * [Guest Images](guest-images)
* [How To Install](#how-to-install)
  * [Automatic Installation](automatic-installation)
  * [Manual Installation](manual-installation)
    * [Setup Server](setup-server)
    * [Setup Compute Nodes](setup-compute-nodes)
    * [Configure Environment](configure-environment)
* [Configuration](#configuration)
  * [Cluster](#cluster)
  * [Timeouts](#timeouts)
  * [Networking for VMs](#networking-for-vms)
  * [Default packages for VMs](#default-packages-for-vms)
  * [VM Defaults for JobSubmission](#vm-defaults-for-jobsubmission)
  * [Debugging](#debugging)
  * [Logging](#logging)
  * [IOcm](#iocm)
  * [vRDMA](#vrdma)
  * [Snap Telemetry](#snap-telemetry)
* [Security Considerations](#security-considerations)
  * [Authorized Images](#authorized-images)
  * [Automatic Security Updates for Guests](#automatic-security-updates-for-guests)
  * [Hypervisor hardening](#hypervisor-hardening)
* [Acknowledgment](#acknowledgment)



## Requirements

There are requirements for the infrastructure, as well as for the guest OS.


### HPC Infrastructure

An HPC infrastructure must cover the following requirements, besides a working PBS/Torque installation.

* Required packages on compute nodes
```
coreutils
net-tools
openssh-client
cloud-utils
bash (>= v4.0)
qemu-kvm
libvirt-bin
numad (if automatic vCPU pinning is desired)
```
* disabled SSH known hosts file (VM ssh server keys are generated during boot)
* command `arp -an` is executable by users (used to determine IP of VMs)

Also folders on a shared file-system are needed for
  * the image pool dir `VM_IMAGE_DIR`
  * user homes `VM_NFS_HOME`
  * a fast workspace for intermediate data `VM_NFS_WS`
  * cluster wide software installations `VM_NFS_OPT`


### Guest Images

Supported guest OS families are: Debian, RedHat and OSv.  
Guest images are required to have:
* package `cloud-init` installed
* cloud-init data-source `no-cloud` is enabled
* workspace directory for intermediate data is `/workspace`
* user homes at the default location `/home`
* `/opt` cannot be used, but `/opt-vm` instead since cluster's `/opt` is mounted

Further details about guest images, their requirements and how to package applications can be found in [Guest Images](guest-images.md) documentation.


## Directory Structure

The source code repository's directory structure is as follows.

```
vTorque
├── contrib             Provides global vTorque environment variables.
├── doc                 Manuals
├── lib                 Dependent libraries.
│   ├── log4bsh         Logging facility.
│   └── osv             Converts a metadata file to an image file, OSv only.
└── src                 Contains all wrapper scripts and templates.
    ├── common          Configuration files and commonly used basic functionality.
    ├── components      Integration scripts for MIKELANGELO components.
    │   ├── iocm        IOcm (part of sKVM)
    │   ├── snap        Snap-Telemetry (monitoring)
    │   └── vrdma       vRDMA (part of sKVM)
    ├── scripts         Root user scripts, wrappers for Torque's root pro/epilogue sequences.
    ├── scripts-vm      Root user scripts, provides pro/epilogue sequences inside standard Linux guests.
    ├── templates       User level wrapper scripts, for VM preparation and job deployment.
    └── templates-vm    All templates related to virtual guests.
```

During installation all files and folders located under `src/` are placed at the main level.
```
vtorque
├── common          Configuration files and commonly used basic functionality.
├── components      Integration scripts for MIKELANGELO components.
│   ├── iocm        IOcm (part of sKVM)
│   ├── snap        Snap-Telemetry (monitoring)
│   └── vrdma       vRDMA (part of sKVM)
├── doc                 Manuals
├── lib                 Dependent libraries.
│   ├── log4bsh         Logging facility.
│   └── osv             Converts a metadata file to an image file, OSv only.
├── scripts         Root user scripts, wrappers for Torque's root pro/epilogue sequences.
├── scripts-vm      Root user scripts, provides pro/epilogue sequences inside standard Linux guests.
├── templates       User level wrapper scripts, for VM preparation and job deployment.
└── templates-vm    All templates related to virtual guests.
```


## How To Install

You can either run the provided setup script or install all files manually as described in the second part.
Note please, the installation requires root user rights, user space is not sufficient as vTorque relies on wrappers for Torque's root prologue and epilogue scripts.

To install other components of the MIKELANGELO HPC software stack, please refer to their documentation:
* [IOcm](https://github.com/mikelangelo-project/dynamic-io-manager)
* [vRDMA (prototype 1)](https://www.mikelangelo-project.eu/wp-content/uploads/2016/06/MIKELANGELO-WP4.1-Huawei-DE_v2.0.pdf)
* [Snap-Telemetry](http://snap-telemetry.io/)

To enable the full MIKELANGELO HPC software stack, also mind the corresponding configuration parameters for [IOcm](#iocm), [vRDMA](#vrdma) and [Snap Telemetry](#snap-telemetry). To ease the first steps with vTorque these disabled by default.

### Automatic Installation

Automatic installation for the compute node part depends on [`pdsh`](https://linux.die.net/man/1/pdsh) and that vTorque src directory resides on a shared file-system, reachable from compute nodes under the same path. If this is not the case, manual installation may be your preferred way to proceed.

The setup script [setup.sh](../setup.sh) can be used to install and uninstall vTorque.
```sh
setup.sh [-p|--prefix <prefix>] [-u|--uninstall]
```

The default prefix for the installation is '/opt'.

To install vTorque just run command
```sh
./setup.sh
```

To install vTorque in a custom location, make use of argument '-p|--prefix'
```sh
./setup.sh -p /custom/path
```

To remove vTorque run command (and mind the prefix if you have not installed in in the default location).
```
./setup.sh -u [-p /custom/path]
```


### Manual Installation

There are two possibilities for the manual installation, first is to clone the git repository and create symlinks or make use of bind mounts. Second one is equal to executing the provided `setup.sh`, copying files to their destination directory. If you want to use a cloned repository directly, replace below command `cp -r` by command `ln -s` to create symlinks.


#### Setup Frontends

* define the installation directory
```sh
  DEST_DIR="/opt/vtorque";
```

* copy all files from the source code directory to the destination directory
```sh
  cp -r ./lib $DEST_DIR/;
  cp -r ./src/* $DEST_DIR/;
  cp -r ./doc $DEST_DIR/;
  cp -r ./test $DEST_DIR/;
  cp ./contrib/97-pbs_server_env.sh /etc/profile.d/;
  cp ./contrib/99-mikelangelo-hpc_stack.sh /etc/profile.d/;
  cp ./LICENSE $DEST_DIR/;
  cp ./NOTICE $DEST_DIR/;
  cp ./README* $DEST_DIR/;
```

* set permissions on server
```sh
  chown -R root:root $DEST_DIR;
  chmod -R 555 $DEST_DIR;
  chmod 444 $DEST_DIR/contrib/*;
  chmod 444 $DEST_DIR/doc/*.md;
  chmod 444 $DEST_DIR/src/common/*;
  chmod 500 $DEST_DIR/src/scripts/*;
  chmod 500 $DEST_DIR/src/scripts-vm/*;
  chmod 444 $DEST_DIR/src/templates/*;
  chmod 444 $DEST_DIR/src/templates-vm/*;
```

#### Setup Compute Nodes

* copy files
```sh
  cp ./contrib/98-pbs_mom_env.sh /etc/profile.d/;
  cp ./contrib/99-mikelangelo-hpc_stack.sh /etc/profile.d/;
```

* rename original root prologue/epilogue scripts to *.orig
```sh
  rename -v 's/(.*)\$$$\/\$$$\1.orig/' /var/spool/torque/mom_priv/{pro,epi}logue{.user,}{.parallel,.precancel,};
```

* create symlinks for vTorque's pro/epilogue wrapper scripts to replace Torque's
```sh
  ln -sf $DEST_DIR/src/scripts/{prologue{,.parallel},epilogue{,.parallel,.precancel}} /var/spool/torque/mom_priv/;
```

#### Configure Environment ####

Last step is vTorque's configuration.
At first edit the profile, in file `99-mikelangelo-hpc_stack.sh`, set `VTORQUE_DIR` to vTorque's installation directory.

Next, take care of networking for VM, see [Networking for VMs](#networking-for-vms)


## Configuration

vTorque has several configuration options available. These can be used to control vTorque's behavior and for fine-tuning.
In the tables below is the complete list of configuration options described, including (proposed) default values.


### Cluster

| Configuration Parameter       | Default Value               | Description            |
| :---                          | :---                        | :---                   |
| `DISABLED_HOSTS_LIST`      | n/a                         | Regex for hosts disabled for VM job submission. |
| `REGEX_FE`                   | `*`                        | Regex for frontends, required if paths on nodes and frontend differ. |
| `TORQUE_HOME`               | `/var/spool/torque`       | Torque's Home directory. |
| `PBS_QSUB_ON_FE`            | `/usr/bin/qsub`           | Path to Torque's qsub on frontends. |
| `PBS_QSUB_ON_NODES`         | `/usr/bin/qsub`           | Path to Torque's qsub on compute nodes. |
| `VM_IMG_DIR`                 | `/opt/vm-images`          | Directory for authorized images. |
| `WS_DIR`                     | `/workspace/.vtorque`     | Fast shared file-system, used by applications for intermediate data. |
| `RAMDISK_DIR`                | `/ramdisk`                 | Path to RAMDISK where images are copied to if no shared fs is used for images. |
| `VM_NFS_HOME`                | n/a                         | NFS export for VM's `/home`, mounted from the cluster. |
| `VM_NFS_WS`                  | n/a                         | NFS export for VM's `/workspace`, mounted from the cluster. |
| `VM_NFS_OPT`                 | n/a                         | NFS export for VM's `/opt`, mounted from the cluster. |
| `ARP_BIN`                    | `/usr/sbin/arp`            | Absolute path to `arp` command. |
| `MAC_PREFIX`                 | `52:54:00 `                | Prefix for all VM's MAC addresses. |
| `HOST_OS_CORE_COUNT`        | `1`                         | Amount of cores reserved for the host OS. |
| `HOST_OS_RAM_MB`            | `2048`                      | Amount of RAM in MB reserved for the host OS. |
| `PBS_EXCLUSIVE_NODE_ALLOC` | `true`                      | Allocate nodes exclusively for an user, needed if Torque runs without meta-scheduler like Moab. |
| `KILL_USER_PROCESSES_AFTER_JOB` | `true`                 | Kills all user processes during the epilogue{.parallel}. |

Hint:  
Do not enable `KILL_USER_PROCESSES_AFTER_JOB` if your nodes are NOT allocated exclusively or you are making use of NUMA domains.

### Timeouts

| Configuration Parameter        | Default Value               | Description            |
| :---                           | :---                        | :---                   |
| `SSH_TIMEOUT`                | `5`                         | Timeout for SSH connections in seconds. |
| `TIMEOUT`                     | `120`                       | Timeout for processes during prologue in seconds. |
| `PROLOGUE_TIMEOUT`           | `600`                       | Timeout for root user prologue. MUST be lower that Torque's `$prologalarm`. |


### Networking for VMs

| Configuration Parameter        | Default Value               | Description            |
| :---                           | :---                        | :---                   |
| `CUSTOM_IP_MAPPING`          | `false`                    | Use a custom script instead of an DHCP server to determine VM IPs. |
| `IP_TO_MAC_SCRIPT`           | n/a                         | Executable that returns an IP and accepts as args: $1->nodeHostname, $2->vmsPerHost, $3->vmNumberOnHost) |
| `DOMAIN`                      | n/a                         | Your domain. |
| `NAME_SERVER`                | n/a                         | Your name server. |
| `SEARCH_DOMAIN`              | n/a                         | Your search domain. |
| `NTP_SERVER_1`               | n/a                         | Your first NTP server. |
| `NTP_SERVER_2`               | n/a                         | Your second NTP server. |

### Default packages for VMs

| Configuration Parameter        | Default Value               | Description            |
| :---                           | :---                        | :---                   |
| `SW_PACKAGES_DEBIAN`        | `('nfs-common' 'libnfs1' 'openmpi-bin' 'libopenmpi-dev' 'libmetis5' 'libmetis-dev' '9mount')` | Minimum required packages to be installed if using a plain cloud-image as is. |
| `SW_PACKAGES_REDHAT`        | `('nfs-common' 'libnfs1' 'nfs-utils' 'openmpi' 'openmpi-devel' 'metis' 'metis-devel' 'nfs-ganesha-mount-9P')` | Minimum required packages to be installed if using a plain cloud-image as is. |


### VM Defaults for JobSubmission

For all [vsub](user.md#vsub-arguments) command line options, defaults can be defined by administrators. These default options are put in place when the user does not provide them at submission time. The table below describes all default configuration options available.

| Configuration Parameter        | Default Value               | Description            |
| :---                           | :---                        | :---                   |
| `FILESYSTEM_TYPE_DEFAULT`   | `FILESYSTEM_TYPE_SFS`    | Default file system type for VM images, either ram disk (FILESYSTEM_TYPE_RD='ramdisk') or shared fs (FILESYSTEM_TYPE_SFS='sharedfs'). |
| `IMG_DEFAULT`                | n/a                         | Default image to use if user doesn't request a specific one. |
| `DISTRO_DEFAULT`             | n/a                         | MUST match the default image's distro, i.e. Debian, Ubuntu, REdHat, CentOS, OSv. |
| `ARCH_DEFAULT`               | `x86_64`                   | Default CPU architecture. |
| `VCPUS_DEFAULT`              | `7`                        | Amount of VCPUs to assign to each guest. Mind also `HOST_OS_CORE_COUNT`, `IOCM_MIN_CORES_DEFAULT`, `IOCM_MAX_CORES_DEFAULT`. |
| `VCPU_PINNING_DEFAULT`      | `true`                     | Indicates whether to enable vCPU pinning. |
| `RAM_DEFAULT`                | n/a                         | Default RAM in MB per VM, mind `HOST_OS_RAM_MB`. |
| `VMS_PER_NODE_DEFAULT`      | `1`                        | Default count of VMs per node, in case of NUMA domains (not managed by Torque) higher count than one may be beneficial. |
| `DISK_DEFAULT`               | n/a                         | Persistent, optional disk mounted at the first VM (rank 0). |
| `VRDMA_ENABLED_DEFAULT`     | `true`                     | Dis/enable vRDMA if parameter is not provided by user. |
| `IOCM_ENABLED_DEFAULT`      | `true`                     | Dis/enable IOcm if parameter is not provided by user. |
| `IOCM_MIN_CORES_DEFAULT`    | `1`                         | Minimum of cores reserved for IOcm, consider `HOST_OS_CORE_COUNT` and `VCPUS_DEFAULT`. |
| `IOCM_MAX_CORES_DEFAULT`    | `4`                         | Maximum of cores reserved for IOcm, consider `HOST_OS_CORE_COUNT` and `VCPUS_DEFAULT`. |


### Debugging

There are some options related to development and debugging of vTorque, DO NEVER enable these in a production environment.  
WARNING: These options have a serious impact on the cluster's security !

| Configuration Parameter        | Default Value               | Description            |
| :---                           | :---                        | :---                   |
| `ENABLE_DEV_MODE`            | `false`                    | Do not use in production, intended for vTorque development and debugging. Allows to override the global environment file by providing `$HOME/99-mikelangelo-hpc_stack.sh`. Useful if multiple developers want to work in parallel on one system. |
| `PARALLEL`                    | `true`                     | Execute prologue logic in parallel, sequential execution is useful for debugging, only. |
| `ALLOW_USER_IMAGES`          | `false`                    | Allow users to run their jobs with custom images. |
| `ABORT_ON_ERROR`             | `true`                     | Abort execution on error, 'true' is strongly recommended. |


### Logging

In the table below there are the relevant log4bsh configuration options for vTorque.  
For a full list, please refer to [log4bsh](https://github.com/mikelangelo-project/log4bsh)

| Configuration Parameter        | Default Value               | Description            |
| :---                           | :---                        | :---                   |
| `DEBUG_DEFAULT`              | `false`                    | Enabled debugging output per default, applied in case user does not set it. |
| `TRACE_DEFAULT`              | `false`                    | Enabled trace output per default, applied in case user does not set it. |
| `SHOW_LOG_DEFAULT`           | `false`                    | Display log on screen per default, applied in case user does not set it. |
| `PRINT_TO_STDOUT`            | `false`                    | Print all output to log file only, or also to STDOUT. |
| `LOG_ROTATE`                 | `true`                      | Use log rotate to keep log size limited |
| `LOG_FILE`                    | `$VM_JOB_DIR/debug.log`  | Log file to write to. |


### IOcm

| Configuration Parameter        | Default Value               | Description            |
| :---                           | :---                        | :---                   |
| `IOCM_ENABLED`               | `false`                    | Dis/enables IOcm. |
| `IOCM_MIN_CORES`             | `1`                         | Minimum of dedicated IOcm cores. |
| `IOCM_MAX_CORES`             | `12`                        | Absolute maximum that can be requested. |
| `IOCM_NODES`                 | `*`                         | Regex for hosts with IOcm support. |


### vRDMA

In addition to the listed vRDMA configuration options, there is also file [src/components/vrdma/vrdma-common.sh](../src/components/vrdma/vrdma-common.sh) where i.e. the memory chunk size can be configured.

| Configuration Parameter        | Default Value               | Description            |
| :---                           | :---                        | :---                   |
| `VRDMA_ENABLED`              | `false`                    | Dis/enables vRDMA. |
| `VRDMA_NODES`                | `*`                         | Regex for hosts with vRDMA support. |


### Snap Telemetry

| Configuration Parameter        | Default Value               | Description            |
| :---                           | :---                        | :---                   |
| `SNAP_MONITORING_ENABLED`   | `false`                    | Dis/enables Snap monitoring. |
| `SNAP_BIN_DIR`               | `/usr/local/bin/`         | Absolute path to the snap binaries on compute nodes. |
| `SNAP_TAG_FORMAT`            | `snapTask-[username]-[jobid]` | Format of task tags, `username` and `jobid` can be used as placeholders. |

In addition there is also file [src/components/snap/snap-common.sh](../src/components/snap/snap-common.sh), however it is not intended to be edited.
Further, there is a template for the monitoring tasks creation [src/components/snap/snapTask.template.json](../src/components/snap/snapTask.template.json) where i.e. metrics can be defined.


## Security Considerations

Virtualization in HPC environments needs to consider basic security aspects that are applied on the bare metal level, i.e. Users must not be able to gain root, as this allows them to change their uid and access other user’s confidential data.

### Authorized Images

User cannot be granted in production mode to utilize generic images they provide, as these may offer them root user access in their virtualized environment. Cluster administrators must remain in total control of user IDs, user access levels and thus the images. Only they can provide them to users via a global configuration parameter `IMAGE_POOL_DIR` that defines the location of white-listed images available to their users. This directory must be owned by root and not must not be user writable.

### Automatic Security Updates for Guests
Automatic security updates for standard Linux guests
Via cloud-init automatic security updates for standard Linux guests can be applied during boot. While this is recommended, administrators may decide to turn it off, as it delays the boot process and requires connectivity from all guests to package repositories. Especially in this case it is strongly recommended to keep images up-to-date and rebuild them frequently and  as soon as there are any security related updates available.

### Hypervisor hardening
The last aspect is the hypervisor, zero-day exploits may allow users to break out of the virtual guest and access the underlying host operating system through the hypervisor with escalated privileges. This can obviously not be handled by vTorque, thus it is recommended to make use of SELinux for Red Hat based host systems or Apparmor for Debian based ones in order to limit possible impacts of such happening to a minimum.


## Acknowledgment

This project has been conducted within the RIA [MIKELANGELO project](https://www.mikelangelo-project.eu/) (no. 645402), started in January 2015, and co-funded by the European Commission under the H2020-ICT- 07-2014: Advanced Cloud Infrastructures and Services program.
Other projects of MIKELANGELO can be found at [Github](https://github.com/mikelangelo-project)!
