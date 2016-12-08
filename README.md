Introduction
============
The aim of this project is, to extend the functionality of the [Torque Resource Manager](http://www.adaptivecomputing.com/products/open-source/torque/) to enable cloud like functionality. This includes, the startup, the provisioning and the shutdown of virtual machines inside a torque cluster. Beside a patch for torque itself, this project consists of several wrappers, that take care of the spin up and the tear down of these Vms.


HPC integration of hypervisor and guest VMs with Torque
=======================================================
Torque is being extended by a qsub wrapper, prologue and epilogue scripts, a job script wrapper, as well as a patch for the Torque source code. The qsub wrapper will be provided as a module in terms of the module system (i.e. "module avail", "module load xyz/version1.0") which is a common thing in HPC environments.


Directory structure
===================
src/ All source code
|-----> scripts/ (All script files, i.e)
|-----> templates/ (All templates)
|-----> modules/ (All modules [qsub wrapper, maybe msub wrapper too])
|-----> test/ (All tests)


Requirements
============
* cloud-utils on all compute hosts
* guest os must be Debian-, RedHat-based or OSv
* guest image file must contain the os name (ubuntu/debian,redhat/centos,osv)
* disable known hosts file for ssh (physical hosts)
* cloud-images only (cloud-init)
* data-source 'file' enabled (for cloud-init)
* [correct access] (http://wiki.libvirt.org/page/Failed_to_connect_to_the_hypervisor#Permission_denied) rights for users to libvirt
* arp -an executeable by users
* realpath
* A way to deploy vm imgs to the nodes (e.g. monted shared filesystem)


HowTo deploy
============
* copy the prologue and epilogue script onto the compute node's '/var/spool/torque/mom_priv/', do not rename them and ensure '-r-x-----'
* place the templates under /opt/torque/misc/templates
* install the qsub wrapper module as usual in the module system, place it in '/opt/system/' or modify the metadata file appropriately
* execute the test(s) to verify functionality

Setup
====
We tried to simplify the configuration as much as possible. To configure several things there is a config.sh / root-config.sh. The parameters in the table below are defined in the file config.sh and are intended to be set by the administrators globally.

| Config Parameter      | Description        |
| :---              | :---          |
| `DISABLE_MIKELANGELO_HPC_STACK` | Disables the qsub wrapper in terms of not parsing any parameters and passing on the call directly to Torque’s qsub. |
| `DISABLED_HOSTS_LIST` | Regex for host list that is disabled for VM job execution.|
| `PARALLEL`            | Execute boot processes on the remote nodes asynchronously or sequentially. Parallel execution is recommended, since huge jobs may otherwise hit the timeout for the prologue phase. |
| `ALLOW_USER_IMAGES`   | Indicates whether users are allowed to submit images with their job. |
| `IMAGE_POOL`      | Absolute path to directory on a shared file-system that contains images available to users. |
| `HOST_OS_CORE_COUNT`  | Cores reserved for the physical host. Greater or equals 0. |
| `HOST_OS_RAM_MB`      | RAM in MB reserved for the physical host. Greater than 0, should match host os requirements as this is used to calculate RAM available to guests.|
| `MAX_VMS_PER_NODE`    | Maximum count of VMs per node that cannot be exceeded. |
| `STATIC_IP_MAPPING`       | Use a static mapping of mac addresses to ip addresses, instead of a DHCP server. Recommended value is false. |
|`TIMEOUT`          | Timeout in seconds for remote processes to complete booting or destruction of  Vms. Must be lower than Torque’s timeout for pro/epilogue. |
| `SERVER_HOSTNAME`     | Short hostname of server. |
| `REAL_QSUB_ON_SERVER` | Path to qsub on the submission front-end, used by the qsub wrapper to call Torque’s qsub. |
| `REAL_QSUB_ON_NODES`  | Path to qsub on the compute nodes, used by the qsub wrapper to call Torque’s qsub. |
| `IOCM_ENABLED`        | Indicates whether `IOCM` is enabled at all. If set to false the default and user settings are ignored for iocm.|
|`IOCM_MIN_CORES`        | Min amounts of cpus that are always reserved for `IOCM`
| `IOCM_MAX_CORES`       | Max amounts of cpus that are always reserved for IOCM
| `VRDMA_ENABLED`       | Indicates whether virtual RDMA is enabled. If set to false the default and user settings are ignored for vRDMA. |
|`VRDMA_NODES`      | Regex for list of nodes that are equipped with required hardware.
|`SNAP_MONITORING_ENABLED`  | Indicates whether monitoring with snap is enabled.

The default values for all mandatory parameters, listed below, are defined in the global configuration file `config.sh`.

| Config Parameter      | Description        |
| :---              | :---          |
|`FILESYSTEM_TYPE_DEFAULT`  | Defines where to place the images for virtual guests. Shared file system `$FILESYSTEM_TYPE_SFS` and RAM disk `$FILESYSTEM_TYPE_RD` are accepted |
|`IMG_DEFAULT`          | Default image for virtual guests.|
|`DISTRO_DEFAULT`       | Distro of the guest’s image, depends on the default image. Supported OS (families) are ‘debian’, ‘redhat’ and ‘osv’|
|`ARCH_DEFAULT CPU`     | architecture of the default image. Usually ‘x86_64’|
|`VCPU_PINNING_DEFAULT` | Recommendation is to enable it. Boolean value (true/false) expected.|
|`VCPUS_DEFAULT`        | Default amount of virtual CPUs per guest|
|`RAM_DEFAULT`          | Default amount of RAM dedicated to each virtual guest.|
|`VMS_PER_NODE_DEFAULT` | Recommended is one. Must be greater or equal to 1.
|`DISK_DEFAULT`     | Persistent user disk, mounted in the first VM of a job’s resource allocation. Recommended is none (=empty).|
|`HYPERVISOR_DEFAULT`       |Accepted values are ‘kvm’ and ‘skvm’.
|`VRDMA_ENABLED_DEFAULT`    |Recommendation is to enable it. Boolean value (true/false) expected. Will be ignored if VRDMA_ENABLED is set to false.|
|`IOCM_ENABLED_DEFAULT`     |Recommendation is to enable it. Boolean value (true/false) expected. Will be ignored if |
|`IOCM_ENABLED`         |is set to false.|
|`IOCM_MIN_CORES_DEFAULT`    |Recommended value is ‘1’. Must be greater or equals 1.|
|`IOCM_MAX_CORES_DEFAULT`    |Recommended value is ‘4’. Must be greater or equals `IOCM_MIN_CORES_DEFAULT`.|

How does it works
=================
First the wrapper around qsub phrases the [new parameter] (link.to.user.guid). The information will be taken to generate files for vm start-up (prologue, prologue.parallel, vmPrologue, vmPrologue.parallel), vm shutdown (epilogue, epilogue.parallel, epilogue.precancel, vmEpilogue, vmEpilogue.parallel), the domain xml files for libvirt and the jobscript wrapper.
This wrapper calls then qsub to insert the vm job into the queue. The original qsub parameters are preserved, which makes it possible to submit non vm jobs with the same command, submit to different queues or request specialized nods or ask for features.
For deeper understanding you can read the ["D2.20 - The intermediate MIKELANGELO architecture"](https://www.mikelangelo-project.eu/wp-content/uploads/2016/07/MIKELANGELO-WP2.2-USTUTT-v2.0.pdf) in the "Technical Details on the HPC-Cloud Infrastructure" section.

Acknowledgements
================
This project has been conducted within the RIA [MIKELANGELO project](https://www.mikelangelo-project.eu/) (no. 645402), started in January 2015, and co-funded by the European Commission under the H2020-ICT- 07-2014: Advanced Cloud Infrastructures and Services programme.
Other projects of MIKELANGELO can be found at [Github](https://github.com/mikelangelo-project)!

