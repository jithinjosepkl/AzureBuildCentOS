# Kickstart for provisioning a CentOS 7.6 Azure HPC (SR-IOV) VM

# System authorization information
auth --enableshadow --passalgo=sha512

# Use graphical install
text

# Do not run the Setup Agent on first boot
firstboot --disable

# Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'

# System language
lang en_US.UTF-8

# Network information
network --bootproto=dhcp

# Use network installation
url --url="http://olcentgbl.trafficmanager.net/centos/7.6.1810/os/x86_64/"
repo --name "os" --baseurl="http://olcentgbl.trafficmanager.net/centos/7.6.1810/os/x86_64/" --cost=100
repo --name="updates" --baseurl="http://olcentgbl.trafficmanager.net/centos/7.6.1810/updates/x86_64/" --cost=100
repo --name "extras" --baseurl="http://olcentgbl.trafficmanager.net/centos/7.6.1810/extras/x86_64/" --cost=100
repo --name="openlogic" --baseurl="http://olcentgbl.trafficmanager.net/openlogic/7/openlogic/x86_64/"

# Root password
rootpw --plaintext "to_be_disabled"

# System services
services --enabled="sshd,waagent,dnsmasq,NetworkManager"

# System timezone
timezone Etc/UTC --isUtc

# Partition clearing information
clearpart --all --initlabel

# Clear the MBR
zerombr

# Disk partitioning information
part /boot --fstype="xfs" --size=500
part / --fstype="xfs" --size=1 --grow --asprimary

# System bootloader configuration
bootloader --location=mbr --timeout=1

# Firewall configuration
firewall --disabled

# Enable SELinux
selinux --enforcing

# Don't configure X
skipx

# Power down the machine after install
poweroff

# Disable kdump
%addon com_redhat_kdump --disable
%end

%packages
@base
@console-internet
@development
ntp
cifs-utils
sudo
python-pyasn1
parted
WALinuxAgent
hypervkvpd
azure-repo-svc
-dracut-config-rescue
selinux-policy-devel
kernel-headers
nfs-utils
numactl
numactl-devel
libxml2-devel
byacc
environment-modules
python-devel
python-setuptools
gtk2
atk
cairo
tcl
tk
m4
glibc-devel
glibc-static
libudev-devel
binutils
binutils-devel
%end

%post --log=/var/log/anaconda/post-install.log

#!/bin/bash

# Disable the root account
usermod root -p '!!'

# Set OL repos
curl -so /etc/yum.repos.d/CentOS-Base.repo https://raw.githubusercontent.com/szarkos/AzureBuildCentOS/master/config/azure/CentOS-Base-7.repo
curl -so /etc/yum.repos.d/OpenLogic.repo https://raw.githubusercontent.com/szarkos/AzureBuildCentOS/master/config/azure/OpenLogic.repo

# Import CentOS and OpenLogic public keys
curl -so /etc/pki/rpm-gpg/OpenLogic-GPG-KEY https://raw.githubusercontent.com/szarkos/AzureBuildCentOS/master/config/OpenLogic-GPG-KEY
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
rpm --import /etc/pki/rpm-gpg/OpenLogic-GPG-KEY

# Set the kernel cmdline
sed -i 's/^\(GRUB_CMDLINE_LINUX\)=".*"$/\1="console=tty1 console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300 net.ifnames=0 scsi_mod.use_blk_mq=y"/g' /etc/default/grub

# Enable grub serial console
echo 'GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"' >> /etc/default/grub
sed -i 's/^GRUB_TERMINAL_OUTPUT=".*"$/GRUB_TERMINAL="serial console"/g' /etc/default/grub

# Blacklist the nouveau driver
cat << EOF > /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
options nouveau modeset=0
EOF

# Rebuild grub.cfg
grub2-mkconfig -o /boot/grub2/grub.cfg

# Enable SSH keepalive
sed -i 's/^#\(ClientAliveInterval\).*$/\1 180/g' /etc/ssh/sshd_config

# Configure network
cat << EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=dhcp
TYPE=Ethernet
USERCTL=no
PEERDNS=yes
IPV6INIT=no
NM_CONTROLLED=yes
PERSISTENT_DHCLIENT=yes
EOF

cat << EOF > /etc/sysconfig/network
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF

# Deploy new configuration
cat <<EOF > /etc/pam.d/system-auth-ac

auth        required      pam_env.so
auth        sufficient    pam_fprintd.so
auth        sufficient    pam_unix.so nullok try_first_pass
auth        requisite     pam_succeed_if.so uid >= 1000 quiet_success
auth        required      pam_deny.so

account     required      pam_unix.so
account     sufficient    pam_localuser.so
account     sufficient    pam_succeed_if.so uid < 1000 quiet
account     required      pam_permit.so

password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type= ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1
password    sufficient    pam_unix.so sha512 shadow nullok try_first_pass use_authtok remember=5
password    required      pam_deny.so

session     optional      pam_keyinit.so revoke
session     required      pam_limits.so
-session     optional      pam_systemd.so
session     [success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
session     required      pam_unix.so

EOF

# Disable persistent net rules
ln -s /dev/null /etc/udev/rules.d/75-persistent-net-generator.rules
rm -f /lib/udev/rules.d/75-persistent-net-generator.rules /etc/udev/rules.d/70-persistent-net.rules 2>/dev/null
rm -f /etc/udev/rules.d/70* 2>/dev/null
ln -s /dev/null /etc/udev/rules.d/80-net-name-slot.rules

# Disable NetworkManager handling of the SRIOV interfaces
cat <<EOF > /etc/udev/rules.d/68-azure-sriov-nm-unmanaged.rules

# Accelerated Networking on Azure exposes a new SRIOV interface to the VM.
# This interface is transparently bonded to the synthetic interface,
# so NetworkManager should just ignore any SRIOV interfaces.
SUBSYSTEM=="net", DRIVERS=="hv_pci", ACTION=="add", ENV{NM_UNMANAGED}="1"

EOF

# Disable some unneeded services by default (administrators can re-enable if desired)
systemctl disable wpa_supplicant
systemctl disable abrtd
systemctl disable firewalld

# Update memory limits
cat << EOF >> /etc/security/limits.conf
*               hard    memlock         unlimited
*               soft    memlock         unlimited
*               soft    nofile          65535
*               hard    nofile          65535
EOF

# Disable GSS proxy
sed -i 's/GSS_USE_PROXY="yes"/GSS_USE_PROXY="no"/g' /etc/sysconfig/nfs

# Enable reclaim mode
echo "vm.zone_reclaim_mode = 1" >> /etc/sysctl.conf
sysctl -p

# Install Mellanox OFED
mkdir -p /tmp/mlnxofed
cd /tmp/mlnxofed
wget https://www.mellanox.com/downloads/ofed/MLNX_OFED-4.7-1.0.0.1/MLNX_OFED_LINUX-4.7-1.0.0.1-rhel7.6-x86_64.tgz
tar zxvf MLNX_OFED_LINUX-4.7-1.0.0.1-rhel7.6-x86_64.tgz

KERNEL=( $(rpm -q kernel | sed 's/kernel\-//g') )
KERNEL=${KERNEL[-1]}
yum install -y kernel-devel-${KERNEL}
./MLNX_OFED_LINUX-4.7-1.0.0.1-rhel7.6-x86_64/mlnxofedinstall --kernel $KERNEL --kernel-sources /usr/src/kernels/${KERNEL} --add-kernel-support --skip-repo
cd && rm -rf /tmp/mlnxofed

# Configure WALinuxAgent
sed -i -e 's/# OS.EnableRDMA=y/OS.EnableRDMA=y/g' /etc/waagent.conf
sed -i -e 's/CGroups.EnforceLimits=n/CGroups.EnforceLimits=y/g' /etc/waagent.conf
systemctl enable waagent

# Default path
LD_LIBRARY_PATH=${LD_LIBRARY_PATH-}:/usr/lib64:/usr/local/lib

# Install gcc 8.2
mkdir -p /tmp/setup-gcc
cd /tmp/setup-gcc

wget ftp://gcc.gnu.org/pub/gcc/infrastructure/gmp-6.1.0.tar.bz2
tar -xvf gmp-6.1.0.tar.bz2
cd ./gmp-6.1.0
./configure --enable-cxx=detect && make -j && make install
cd ..

wget ftp://gcc.gnu.org/pub/gcc/infrastructure/mpfr-3.1.4.tar.bz2
tar -xvf mpfr-3.1.4.tar.bz2
cd mpfr-3.1.4
./configure && make -j && make install
cd ..

wget ftp://gcc.gnu.org/pub/gcc/infrastructure/mpc-1.0.3.tar.gz
tar -xvf mpc-1.0.3.tar.gz
cd mpc-1.0.3
./configure && make -j && make install
cd ..

# install gcc 8.2
wget https://ftp.gnu.org/gnu/gcc/gcc-8.2.0/gcc-8.2.0.tar.gz
tar -xvf gcc-8.2.0.tar.gz
cd gcc-8.2.0
./configure --disable-multilib --prefix=/opt/gcc-8.2.0 && make -j && make install
cd && rm -rf /tmp/setup-gcc


cat << EOF >> /usr/share/Modules/modulefiles/gcc-8.2.0
#%Module 1.0
#
#  GCC 8.2.0
#

prepend-path    PATH            /opt/gcc-8.2.0/bin
prepend-path    LD_LIBRARY_PATH /opt/gcc-8.2.0/lib64
setenv          CC              /opt/gcc-8.2.0/bin/gcc
setenv          GCC             /opt/gcc-8.2.0/bin/gcc
EOF

# Load gcc-8.2.0
export PATH=/opt/gcc-8.2.0/bin:$PATH
export LD_LIBRARY_PATH=/opt/gcc-8.2.0/lib64:$LD_LIBRARY_PATH
set CC=/opt/gcc-8.2.0/bin/gcc
set GCC=/opt/gcc-8.2.0/bin/gcc

# Install MPIs
INSTALL_PREFIX=/opt
mkdir -p /tmp/mpi
cd /tmp/mpi

# MVAPICH2 2.3.2
MV2_VERSION="2.3.2"
wget http://mvapich.cse.ohio-state.edu/download/mvapich/mv2/mvapich2-${MV2_VERSION}.tar.gz
tar -xvf mvapich2-${MV2_VERSION}.tar.gz
cd mvapich2-${MV2_VERSION}
./configure --prefix=${INSTALL_PREFIX}/mvapich2-${MV2_VERSION} --enable-g=none --enable-fast=yes && make -j && make install
cd ..

# HPC-X v2.5.0
HPCX_VERSION="v2.5.0"
cd ${INSTALL_PREFIX}
wget http://www.mellanox.com/downloads/hpc/hpc-x/v2.6/hpcx-v2.5.0-gcc-MLNX_OFED_LINUX-4.7-1.0.0.1-redhat7.6-x86_64.tbz
tar -xvf hpcx-v2.5.0-gcc-MLNX_OFED_LINUX-4.7-1.0.0.1-redhat7.6-x86_64.tbz
HPCX_PATH=${INSTALL_PREFIX}/hpcx-v2.5.0-gcc-MLNX_OFED_LINUX-4.7-1.0.0.1-redhat7.6-x86_64
HCOLL_PATH=${HPCX_PATH}/hcoll
UCX_PATH=${HPCX_PATH}/ucx
rm -rf hpcx-v2.5.0-gcc-MLNX_OFED_LINUX-4.7-1.0.0.1-redhat7.6-x86_64.tbz
cd /tmp/mpi

# OpenMPI 4.0.1
OMPI_VERSION="4.0.1"
wget https://download.open-mpi.org/release/open-mpi/v4.0/openmpi-${OMPI_VERSION}.tar.gz
tar -xvf openmpi-${OMPI_VERSION}.tar.gz
cd openmpi-${OMPI_VERSION}
./configure --prefix=${INSTALL_PREFIX}/openmpi-${OMPI_VERSION} --with-ucx=${UCX_PATH} --with-hcoll=${HCOLL_PATH} --enable-mpirun-prefix-by-default --with-platform=contrib/platform/mellanox/optimized && make -j && make install
cd ..

# MPICH 3.3.1
MPICH_VERSION="3.3.1"
wget http://www.mpich.org/static/downloads/${MPICH_VERSION}/mpich-${MPICH_VERSION}.tar.gz
tar -xvf mpich-${MPICH_VERSION}.tar.gz
cd mpich-${MPICH_VERSION}
./configure --prefix=${INSTALL_PREFIX}/mpich-${MPICH_VERSION} --with-ucx=${UCX_PATH} --with-hcoll=${HCOLL_PATH} --enable-g=none --enable-fast=yes --with-device=ch4:ucx   && make -j && make install
cd ..

# Intel MPI 2019 (update 5)
IMPI_2019_VERSION="2019.5.281"
CFG="IntelMPI-v2019.x-silent.cfg"
wget http://registrationcenter-download.intel.com/akdlm/irc_nas/tec/15838/l_mpi_${IMPI_2019_VERSION}.tgz
wget https://raw.githubusercontent.com/szarkos/AzureBuildCentOS/master/config/azure/${CFG}
tar -xvf l_mpi_${IMPI_2019_VERSION}.tgz
cd l_mpi_${IMPI_2019_VERSION}
./install.sh --silent /tmp/mpi/${CFG}
cd ..

# Intel MPI 2018 (update 4)
IMPI_VERSION="2018.4.274"
CFG="IntelMPI-v2018.x-silent.cfg"
wget http://registrationcenter-download.intel.com/akdlm/irc_nas/tec/13651/l_mpi_${IMPI_VERSION}.tgz
wget https://raw.githubusercontent.com/szarkos/AzureBuildCentOS/master/config/azure/${CFG}
tar -xvf l_mpi_${IMPI_VERSION}.tgz
cd l_mpi_${IMPI_VERSION}
./install.sh --silent /tmp/mpi/${CFG}
cd ..

cd && rm -rf /tmp/mpi

# Setup module files for MPIs
mkdir -p /usr/share/Modules/modulefiles/mpi/

# HPC-X
cat << EOF >> /usr/share/Modules/modulefiles/mpi/hpcx-${HPCX_VERSION}
#%Module 1.0
#
#  HPCx $(HPCX_VERSION)
#
conflict        mpi
module load /opt/hpcx-v2.5.0-gcc-MLNX_OFED_LINUX-4.7-1.0.0.1-redhat7.6-x86_64/modulefiles/hpcx
EOF

# MPICH
cat << EOF >> /usr/share/Modules/modulefiles/mpi/mpich-${MPICH_VERSION}
#%Module 1.0
#
#  MPICH ${MPICH_VERSION}
#
conflict        mpi
prepend-path    PATH            /opt/mpich-${MPICH_VERSION}/bin
prepend-path    LD_LIBRARY_PATH /opt/mpich-${MPICH_VERSION}/lib
prepend-path    MANPATH         /opt/mpich-${MPICH_VERSION}/share/man
setenv          MPI_BIN         /opt/mpich-${MPICH_VERSION}/bin
setenv          MPI_INCLUDE     /opt/mpich-${MPICH_VERSION}/include
setenv          MPI_LIB         /opt/mpich-${MPICH_VERSION}/lib
setenv          MPI_MAN         /opt/mpich-${MPICH_VERSION}/share/man
setenv          MPI_HOME        /opt/mpich-${MPICH_VERSION}
EOF

# MVAPICH2
cat << EOF >> /usr/share/Modules/modulefiles/mpi/mvapich2-${MV2_VERSION}
#%Module 1.0
#
#  MVAPICH2 $(MV2_VERSION)
#
conflict        mpi
prepend-path    PATH            /opt/mvapich2-${MV2_VERSION}/bin
prepend-path    LD_LIBRARY_PATH /opt/mvapich2-${MV2_VERSION}/lib
prepend-path    MANPATH         /opt/mvapich2-${MV2_VERSION}/share/man
setenv          MPI_BIN         /opt/mvapich2-${MV2_VERSION}/bin
setenv          MPI_INCLUDE     /opt/mvapich2-${MV2_VERSION}/include
setenv          MPI_LIB         /opt/mvapich2-${MV2_VERSION}/lib
setenv          MPI_MAN         /opt/mvapich2-${MV2_VERSION}/share/man
setenv          MPI_HOME        /opt/mvapich2-${MV2_VERSION}
EOF

# OpenMPI
cat << EOF >> /usr/share/Modules/modulefiles/mpi/openmpi-${OMPI_VERSION}
#%Module 1.0
#
#  OpenMPI ${OMPI_VERSION}
#
conflict        mpi
prepend-path    PATH            /opt/openmpi-${OMPI_VERSION}/bin
prepend-path    LD_LIBRARY_PATH /opt/openmpi-${OMPI_VERSION}/lib
prepend-path    MANPATH         /opt/openmpi-${OMPI_VERSION}/share/man
setenv          MPI_BIN         /opt/openmpi-${OMPI_VERSION}/bin
setenv          MPI_INCLUDE     /opt/openmpi-${OMPI_VERSION}/include
setenv          MPI_LIB         /opt/openmpi-${OMPI_VERSION}/lib
setenv          MPI_MAN         /opt/openmpi-${OMPI_VERSION}/share/man
setenv          MPI_HOME        /opt/openmpi-${OMPI_VERSION}
EOF

#IntelMPI-v2018
cat << EOF >> /usr/share/Modules/modulefiles/mpi/impi_${IMPI_VERSION}
#%Module 1.0
#
#  Intel MPI ${IMPI_VERSION}
#
conflict        mpi
prepend-path    PATH            /opt/intel/impi/${IMPI_VERSION}/intel64/bin
prepend-path    LD_LIBRARY_PATH /opt/intel/impi/${IMPI_VERSION}/intel64/lib
prepend-path    MANPATH         /opt/intel/impi/${IMPI_VERSION}/man
setenv          MPI_BIN         /opt/intel/impi/${IMPI_VERSION}/intel64/bin
setenv          MPI_INCLUDE     /opt/intel/impi/${IMPI_VERSION}/intel64/include
setenv          MPI_LIB         /opt/intel/impi/${IMPI_VERSION}/intel64/lib
setenv          MPI_MAN         /opt/intel/impi/${IMPI_VERSION}/man
setenv          MPI_HOME        /opt/intel/impi/${IMPI_VERSION}/intel64
EOF

#IntelMPI-v2019
cat << EOF >> /usr/share/Modules/modulefiles/mpi/impi_${IMPI_2019_VERSION}
#%Module 1.0
#
#  Intel MPI ${IMPI_2019_VERSION}
#
conflict        mpi
prepend-path    PATH            /opt/intel/impi/${IMPI_2019_VERSION}/intel64/bin
prepend-path    LD_LIBRARY_PATH /opt/intel/impi/${IMPI_2019_VERSION}/intel64/lib
prepend-path    MANPATH         /opt/intel/impi/${IMPI_2019_VERSION}/man
setenv          MPI_BIN         /opt/intel/impi/${IMPI_2019_VERSION}/intel64/bin
setenv          MPI_INCLUDE     /opt/intel/impi/${IMPI_2019_VERSION}/intel64/include
setenv          MPI_LIB         /opt/intel/impi/${IMPI_2019_VERSION}/intel64/lib
setenv          MPI_MAN         /opt/intel/impi/${IMPI_2019_VERSION}/man
setenv          MPI_HOME        /opt/intel/impi/${IMPI_2019_VERSION}/intel64
EOF

# Create symlinks for modulefiles
ls -s /usr/share/Modules/modulefiles/mpi/hpcx-${HPCX_VERSION} /usr/share/Modules/modulefiles/mpi/hpcx
ls -s /usr/share/Modules/modulefiles/mpi/mpich-${MPICH_VERSION} /usr/share/Modules/modulefiles/mpi/mpich
ls -s /usr/share/Modules/modulefiles/mpi/mvapich2-${MV2_VERSION} /usr/share/Modules/modulefiles/mpi/mvapich2
ls -s /usr/share/Modules/modulefiles/mpi/openmpi-${OMPI_VERSION} /usr/share/Modules/modulefiles/mpi/openmpi
ls -s /usr/share/Modules/modulefiles/mpi/impi_${IMPI_2019_VERSION} /usr/share/Modules/modulefiles/mpi/impi-2019
ls -s /usr/share/Modules/modulefiles/mpi/impi_${IMPI_VERSION} /usr/share/Modules/modulefiles/mpi/impi

# Modify yum
echo "http_caching=packages" >> /etc/yum.conf
yum history sync
yum clean all

# Set tuned profile
echo "virtual-guest" > /etc/tuned/active_profile

# Deprovision and prepare for Azure
/usr/sbin/waagent -force -deprovision

%end
