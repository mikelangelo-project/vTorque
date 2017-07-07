# vTorque

Virtualization support for Torque

## Table of contents

* [Introduction](#introduction)
* [How It Works](#how-it-works)
* [Architecture](#architecture)
* [Further Informations](further-informations)
    * [User Documentation](doc/userdoc.md)
    * [Administrator Documentation](doc/admindoc.md)
    * [Development Documentation](doc/devdoc.md)
* [Acknowledgments](#acknowledgments)


## Introduction

The **MIKELANGELO HPC Infrastructure** has been designed to introduce the **benefits of virtualization into the domain of high performance computing (HPC)**. These benefits comprise besides abstraction of the actual execution environment, providing portability and thus enabling application packaging, flexibility and fault-tolerance for the application execution, e.g. live migration away from degrading hardware or suspend and resume capabilities.
MIKELANGELO also improves the **I/O performance of virtual environments** crucial for the use in HPC infrastructures.

The aim of vTorque is, to extend [Torque Resource Manager](http://www.adaptivecomputing.com/products/open-source/torque/) with capabilities for the management of virtual guests. vTorque enables Torque to deploy and execute job scripts in virtual machines, transparently to the user.

vTorque consists of a set of bash scripts, several templates and new command line tools. It is independent of a specific version of Torque, thanks to its non-invasive nature.


## How It Works

vTorque provides a new submission command line tool called **vsub** deploying user job scripts in virtual environments.
It accepts all standard PBS/Torque arguments, but also introduces several new arguments related to virtual resources, e.g. the amount of vCPUs.
vTorque consists of several wrapper scripts used as hooks for the various sequences in Torque's job life-cycles, i.e. root and user prologue, to manage virtual guests.


## Architecture

The **MIKELANGELO Software Stack** for HPC consists of the following components:

- **vTorque**: A virtualization layer for the Portable Batch System (PBS) open-source fork called [Torque](http://www.adaptivecomputing.com/products/open-source/torque/). Torque is a resource manager and scheduler for HPC environments. Torque manages compute nodes and other IT resources, like GPUs or software licenses. Torque has been extended to allow users to run their HPC workloads in predefined customized virtual environments - independent of the actual software, operating system and hardware in place.

- **sKVM**: sKVM extends KVM (Kernel-based Virtual Machine) and addresses the high overhead for virtulizued I/O, by the help of

    - **IOcm**: IO core manager, an optimization for virtio-based virtual I/O devices using multiple dedicated I/O processing cores

    - **vRDMA**: Virtual RDMA, a new type of virtio device implementing the RDMA protocol for low overhead communication between virtual machines

- **Snap**: The open-source snap telemetry framework is specifically designed to allow data center owners dynamically instrument cloud-scale data-centers.

- **Guest OS**: The guest operating system (or “guest OS”) is the operating system running inside each individual VM (virtual machine). In the MIKELANGELO architecture standard **Linux** OS is already supported as guest OS and the support for **OSv** is currently in progress.

The architecture of MIKELANGELO HPC Infrastructure is explained in detail in the document [MIKELANGELO-WP2-D2.20-Architecture](https://www.mikelangelo-project.eu/wp-content/uploads/2016/07/MIKELANGELO-WP2.20-USTUTT-v2.0.pdf).

## Further Information

Further documentation for [end-users](doc/userdoc.md) describing the newly introduced arguments for the virtual execution and instructions for [administrators](doc/admindoc.md) describing how to set it up and configure it can be found in directory [doc](doc/).
For a deeper insight into vTorque's architecture please refer to ["D2.20 - The intermediate MIKELANGELO architecture"](https://www.mikelangelo-project.eu/wp-content/uploads/2016/07/MIKELANGELO-WP2.2-USTUTT-v2.0.pdf) and ["D2.21 - The final MIKELANGELO architecture"](https://www.mikelangelo-project.eu/wp-content/uploads/2017/07/MIKELANGELO-WP2.21-USTUTT-v2.0.pdf).


## Acknowledgments

This project has been conducted within the RIA [MIKELANGELO project](https://www.mikelangelo-project.eu/) (no. 645402), started in January 2015, and co-funded by the European Commission under the H2020-ICT- 07-2014: Advanced Cloud Infrastructures and Services program.
Other projects of MIKELANGELO can be found at [Github](https://github.com/mikelangelo-project)!
