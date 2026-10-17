<#
.SYNOPSIS
    Crea la red interna del laboratorio en Hyper-V.

.DESCRIPTION
    Switch interno LabSwitch, IP 10.10.10.1/24 para Windows en ese switch
    y NAT para que las VMs (10.10.10.0/24) salgan a Internet.

.NOTES
    Requisitos: PowerShell como Administrador y Hyper-V activado.
    No es idempotente, ejecutar una sola vez. Para repetir, usar antes 01-red-borrar.ps1.
    Windows solo admite un NAT de este tipo: comprobar antes con Get-NetNat.
#>

# Switch interno: solo conecta Windows y las VMs, sin acceso directo a la red física
New-VMSwitch -Name LabSwitch -SwitchType Internal

# Windows hace de router: esta IP es la puerta de enlace de las VMs
New-NetIPAddress -InterfaceAlias "vEthernet (LabSwitch)" -IPAddress 10.10.10.1 -PrefixLength 24

# NAT: las VMs salen a Internet pero nadie de fuera puede entrar en ellas
New-NetNat -Name LabNAT -InternalIPInterfaceAddressPrefix 10.10.10.0/24
