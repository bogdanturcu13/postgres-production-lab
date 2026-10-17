# Apuntes del laboratorio

## BLOQUE 0: Repositorio y equipo

- Equipo: i5-11400H (6 núcleos / 12 hilos), 32 GB de RAM, Windows 11 Pro, disco E: con 484 GB libres.
- Hipervisor elegido: Hyper-V (ver [ADR 0001](decisiones/0001-hipervisor-hyper-v.md)).
- Sistema operativo de las VMs: Rocky Linux 9 (ver [ADR 0002](decisiones/0002-sistema-operativo-rocky-linux-9.md)).

**Problema:** al hacer `git push` daba error 403 porque Git se autenticaba con la cuenta de la universidad (credenciales guardadas en el Administrador de credenciales de Windows).

**Solución:** usar SSH con una clave y un alias por cuenta (`github-personal` / `github-uni`) e identidad de commits por carpeta con `includeIf` y `user.useConfigOnly`.

## BLOQUE 1: Configuración de Hyper-V

- Hyper-V: es un hipervisor de tipo 1 o bare metal, es decir, se ejecuta directamente sobre el hardware físico del ordenador y actúa como si fuese el sistema operativo. Al activarlo y reiniciar el ordenador es Hyper-V el que se inicia primero sobre el hardware, y luego Windows 11 sobre él, dando la ilusión de que seguimos usando Windows 11 nativo cuando en realidad es solamente una VM privilegiada (la partición raíz).

Para activar Hyper-V y llevar todas las máquinas virtuales a mi disco E: (que es el que más espacio disponible tiene) he seguido estos pasos:

1. Ejecutar estos comandos en PowerShell como admin:

   ```powershell
   # Qué tipo de disco es E: (SSD/HDD, interno/USB)
   Get-Partition -DriveLetter E | Get-Disk | Select-Object FriendlyName, BusType
   Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType

   # Activar Hyper-V
   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
   ```

   En mi caso devolvió `RestartNeeded : False` porque Hyper-V ya estaba activado. Lo comprobé con `(Get-CimInstance Win32_ComputerSystem).HypervisorPresent`, que devolvió `True` (el hipervisor está en marcha), así que no hizo falta reiniciar.

   El disco E: es un **NVMe Crucial P2 (CT1000P2SSD8)**, un SSD sin DRAM: en escrituras largas y sostenidas baja bastante su velocidad. Hay que tenerlo en cuenta al interpretar métricas de disco (checkpoints, replicación síncrona) en la Fase 5.

2. Comprobar el estado y mover las rutas por defecto de Hyper-V a E:

   ```powershell
   Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V | Select-Object State

   New-Item -ItemType Directory -Path E:\HyperV\VHD, E:\HyperV\VMs, E:\HyperV\ISO -Force
   Set-VMHost -VirtualHardDiskPath 'E:\HyperV\VHD' -VirtualMachinePath 'E:\HyperV\VMs'
   Get-VMHost | Select-Object VirtualHardDiskPath, VirtualMachinePath
   ```

3. Descargar la ISO de Rocky Linux 9 para las máquinas, versión minimal, desde https://rockylinux.org/download (en mi caso `Rocky-9.8-x86_64-minimal.iso`).

## BLOQUE 2: Red interna con NAT

Vamos a crear un switch virtual (que actúa como un switch físico) al que vamos a conectar las 4 máquinas virtuales y mi propia máquina Windows, que servirá como router con NAT hacia mi red real. De esta manera la IP de las máquinas será siempre fija y no depende de dónde esté. Tampoco habrá DHCP: cada máquina tendrá su IP configurada a mano.

El script `scripts/hyperv/01-red.ps1` crea el switch virtual con `New-VMSwitch`, configura la IP de Windows (10.10.10.1/24) en dicho switch con `New-NetIPAddress` y configura una NAT para la red 10.10.10.0/24 con `New-NetNat`.

Para comprobar que se ha creado correctamente podemos ejecutar `Get-NetNat` y observar la salida. En este caso mi ejecución ha sido exitosa:

```
Name                             : LabNAT
ExternalIPInterfaceAddressPrefix :
InternalIPInterfaceAddressPrefix : 10.10.10.0/24
IcmpQueryTimeout                 : 30
TcpEstablishedConnectionTimeout  : 1800
TcpTransientConnectionTimeout    : 120
TcpFilteringBehavior             : AddressDependentFiltering
UdpFilteringBehavior             : AddressDependentFiltering
UdpIdleSessionTimeout            : 120
UdpInboundRefresh                : False
Store                            : Local
Active                           : True
```

También podemos testear la conexión con la máquina Windows con el comando `Test-Connection 10.10.10.1`:

```
PS C:\dev\personal\postgres-production-lab\scripts\hyperv> Test-Connection 10.10.10.1

Source        Destination     IPV4Address      IPV6Address                              Bytes
------        -----------     -----------      -----------                              -----
ASUS-TUF      10.10.10.1      192.168.1.131    fe80::6b2d:dbab:15a0:4eb0%78             32
ASUS-TUF      10.10.10.1      192.168.1.131    fe80::6b2d:dbab:15a0:4eb0%78             32
ASUS-TUF      10.10.10.1      192.168.1.131    fe80::6b2d:dbab:15a0:4eb0%78             32
ASUS-TUF      10.10.10.1      192.168.1.131    fe80::6b2d:dbab:15a0:4eb0%78             32
```

En PowerShell 5.1, la columna `IPV4Address` muestra la IP de **origen** (la de mi red real), no la de destino. Lo importante es que hay respuesta.

### Problemas y soluciones

- **`New-VMSwitch` falló con `0x800700B7` ("No se puede crear un archivo que ya existe")**, sin que existiera ningún switch ni adaptador `LabSwitch`. Como consecuencia, `New-NetIPAddress` también falló (no existía la tarjeta `vEthernet (LabSwitch)`); el NAT sí se creó. Al reintentar `New-VMSwitch` se creó bien: fue un error puntual al registrar el adaptador virtual. Posibles factores: restos de un adaptador Hyper-V antiguo (`Hyper-V Virtual Ethernet Adapter #2`) y drivers de VPN (Fortinet, Hamachi) en estado `Error`.
- **Al reintentar se crearon dos switches `LabSwitch`**: Hyper-V permite nombres duplicados porque internamente identifica cada switch por su Id. Solución: `Remove-VMSwitch -Name LabSwitch -Force` (script `01-red-borrar.ps1`), crear uno solo y asignar la IP.
- **Lección:** los scripts sencillos no son idempotentes; antes de repetir un comando hay que comprobar el estado con `Get-VMSwitch`, `Get-NetNat` y `Get-NetIPAddress`.

## BLOQUE 3: Crear las 4 VMs

Para la automatización de la creación de las máquinas virtuales (script `scripts/hyperv/02-vms.ps1`) se han usado varios comandos:

- `New-VM`: crea una nueva máquina virtual de generación 2 (UEFI). Se conecta al switch virtual LabSwitch mediante el parámetro `-SwitchName` y se crea el disco que contendrá el sistema con el parámetro `-NewVHDPath`.
- `Set-VM`: modifica la configuración de la máquina virtual, por ejemplo para especificar la cantidad de núcleos, si tendrá memoria RAM fija asignada, etc.
- `New-VHD`: crea un nuevo disco (el que será el disco de datos de la VM) de 20 GB de tamaño.
- `Add-VMHardDiskDrive`: acopla el nuevo disco de datos a una máquina virtual, que se especifica mediante `-VMName` o directamente con `$n` si en el script tienes como variable el nombre de la máquina. El parámetro `-Path` indica qué disco acoplar a dicha máquina.
- `Add-VMDvdDrive`: equivale a meter un USB con el SO para instalarlo en el disco de la máquina. Añade a la VM un lector de DVD virtual con la ISO.
- `Set-VMFirmware`: configura el firmware UEFI de la VM (el equivalente a su BIOS): la plantilla de arranque seguro (`-SecureBootTemplate`) y el dispositivo de arranque (`-FirstBootDevice`) para que arranque desde el DVD (la ISO en este caso). La plantilla por defecto solo acepta cargadores de Windows; `MicrosoftUEFICertificateAuthority` permite arrancar Linux.
- `Resize-VHD`: amplía el disco de datos de `infra` a 40 GB (además, `Set-VM` le sube la RAM a 4 GB).

Por qué se ha configurado así:

- **Dos discos por VM (sistema y datos):** si el disco de datos se llena (por ejemplo, con WAL en la Fase 2), PostgreSQL se para pero el sistema sigue vivo y se puede entrar por SSH a arreglarlo. Además, el disco de datos puede crecer por separado.
- **RAM fija:** PostgreSQL dimensiona su memoria según la RAM que ve; si Hyper-V se la cambia en caliente, el ajuste deja de tener sentido.
- **`infra` con más RAM y disco:** aloja más servicios (MinIO, Prometheus, Grafana...) y guarda los backups y las métricas.

| VM    | vCPU | RAM  | Disco sistema | Disco datos |
|-------|------|------|---------------|-------------|
| infra | 2    | 4 GB | 20 GB         | 40 GB       |
| pg1   | 2    | 3 GB | 20 GB         | 20 GB       |
| pg2   | 2    | 3 GB | 20 GB         | 20 GB       |
| pg3   | 2    | 3 GB | 20 GB         | 20 GB       |

Tras ejecutar el script podemos ejecutar algunos comandos para asegurarnos de que todo ha ido bien (aparte de ver la salida del propio script `02-vms.ps1`):

```powershell
# Listar las 4 VMs con sus CPUs, su RAM en GB y si tienen memoria dinámica
Get-VM | Select-Object Name, ProcessorCount, @{n='RAM_GB';e={$_.MemoryStartup/1GB}}, DynamicMemoryEnabled

# Mostrar los 8 discos con su tamaño máximo
Get-VMHardDiskDrive -VMName * | Get-VHD | Select-Object Path, @{n='GB';e={$_.Size/1GB}}

# Confirmar que todas las VMs tienen configurado el arranque seguro para Linux
Get-VMFirmware -VMName * | Select-Object VMName, SecureBootTemplate
```

Los discos son dinámicos: en la salida de `New-VHD`, `Size` es 20 GB pero `FileSize` es solo 4 MB, porque en E: solo ocupan lo que contienen.
