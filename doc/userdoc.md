# MIKELANGELO User Manual

## Introduction

The **MIKELANGELO HPC Infrastructure** has been designed to improve the **I/O performance of virtual environments in HPC systems**. The benefits of virtualization in HPC include application packaging, deployment, and elasticity during the application execution, without losing the high performance in computation and communication characteristic of HPC systems.

This document explains briefly how a user can submit run their job in a virtualized environment provided by the MIKELANGELO software stack for HPC Infrastructure. For further details please refer to the document [MIKELANGELO-WP2-D2.20-Architecture](https://www.mikelangelo-project.eu/wp-content/uploads/2016/07/MIKELANGELO-WP2.20-USTUTT-v2.0.pdf).

## Table of contents

* [VM-based Job Submission](#vm-based-job-submission)
    * [VM Parameters](#vm-parameters)
        * [IO Core Manager](io-core-manager)
        * [Virtual RDMA](#virtual-rdma)
* [Torque Extensions for OSv](#torque-extensions-for-osv)
* [Considerations](#considerations)
* [Acknowledgment](#acknowledgment)



## VM-based Job Submission

For a VM-based job execution users have the opportunity to define many resources, but are free to skip most of these. Parameters needed, but not provided, will be set to the default values that are defined in a global configuration file and are chosen by the HPC system administrators.

The standard qsub resource requests are issued by prefixing a ‘-l’, i.e.
```sh
qsub -l nodes=2,walltime=00:15:00 jobScript.sh
```
### VM Parameters

The resources/parameters that are dedicated to the virtual guest(s) are appended to the physical resource request in a similar way.

The vm resources and parameters are requested by issuing them with a ‘-vm’ prefix, i.e.
```sh
qsub -l nodes=2,walltime=00:15:00 -vm img=image.img,distro=debian jobScript.sh
```
As an example, suppose the user is requesting 16 cores per node using the virtual environment. The image is a specified as a debian and is inside the image.img. The job that will be executed is defined as jobScript.sh.

The user is informed about this reduction at submission time and is allowed to cancel their job and modify the specification of cores per node and IOcm core count request to match their requirements.
For further details and a full list of supported parameters can be found in the document [MIKELANGELO-WP2-D2.20-Architecture](https://www.mikelangelo-project.eu/wp-content/uploads/2016/07/MIKELANGELO-WP2.20-USTUTT-v2.0.pdf), Appendix A.3.

- IMG: <path to image e.g. /image/image.img>
- DISTRO: <debian|rethat|osv>
- RAM: <count in MB>
- VCPUS: <count>
- VMS_PER_NODE: <count>
- METADATA <path>
- DISK <path>
- ARCH <x86_64>
- HYPERVISOR <kvm|skvm>
- VCPU_PINNING <path to virsh xml fragment|auto|enabled|true|yes|0|disabled|false|no|1>
- VM_PROLOGUE <path>
- VM_EPILOGUE <path>
- VRDMA <true|false>
- IOCM <true|false>
- IOCM_MIN <count>
- IOCM_MAX <count>
- FS_TYPE <>

#### IO Core Manager

The integration of the IO core manager (IOcm), in order to increase I/O operations for virtual guests, into our extensions for Torque, provides addiotional parameters that the user can define on the job submission command line or inline in the job script’s header section.

These additional (optional) qsub command line parameters for IOcm are prefixed with ‘-vm’:

```sh
iocm=true|false
iocm_min_cores=<number gt 0>
iocm_max_cores=<number gt 0 and ge iocm_min_cores>
```
Furthermore, there are default parameters defined in the global admin configuration that come into place when IOCM_ENABLED is globally set to true and the user does not provide any IOCM_* parameters.

For details, please refer to document [MIKELANGELO-WP2-D2.20-Architecture](https://www.mikelangelo-project.eu/wp-content/uploads/2016/07/MIKELANGELO-WP2.20-USTUTT-v2.0.pdf), section 4.4.4.

#### Virtual RDMA

Integration of vRDMA connectivity to enable multiple virtual guests to share the Infiniband network of the underlying host system into our extensions for Torque, provides additional parameters that the user can define on the job submission command line or inline in the job script’s header section.

The additional (optional) qsub command line parameters for vRDMA are prefixed with ‘-vm’:

```sh
vrdma=true|false
```

Furthermore, there are default parameters defined in the global admin configuration that applies when VRDMA_ENABLED is globally set to true and the user does not provide any vRDMA parameter.

For details, please refer to document [MIKELANGELO-WP2-D2.20-Architecture](https://www.mikelangelo-project.eu/wp-content/uploads/2016/07/MIKELANGELO-WP2.20-USTUTT-v2.0.pdf), section 4.4.5.


Please refer to the document [MIKELANGELO-WP2-D2.20-Architecture](https://www.mikelangelo-project.eu/wp-content/uploads/2016/07/MIKELANGELO-WP2.20-USTUTT-v2.0.pdf), Appendix A.2, for the details about available metrics.

## Torque Extensions for OSv

The extensions required for OSv are almost in line with standard Linux guests, however there are some minor differences in the way OSv images are handled, e.g. regarding meta data and interactive jobs. OSv furthermore requires modifications of the MPI startup, due to its nature of being a single-process container, while MPI depends on multiple processes for its polling, running its daemons, etc. **These extensions are currently being implemented and tested and therefore the use os OSv-based VM is not supported yet**.

## Considerations

Application developers are requested to make use of the directory path ‘**/workspace**’ to write out intermediate application data that benefit from the fast shared file-system. This path is not intended to keep any data beyond a job’s runtime. It is mapped to the actual cluster’s shared workspace file-system, configured by the cluster administrators, and may be wiped after a job has completed.

The directory path ‘**/home**’ is also external storage and should be considered as slower mid term storage where data can reside after a job.

Optional, persistent, mid-term storage may be available under path ‘**/data**’, in case there is a default disk defined globally or the user explicitly defined it at submission time. It will be mounted to the first virtual guest of a job’s resource allocation where the user’s job script is executed.

## Acknowledgment

This project has been conducted within the RIA [MIKELANGELO project](https://www.mikelangelo-project.eu/) (no. 645402), started in January 2015, and co-funded by the European Commission under the H2020-ICT- 07-2014: Advanced Cloud Infrastructures and Services program.
Other projects of MIKELANGELO can be found at [Github](https://github.com/mikelangelo-project)!
