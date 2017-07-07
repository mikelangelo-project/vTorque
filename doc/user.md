# vTorque User Manual


## Introduction

The **MIKELANGELO HPC Infrastructure** has been designed to introduce the **benefits of virtualization into the domain of high performance computing (HPC)**. These benefits comprise besides abstraction of the actual execution environment, providing portability and thus enabling application packaging, flexibility and fault-tolerance for the application execution, e.g. live migration away from degrading hardware or suspend and resume capabilities.
MIKELANGELO also improves the **I/O performance of virtual environments** crucial for the use in HPC infrastructures.

The aim of vTorque is, to extend [Torque Resource Manager](http://www.adaptivecomputing.com/products/open-source/torque/) with capabilities for the management of virtual guests. vTorque enables Torque to deploy and execute job scripts in virtual machines, transparently to the user.


## Table of contents

* [How It Works](#how-it-works)
* [vsub Arguments](#vsub-arguments)
* [Defaults for vsub](#defaults-for-vsub)
* [Considerations](#considerations)
* [Acknowledgment](#acknowledgment)


## How It Works

For a VM-based job execution users have with vTorque now the opportunity to request several VM related parameters, but are at the same time free to skip them and utilize defaults. All parameters not provided by the user at submission time, will be set to values defined by the cluster administrators.

The standard Torque's qsub accepts resource requests on the command line by prefixing these by a ‘-l’, i.e.
```sh
qsub -l nodes=2,walltime=00:15:00 jobScript.sh
```

vTorque introduces the command line submission tool **vsub** for virtualized job execution in the same by prefixing VM resource requests by a '-vm', i.e.
```sh
vsub -l nodes=2,walltime=00:15:00 -vm vcpus=14 jobScript.sh
```


## vsub Arguments

The command line submission tool vsub accepts several arguments enabling users to define the virtual job execution environment, in order to provide flexibility to match an application's individual requirements as best as possible.

| Parameter         | Valid values                  | Description            |
| :---              | :---                          | :---                   |
| `img`             | Any `*.img/*.qcow2` file.   | VM image file for the job execution. |
| `distro`          | `debian/ubuntu/redhat/centos/osv` | Distro of the image, i.e. debian, redhat, osv. |
| `arch`            | Refer to KVM docs, please.   | CPU architecture, must match compute nodes and the guest image. |
| `vcpus`           | Positive number.             | Amount of vCPU assigned to each guest. |
| `vcpu_pinning`   | `true/false/<pinning_file>` | Use vCPU pinning or not. |
| `vms_per_node`   | Positive number.             | Amount of VMs per allocated physical node. |
| `vm_prologue`    | An executable file.           | Optional user prologue script run in standard Linux guests. |
| `vm_epilogue`    | An executable file.           | Optional user epilogue script run in standard Linux guests. |
| `vrdma`           | `true/false`                | Dis/enable vRDMA. |
| `iocm`            | `true/false`                | Dis/enable IOcm. |
| `iocm_min_cores` | Positive number.              | Define minimum amount of dedicated IOcm cores. |
| `iocm_max_cores` | Positive number.              | Define maximum amount of dedicated IOcm cores. |
| `fs_type`         | `sharedfs/ramdisk`          | File-system type for VM images, either sahred fs or local ram disk. |
| `disk`            | Any `*.img/*.qcow2` file.    | Optional persistent disk, mounted at the first VM (rank 0). |


## Defaults for vsub

For each `-vm ..` parameter there are defaults, defined by the cluster administrators. These are applied in case user doesn't request it explicitly. In case of doubts it is recommended to rely on the defaults provided.


## Considerations

Use `/workspace` to write out intermediate application data that benefit from the fast shared file-system. This path is not intended to keep any data beyond a job’s runtime. It is mapped to the actual cluster’s shared workspace file-system, configured by the cluster administrators, and may be wiped after a job has completed.

The directory path `/home` is also external storage and should be considered as slower mid term storage where data can reside after a job has finished.

Optional, persistent, mid-term storage may be available under path `/data`, in case there is a default disk defined globally or the user explicitly defined it at submission time. It will be mounted to the first virtual guest of a job’s resource allocation where the user’s job script is executed.

Keep in mind that directory `/opt` is mounted from the cluster environment and binaries may not be compatible.


## Acknowledgment

This project has been conducted within the RIA [MIKELANGELO project](https://www.mikelangelo-project.eu/) (no. 645402), started in January 2015, and co-funded by the European Commission under the H2020-ICT- 07-2014: Advanced Cloud Infrastructures and Services program.
Other projects of MIKELANGELO can be found at [Github](https://github.com/mikelangelo-project)!
