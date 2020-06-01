#!/bin/bash
VM_NAMES="rhel7"
OVS_BRIGES="br-0"
LINUX_BRIGES="br-mgmt br-data"

# Cleanup VMs
for vm_name in $VM_NAMES; do
    virsh destroy $vm_name
    virsh undefine $vm_name
    rm -rf /var/lib/libvirt/images/$vm_name.qcow2
done

# Cleanup briges
for bridge in $OVS_BRIGES; do
    virsh net-destroy $bridge
    virsh net-undefine $bridge
    ovs-vsctl del-br $bridge
done

for bridge in $LINUX_BRIGES; do
    ip link set $bridge down
    brctl delbr $bridge
done
