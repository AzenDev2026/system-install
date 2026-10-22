# NVazen install script
this repository contains the main script for downloading NVazen Linux  
detail NVazen releaseID= NV20261011  
![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)  
## setup
the script usually works, but if you have met some problem
gui problem, solving method is export values to install.sh,such as:
```bash
export NV_USER=nvazen NV_USER_PASS=140108 NV_ROOT=azen NV_ROOT_PASS=140108 (and others) /usr/bin/nvazen-install (or other path that stores the script)
```
all values that can be exported to install.sh
```bash
NV_TARGET_DISK	(your target disk,MUST be correct)  
NV_USERNAME   
NV_USER_PASS  
NV_ROOT_PASS  
NV_FS_TYPE  (system files type, btrfs/ext4)  
NV_HOSTNAME  
NV_YES
```
written in 2026 oct 22
main repository click [here](https://github.com/AzenDev2026/AzenDev)  
personal email [here](zitingliang18@gmail.com)  
official website [here](https://azen.dev)  
