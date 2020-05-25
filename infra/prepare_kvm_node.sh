#!/bin/bash -e
set -o pipefail

# Provision network
NIC0="eno1"
# Tenant network
NIC1="ens2f3"
MIRROR_HOST=${MIRROR_HOST:-"10.10.50.2"}

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Enable local mirrors
cat << EOF > local.repo
[local-rhel-7-server-rpms]
name = Red Hat Enterprise Linux 7 Server (RPMs) local
baseurl = http://$MIRROR_HOST/rhel-7-server-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-optional-rpms]
name = Red Hat Enterprise Linux 7 Server - Optional (RPMs) local
baseurl = http://$MIRROR_HOST/rhel-7-server-optional-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-extras-rpms]
name = Red Hat Enterprise Linux 7 Server - Extras (RPMs) local
baseurl = http://$MIRROR_HOST/rhel-7-server-extras-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF
mv local.repo /etc/yum.repos.d/

# install packages
yum -y install qemu-kvm libvirt libvirt-python libguestfs-tools virt-install \
               python3-pip libvirt-python libvirt-devel gcc python3-devel \
               openvswitch
pip3 install virtualbmc==1.5.0

systemctl enable libvirtd
systemctl start libvirtd
systemctl enable openvswitch
systemctl start openvswitch

# tune host
tuned-adm profile virtual-host
systemctl stop NetworkManager
systemctl disable NetworkManager

# create bridges
sed -i 's/dhcp/none/g' /etc/sysconfig/network-scripts/ifcfg-$NIC0
sed -i 's/dhcp/none/g' /etc/sysconfig/network-scripts/ifcfg-$NIC1
sed -i 's/ONBOOT=.*/ONBOOT=yes/g' /etc/sysconfig/network-scripts/ifcfg-$NIC0
sed -i 's/ONBOOT=.*/ONBOOT=yes/g' /etc/sysconfig/network-scripts/ifcfg-$NIC1
ovs-vsctl add-br br0
ovs-vsctl add-br br1
ovs-vsctl add-port br0 $NIC0
ovs-vsctl add-port br1 $NIC1
systemctl restart network

cat << EOF > br0.xml
<network>
  <name>br0</name>
  <forward mode='bridge'/>
  <bridge name='br0'/>
  <virtualport type='openvswitch'/>
  <portgroup name='overcloud'>
    <vlan trunk='yes'>
      <tag id='700' nativeMode='untagged'/>
      <tag id='710'/>
      <tag id='720'/>
      <tag id='730'/>
      <tag id='740'/>
      <tag id='750'/>
    </vlan>
  </portgroup>
</network>
EOF
cat << EOF > br1.xml
<network>
  <name>br1</name>
  <forward mode='bridge'/>
  <bridge name='br1'/>
  <virtualport type='openvswitch'/>
</network>
EOF
virsh net-define br0.xml
virsh net-start br0
virsh net-autostart br0
virsh net-define br1.xml
virsh net-start br1
virsh net-autostart br1
