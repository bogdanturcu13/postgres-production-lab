<#
.SYNOPSIS
    Deshace 01-red.ps1: borra el switch LabSwitch.

.DESCRIPTION
    Borra todos los switches llamados LabSwitch (Hyper-V permite duplicados)
    junto con su tarjeta vEthernet y la IP 10.10.10.1. No toca el Default Switch.

.NOTES
    Requisitos: PowerShell como Administrador y ninguna VM conectada a LabSwitch.
    El NAT no se borra; si hace falta: Remove-NetNat -Name LabNAT
#>

# -Force evita la confirmación por cada switch
Remove-VMSwitch -Name LabSwitch -Force
