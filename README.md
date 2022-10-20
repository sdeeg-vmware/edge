# Edge Projects

## Create virtual Cluster

1: Edge Cluster Creator - a script to create an embeded cluster to simulate an edge deployment on vSphere

VMs will be created and pinned to a specific host.  Available hosts will be polled for available memory and the 3 with the most available
will be chosen to deploy the VMs on.  VMs will be mounted to flash DAS for vSAN.

## Dependencies

My Environment:
4 physical hosts (3 needed)
vSphere 7
10Ge network
2 flash DAS available on each host


William Lam's magic ESXi image:  https://williamlam.com/nested-virtualization/nested-esxi-virtual-appliance

