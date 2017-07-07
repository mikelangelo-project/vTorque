# Guest Images Documentation


## Introduction

This document outlines the requirements for guest images and the packing with LEET, as well as manual packaging.


## Table Of Contents

* [Guest Image Requirements](#guest-image-requirements)
  * [vRDMA](#vrdma)
* [Application Packaging](#application-packaging)
  * [Standard Linux Guests](#standard-linux-guests)
  * [OSv Guests](#osv-guests)
* [Acknowledgment](#acknowledgment)


## Guest Image Requirements

Supported guest OS families are: Debian, RedHat and OSv.  
Guest images are required to have:
* package `cloud-init` installed
* cloud-init data-source `no-cloud` is enabled
* workspace directory for intermediate data is `/workspace`
* user homes at the default location `/home`
* `/opt` cannot be used, but `/opt-vm` instead since cluster's `/opt` is mounted

### vRDMA

In order to utilize the optional vRDMA functionality, guests must have the support for it also installed. For details please refer to the vRDMA [documentation](https://www.mikelangelo-project.eu/wp-content/uploads/2016/06/MIKELANGELO-WP4.1-Huawei-DE_v2.0.pdf).


## Application Packaging


### Standard Linux Guests

For building standard Linux cloud images, please refer to the [OpenStack image creation guide](https://docs.openstack.org/image-guide/create-images-manually.html) and mind vTorque's [requirements](#guest-image-requirements). 

Applications can either be installed in the running guest during the image creation, or afterwards by copying application binaries and files into the guest image by the help of [guestfish](http://libguestfs.org/guestfish.1.html).


### OSv Guests

For the packaging of applications with OSv guest images, please refer to the [OSv documentation](https://github.com/cloudius-systems/osv) and OSv packaging tool [Capstan](https://github.com/mikelangelo-project/capstan).



## Acknowledgment

This project has been conducted within the RIA [MIKELANGELO project](https://www.mikelangelo-project.eu/) (no. 645402), started in January 2015, and co-funded by the European Commission under the H2020-ICT- 07-2014: Advanced Cloud Infrastructures and Services program.
Other projects of MIKELANGELO can be found at [Github](https://github.com/mikelangelo-project)!
