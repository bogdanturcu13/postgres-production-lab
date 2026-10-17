# 01-red.ps1 - Red del laboratorio

# Switch interno: conecta Windows y las VMs
New-VMSwitch -Name LabSwitch -SwitchType Internal

# IP de Windows en ese switch: puerta de enlace de las VMs
New-NetIPAddress -InterfaceAlias "vEthernet (LabSwitch)" -IPAddress 10.10.10.1 -PrefixLength 24

# NAT: las VMs salen a Internet a traves de Windows
New-NetNat -Name LabNAT -InternalIPInterfaceAddressPrefix 10.10.10.0/24
