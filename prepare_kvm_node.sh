#!/bin/bash -e
set -o pipefail

# Run on each kvm server

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# Provision network
NIC0="eno1"
# Tenant network
NIC1="ens2f3"
# Rhel repository mirror host
MIRROR_HOST=${MIRROR_HOST:-"10.10.50.2"}
IPMI_USER=${IPMI_USER:-"ADMIN"}
IPMI_PASSWORD=${IPMI_PASSWORD:-"ADMIN"}
# First port in range
VM_IPMI_PORT=16230
# Сreate vm with names from list
VM_NAMES="contrail-controller controller compute"

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
systemctl stop firewalld
systemctl disable firewalld

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
ovs-vsctl add-br br-ext
ovs-vsctl add-port br0 $NIC0
ovs-vsctl add-port br1 $NIC1

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
cat << EOF > br-ext.xml
<network>
  <name>br-ext</name>
  <forward mode='bridge'/>
  <bridge name='br-ext'/>
  <virtualport type='openvswitch'/>
</network>
EOF
virsh net-define br0.xml
virsh net-start br0
virsh net-autostart br0
virsh net-define br1.xml
virsh net-start br1
virsh net-autostart br1
virsh net-define br-ext.xml
virsh net-start br-ext
virsh net-autostart br-ext

for vm_name in $VM_NAMES; do
  qemu-img create -f qcow2 /var/lib/libvirt/images/${vm_name}.qcow2 120G
  virt-install --name ${vm_name} \
      --disk /var/lib/libvirt/images/${vm_name}.qcow2 \
      --vcpus=4 \
      --ram=16348 \
      --network network=br0,model=virtio,portgroup=overcloud \
      --network network=br-ext,model=virtio \
      --network network=br1,model=virtio \
      --virt-type kvm \
      --cpu host \
      --import \
      --os-variant rhel7 \
      --serial pty \
      --console pty,target_type=virtio \
      --graphics vnc \
      --noautoconsole

    vbmc add ${vm_name} --port $VM_IPMI_PORT --username ${IPMI_USER} --password ${IPMI_PASSWORD}
    vbmc start ${vm_name}
    prov_mac=`virsh domiflist ${vm_name}|grep 'br0' |awk '{print $5}'`
    vm_full_name=${vm_name}-`hostname -s`
    kvm_ip=`ip route get 1 | grep 'src' | awk '{print $7}'`
    echo ${prov_mac} ${vm_full_name} ${kvm_ip} $VM_IPMI_PORT | tee -a vm_list
    VM_IPMI_PORT=$(( $VM_IPMI_PORT + 1 ))
    virsh destroy ${vm_name}
done
