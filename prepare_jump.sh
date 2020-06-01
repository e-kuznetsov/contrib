#!/bin/bash -e
set -o pipefail

# Run on jump server

# Undercloud VM config
undercloud_name=rhel7
undercloud_suffix=local
root_password=c0ntrail123
stack_password=c0ntrail123
vcpus=8
vram=32000

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# install packages
yum -y install qemu-kvm libvirt libvirt-python libguestfs-tools virt-install openvswitch \
    httpd screen yum-utils createrepo

# tune host
systemctl enable httpd
systemctl start httpd
systemctl enable libvirtd
systemctl start libvirtd
systemctl enable openvswitch
systemctl start openvswitch
systemctl stop firewalld
systemctl disable firewalld
systemctl stop NetworkManager
systemctl disable NetworkManager
tuned-adm profile virtual-host

# Enable mirror repos
cat << 'EOF' > update_mirror_repo
#!/bin/bash -x

repos="rhel-7-server-rpms
rhel-7-server-extras-rpms
rhel-7-server-optional-rpms
rhel-server-rhscl-7-rpms
rhel-7-server-rh-common-rpms
rhel-ha-for-rhel-7-server-rpms
rhel-7-server-openstack-13-devtools-rpms
rhel-7-server-openstack-13-rpms"

function sync_repo() {
  local r=$1
  reposync --gpgcheck -l --repoid=$r --download_path=/var/www/html --downloadcomps --download-metadata
  cd /var/www/html/$r
  createrepo --workers=2 -v /var/www/html/${r}/ -g comps.xml
}

for r in $repos; do
  sync_repo $r
done
EOF
chmod +x update_mirror_repo
mv update_mirror_repo /etc/cron.weekly/

# create briges
virsh iface-bridge eno1 br-mgmt
virsh iface-bridge ens2f3 br-data
ovs-vsctl add-br br0
ovs-vsctl add-port br0 eno2

# ceate virtual net
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
virsh net-define br0.xml
virsh net-start br0
virsh net-autostart br0

# Create undercloud vm
cat << EOF > $HOME/local.repo

[local-rhel-7-server-rpms]
name = Red Hat Enterprise Linux 7 Server (RPMs) local
baseurl = http://10.10.50.2/rhel-7-server-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-optional-rpms]
name = Red Hat Enterprise Linux 7 Server - Optional (RPMs) local
baseurl = http://10.10.50.2/rhel-7-server-optional-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-extras-rpms]
name = Red Hat Enterprise Linux 7 Server - Extras (RPMs) local
baseurl = http://10.10.50.2/rhel-7-server-extras-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-openstack-13-rpms]
name = Red Hat OpenStack Platform 13 for RHEL 7 (RPMs) local
baseurl = http://10.10.50.2/rhel-7-server-openstack-13-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-openstack-13-devtools-rpms]
name = Red Hat OpenStack Platform Dev Tools 13 for RHEL 7 (RPMs) local
baseurl = http://10.10.50.2/rhel-7-server-openstack-13-devtools-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-server-ansible-2.6-rpms]
name = Red Hat Ansible 2.6 for RHEL 7 (RPMs) local
baseurl = http://10.10.50.2/rhel-7-server-ansible-2.6-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-7-fast-datapath-rpms]
name = Red Hat Fast Datapath for RHEL 7 (RPMs) local
baseurl = http://10.10.50.2/rhel-7-fast-datapath-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-server-rhscl-7-rpms]
name = Red Hat Software collections 7 (RPMs) local
baseurl = http://10.10.50.2/rhel-server-rhscl-7-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[local-rhel-ha-for-rhel-7-server-rpms]
name = Red Hat HA for RHEL 7 (RPMs) local
baseurl = http://10.10.50.2/rhel-ha-for-rhel-7-server-rpms
enabled = 1
gpgcheck = 1
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF

export LIBGUESTFS_BACKEND=direct
qemu-img create -f qcow2 /var/lib/libvirt/images/${undercloud_name}.qcow2 100G
virt-resize --expand /dev/sda1 ${cloud_image} /var/lib/libvirt/images/${undercloud_name}.qcow2
virt-customize  -a /var/lib/libvirt/images/${undercloud_name}.qcow2 \
  --run-command 'xfs_growfs /' \
  --root-password password:${root_password} \
  --hostname ${undercloud_name}.${undercloud_suffix} \
  --run-command 'useradd stack' \
  --password stack:password:${stack_password} \
  --ssh-inject stack:file:$HOME/.ssh/id_rsa.pub \
  --run-command 'echo "stack ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/stack' \
  --chmod 0440:/etc/sudoers.d/stack \
  --run-command 'sed -i "s/dhcp/none/g"  /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'echo "IPADDR=10.10.50.10" >> /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'echo "PREFIX=24" >> /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'echo "GATEWAY=10.10.50.1" >> /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'echo "DNS1=8.8.8.8" >> /etc/sysconfig/network-scripts/ifcfg-eth0' \
  --run-command 'sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config' \
  --run-command 'systemctl enable sshd' \
  --run-command 'yum remove -y cloud-init' \
  --upload $HOME/local.repo:/etc/yum.repos.d/local.repo \
  --selinux-relabel

virt-install --name ${undercloud_name} \
  --disk /var/lib/libvirt/images/${undercloud_name}.qcow2 \
  --vcpus=${vcpus} \
  --ram=${vram} \
  --network bridge=br-mgmt,model=virtio \
  --network network=br0,model=virtio,portgroup=overcloud \
  --virt-type kvm \
  --import \
  --os-variant rhel7 \
  --graphics vnc \
  --serial pty \
  --noautoconsole \
  --console pty,target_type=virtio

virsh destroy ${undercloud_name}

#clone this vm for deploy undercloud 