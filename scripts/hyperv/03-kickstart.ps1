<#
.SYNOPSIS
    Prepara la instalación automática (Kickstart) de pg1, pg2 y pg3.

.DESCRIPTION
    Para cada VM crea un disco pequeño con la etiqueta OEMDRV que contiene un ks.cfg
    con su nombre e IP, y se lo conecta. Al arrancar desde la ISO, el instalador de
    Rocky encuentra ese ks.cfg solo y hace la instalación sin preguntar nada.
    La VM se apaga sola al terminar.

.NOTES
    Requisitos: PowerShell como Administrador, VMs creadas (02-vms.ps1) y la clave
    $HOME\.ssh\id_ed25519_lab.pub creada.
    Las contraseñas se piden al ejecutar: no se guardan en el repo.
#>

$rootPass = Read-Host "Contraseña de root"
$userPass = Read-Host "Contraseña de bogdan"
$sshKey   = Get-Content "$HOME\.ssh\id_ed25519_lab.pub"

$ips = @{ pg1 = '10.10.10.11'; pg2 = '10.10.10.12'; pg3 = '10.10.10.13' }

foreach ($n in $ips.Keys) {
    # Mismas respuestas que en la instalación manual de infra, cambiando nombre e IP
    $ks = @"
text
lang en_US.UTF-8
keyboard es
timezone Europe/Madrid --utc
network --bootproto=static --device=eth0 --ip=$($ips[$n]) --netmask=255.255.255.0 --gateway=10.10.10.1 --nameserver=1.1.1.1,8.8.8.8 --hostname=$n --activate
ignoredisk --only-use=sda
clearpart --all --initlabel --drives=sda
autopart
bootloader --boot-drive=sda
rootpw --plaintext $rootPass
user --name=bogdan --groups=wheel --plaintext --password=$userPass
sshkey --username=bogdan "$sshKey"
selinux --enforcing
firewall --enabled --service=ssh
firstboot --disable
poweroff

%packages
@^minimal-environment
%end
"@

    # Disco de 100 MB en FAT32 con la etiqueta OEMDRV, que es la que busca el instalador
    $vhd = "E:\HyperV\VHD\$n-ks.vhdx"
    $vol = New-VHD $vhd -SizeBytes 100MB | Mount-VHD -Passthru | Initialize-Disk -PartitionStyle MBR -Passthru |
           New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem FAT32 -NewFileSystemLabel OEMDRV -Confirm:$false

    # Linux espera finales de línea LF: se quitan los CR de Windows
    [IO.File]::WriteAllText("$($vol.DriveLetter):\ks.cfg", ($ks -replace "`r", ""))

    Dismount-VHD $vhd
    Add-VMHardDiskDrive $n -Path $vhd
}
