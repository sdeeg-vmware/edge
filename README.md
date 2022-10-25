# Edge Projects

Warning: perpetually Alpha (or worse) quality code within

## Edge Cluster Creator

A set of Powershell/PowerCLI scripts to create, configure, delete a virtual ESXi cluster to simulate an edge deployment on vSphere.

### The Inspiration 
I began with the script from William Lam and started hacking from there.  I appologize for the uglyness, I don't really know anything
about programming in Powershell and am just winging it.  Also, as of now you have to use the special OVA from William.

William Lam's magic ESXi image:  https://williamlam.com/nested-virtualization/nested-esxi-virtual-appliance

### Optimized for (my) Edge

VMs will be created and pinned to a specific host.  Available hosts will be polled for available memory and the 3 with the most available
will be chosen to deploy the VMs on.  VMs will be mounted to flash DAS for vSAN.

## Dependencies

My Environment:
4 physical hosts (3 needed)
vSphere 7
10Ge network
1 flash drive as main drive
2 flash DAS available on each host for vSAN
