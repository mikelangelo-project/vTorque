# vTorque

## Table of contents

* [Introduction](#introduction)
* [The HPC Integration](#the-hpc-integration)
* [How It Works](#how-it-works)
* [Architecture](#architecture)
* [Further Informations](further-informations)
    * [User Documentation](doc/userdoc.md)
    * [Administrator Documentation](doc/admindoc.md)
    * [Development Documentation](doc/devdoc.md)
* [Acknowledgments](#acknowledgments)

## Introduction

The **MIKELANGELO HPC Infrastructure** has been designed to improve the **I/O
performance of virtual environments in HPC systems**. The benefits of
virtualization in HPC include application packaging, deployment, and
elasticity during the application execution, without losing the high
performance in computation and communication characteristic of HPC systems.

The aim of this project is, to extend the functionality of the [Torque Resource Manager](http://www.adaptivecomputing.com/products/open-source/torque/) to enable cloud like functionality. This includes, the startup, the provisioning and the shutdown of virtual machines inside a torque cluster. Beside a patch for torque itself, this project consists of several wrappers, that take care of the spin up and the tear down of these Vms.


## The HPC Integration

Torque is being extended by a qsub wrapper, prologue and epilogue scripts, a job script wrapper, as well as a patch for the Torque source code. The qsub wrapper will be provided as a module in terms of the module system (i.e. "module avail", "module load xyz/version1.0") which is a common thing in HPC environments.

## How It Works

First the wrapper around qsub phrases the [new parameter](doc/userdoc.md). The information will be taken to generate files for vm start-up (prologue, prologue.parallel, vmPrologue, vmPrologue.parallel), vm shutdown (epilogue, epilogue.parallel, epilogue.precancel, vmEpilogue, vmEpilogue.parallel), the domain xml files for libvirt and the jobscript wrapper.
This wrapper calls then qsub to insert the vm job into the queue. The original qsub parameters are preserved, which makes it possible to submit non vm jobs with the same command, submit to different queues or request specialized nods or ask for features.
For deeper understanding you can read the ["D2.20 - The intermediate MIKELANGELO architecture"](https://www.mikelangelo-project.eu/wp-content/uploads/2016/07/MIKELANGELO-WP2.2-USTUTT-v2.0.pdf) in the "Technical Details on the HPC-Cloud Infrastructure" section.

## Architecture

The **MIKELANGELO Software Stack** consists of the following components:

- **vTorque**: A virtualization layer for the Portable Batch System (PBS) open-source fork called [Torque](http://www.adaptivecomputing.com/products/open-source/torque/). Torque is a resource manager and scheduler for HPC environments. Torque manages compute nodes and other IT resources, like GPUs or software licenses. Torque has been extended to allow users to run their HPC workloads in predefined customized virtual environments - independent of the actual software, operating system and hardware in place.

- **sKVM**: KVM (for Kernel-based Virtual Machine) is a full virtualization solution, or hypervisor, for Linux on x86 hardware. Each virtual machine has private virtualized hardware: a network card, disk, graphics adapter, etc. sKVM is the extension of KVM done in [MIKELANGELO](https://www.mikelangelo-project.eu) with 3 main features:

    - **IO core manager**: An optimization for virtio-based virtual I/O devices using multiple dedicated I/O processing cores

    - **Virtual RDMA**: A new type of virtio device implementing the RDMA protocol for low overhead communication between virtual machines

    - **SCAM**: A protection mechanism to thwart side-channel attacks (such as cache sniffing) from malicious co-located virtual machines. (Not necessary for HPC virtual environments).

- **Snap**: The open-source snap telemetry framework is specifically designed to allow data center owners dynamically instrument cloud-scale data-centers.

- **Guest OS**: The guest operating system (or “guest OS”) is the operating system running inside each individual VM (virtual machine). In the MIKELANGELO architecture standard **Linux** OS is already supported as guest OS and the support for **OSv** is currently in progress.

The architecture of MIKELANGELO HPC Infrastructure is explained in detail in the document [MIKELANGELO-WP2-D2.20-Architecture](https://www.mikelangelo-project.eu/wp-content/uploads/2016/07/MIKELANGELO-WP2.20-USTUTT-v2.0.pdf).

## Further Informations

For administrators see the [admin doc](doc/admindoc.md), for users the [user doc](doc/userdoc.md) to learn more about the usage of this project.

## Acknowledgments

This project has been conducted within the RIA [MIKELANGELO project](https://www.mikelangelo-project.eu/) (no. 645402), started in January 2015, and co-funded by the European Commission under the H2020-ICT- 07-2014: Advanced Cloud Infrastructures and Services program.
Other projects of MIKELANGELO can be found at [Github](https://github.com/mikelangelo-project)!
