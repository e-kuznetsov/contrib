#!/bin/bash
VM_NAMES="contrail-controller controller compute"
OVS_BRIGES="br0 br1 br-ext"

# Cleanup VMs
for vm_name in $VM_NAMES; do
    vbmc stop $vm_name
    vbmc delete $vm_name
    virsh destroy $vm_name
    virsh undefine $vm_name
    rm -rf /var/lib/libvirt/images/$vm_name.qcow2
done
rm -f vm_list

# Cleanup briges
for bridge in $OVS_BRIGES; do
    virsh net-destroy $bridge
    virsh net-undefine $bridge
    ovs-vsctl del-br $bridge
done
