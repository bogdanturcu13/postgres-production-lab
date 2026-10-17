<#
.SYNOPSIS
    Crea las 4 VMs del laboratorio en Hyper-V.

.DESCRIPTION
    infra, pg1, pg2 y pg3: generación 2, 2 vCPU, RAM fija, disco de sistema de 20 GB
    y disco de datos aparte. Arrancan desde la ISO de Rocky Linux 9.

.NOTES
    Requisitos: PowerShell como Administrador y LabSwitch creado (01-red.ps1).
    No es idempotente: ejecutar una sola vez. Para repetir, borrar antes las VMs.
#>

$iso = 'E:\HyperV\ISO\Rocky-9.8-x86_64-minimal.iso'

foreach ($n in 'infra', 'pg1', 'pg2', 'pg3') {
    # Generación 2 = UEFI y arranque seguro, como un servidor actual
    New-VM $n -Generation 2 -MemoryStartupBytes 3GB -SwitchName LabSwitch -NewVHDPath "E:\HyperV\VHD\$n.vhdx" -NewVHDSizeBytes 20GB

    # RAM fija: PostgreSQL se ajusta a la memoria que ve, no debe cambiar en caliente
    Set-VM $n -ProcessorCount 2 -StaticMemory -AutomaticCheckpointsEnabled $false

    # Datos en un disco aparte: si se llena, no tumba el sistema operativo
    New-VHD "E:\HyperV\VHD\$n-datos.vhdx" -SizeBytes 20GB
    Add-VMHardDiskDrive $n -Path "E:\HyperV\VHD\$n-datos.vhdx"

    # La plantilla por defecto solo arranca Windows; esta acepta Linux
    Add-VMDvdDrive $n -Path $iso
    Set-VMFirmware $n -SecureBootTemplate MicrosoftUEFICertificateAuthority -FirstBootDevice (Get-VMDvdDrive $n)
}

# infra aloja más servicios (MinIO, Prometheus...): más RAM y más disco de datos
Set-VM infra -MemoryStartupBytes 4GB
Resize-VHD E:\HyperV\VHD\infra-datos.vhdx -SizeBytes 40GB