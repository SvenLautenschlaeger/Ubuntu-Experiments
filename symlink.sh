#!/bin/bash/

#find /home/armadillo/yocto/seg5/fsl-community-bsp/tx6q -print0 -type f -size -1k
find /home/armadillo/yocto/seg5/fsl-community-bsp/tx6q -print0 -type f -size -1k | xargs -0 -n 1 fixlink.pl 

