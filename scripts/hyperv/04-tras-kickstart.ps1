<#
.SYNOPSIS
    Deja pg1, pg2 y pg3 listas tras la instalación con Kickstart.

.DESCRIPTION
    Saca la ISO del lector, desconecta el disco OEMDRV con el ks.cfg y enciende las VMs,
    que ya arrancan desde su disco.

.NOTES
    Requisitos: PowerShell como Administrador y las 3 VMs apagadas tras instalar.
    Los ficheros *-ks.vhdx quedan en E:\HyperV\VHD; se pueden borrar a mano.
#>

foreach ($n in 'pg1', 'pg2', 'pg3') {
    Set-VMDvdDrive -VMName $n -Path $null
    Get-VMHardDiskDrive -VMName $n | Where-Object Path -like '*-ks.vhdx' | Remove-VMHardDiskDrive
    Start-VM $n
}
