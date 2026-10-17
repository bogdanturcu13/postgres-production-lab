# Apuntes del laboratorio

## Resumen

Este proyecto es un laboratorio personal para aprender a administrar PostgreSQL como se hace en producción. La idea es montar un entorno parecido al de una empresa, operarlo día a día y romperlo a propósito para aprender a diagnosticar y arreglar los problemas, igual que haría un DBA o un SRE.

El laboratorio son 4 máquinas virtuales con Rocky Linux 9 en Hyper-V: tres nodos de base de datos (pg1, pg2 y pg3) con PostgreSQL 16, Patroni y etcd, y una VM de infraestructura (infra) con HAProxy, PgBouncer, pgBackRest con MinIO, Prometheus, Alertmanager, Grafana y Ansible.

Objetivos:

- Instalar, configurar y mantener PostgreSQL en producción.
- Montar alta disponibilidad con Patroni y etcd, y probar failovers reales.
- Configurar replicación física (streaming) y lógica.
- Hacer backups, restauraciones y recuperación ante desastres (PITR, RTO/RPO) con pgBackRest.
- Monitorizar el clúster, analizar consultas lentas y planificar la capacidad.
- Hacer el mantenimiento: VACUUM, ANALYZE, REINDEX, bloat y autovacuum.
- Aplicar parches y actualizaciones de versión (16 → 18) siguiendo un proceso de cambios.
- Resolver incidencias, analizar la causa raíz y escribir postmortems siguiendo ITIL.
- Automatizar todo con Bash y Ansible, hasta poder destruir el laboratorio y reconstruirlo desde cero.

El trabajo está dividido en 10 fases (de la 0 a la 9). Cada una tiene un ejercicio de rotura y un entregable en este repositorio: scripts, runbooks, postmortems y documentación. Estos apuntes recogen lo que voy haciendo bloque a bloque, los problemas que me encuentro y cómo los soluciono.

## FASE 0: Preparación del entorno

### BLOQUE 0: Repositorio y equipo

- Equipo: i5-11400H (6 núcleos / 12 hilos), 32 GB de RAM, Windows 11 Pro, disco E: con 484 GB libres.
- Hipervisor elegido: Hyper-V (ver [ADR 0001](decisiones/0001-hipervisor-hyper-v.md)).
- Sistema operativo de las VMs: Rocky Linux 9 (ver [ADR 0002](decisiones/0002-sistema-operativo-rocky-linux-9.md)).

**Problema:** al hacer `git push` daba error 403 porque Git se autenticaba con la cuenta de la universidad (credenciales guardadas en el Administrador de credenciales de Windows).

**Solución:** usar SSH con una clave y un alias por cuenta (`github-personal` / `github-uni`) e identidad de commits por carpeta con `includeIf` y `user.useConfigOnly`.

### BLOQUE 1: Configuración de Hyper-V

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

### BLOQUE 2: Red interna con NAT

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

#### Problemas y soluciones

- **`New-VMSwitch` falló con `0x800700B7` ("No se puede crear un archivo que ya existe")**, sin que existiera ningún switch ni adaptador `LabSwitch`. Como consecuencia, `New-NetIPAddress` también falló (no existía la tarjeta `vEthernet (LabSwitch)`); el NAT sí se creó. Al reintentar `New-VMSwitch` se creó bien: fue un error puntual al registrar el adaptador virtual. Posibles factores: restos de un adaptador Hyper-V antiguo (`Hyper-V Virtual Ethernet Adapter #2`) y drivers de VPN (Fortinet, Hamachi) en estado `Error`.
- **Al reintentar se crearon dos switches `LabSwitch`**: Hyper-V permite nombres duplicados porque internamente identifica cada switch por su Id. Solución: `Remove-VMSwitch -Name LabSwitch -Force` (script `01-red-borrar.ps1`), crear uno solo y asignar la IP.
- **Lección:** los scripts sencillos no son idempotentes; antes de repetir un comando hay que comprobar el estado con `Get-VMSwitch`, `Get-NetNat` y `Get-NetIPAddress`.

### BLOQUE 3: Crear las 4 VMs

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

Name  ProcessorCount RAM_GB DynamicMemoryEnabled
----  -------------- ------ --------------------
infra              2      4                False
pg1                2      3                False
pg2                2      3                False
pg3                2      3                False

# Mostrar los 8 discos con su tamaño máximo
Get-VMHardDiskDrive -VMName * | Get-VHD | Select-Object Path, @{n='GB';e={$_.Size/1GB}}

Path                           GB
----                           --
E:\HyperV\VHD\pg1.vhdx         20
E:\HyperV\VHD\pg1-datos.vhdx   20
E:\HyperV\VHD\infra.vhdx       20
E:\HyperV\VHD\infra-datos.vhdx 40
E:\HyperV\VHD\pg3.vhdx         20
E:\HyperV\VHD\pg3-datos.vhdx   20
E:\HyperV\VHD\pg2.vhdx         20
E:\HyperV\VHD\pg2-datos.vhdx   20

# Confirmar que todas las VMs tienen configurado el arranque seguro para Linux
Get-VMFirmware -VMName * | Select-Object VMName, SecureBootTemplate
```

Name  ProcessorCount RAM_GB DynamicMemoryEnabled
----  -------------- ------ --------------------
infra              2      4                False
pg1                2      3                False
pg2                2      3                False
pg3                2      3                False

Los discos son dinámicos: en la salida de `New-VHD`, `Size` es 20 GB pero `FileSize` es solo 4 MB, porque en E: solo ocupan lo que contienen.

### BLOQUE 4: Instalar Rocky Linux en la VM infra

Primero voy a realizar una instalación a mano para comprender realmente qué se hace y por qué se hace. Las otras 3 VM las automatizaré ya que será el mismo proceso cambiando el nombre y la IP.

Algunas consideraciones generales: la cuenta de root tendrá contraseña solo para emergencias, pero no se podrá entrar como root por SSH (el día a día se hace con mi usuario y sudo, como en producción); se instala solamente en el disco del sistema, no en el de datos; las VMs tienen IP fija, no hay DHCP.

Paso 1: Encender la VM y abrir su consola

Se hace desde PowerShell como Admin con los comandos:

- `Start-VM infra`: enciende la VM, que arranca desde la ISO.
- `vmconnect localhost infra`: abre una ventana con la pantalla de la VM, como si tuviese un monitor conectado.

Paso 2: Instalador de Rocky

En el menú de arranque elijo "Install Rocky Linux 9.8" y voy eligiendo las opciones:

- Idioma: English (United States). En servidores se suele usar inglés porque los mensajes de error se buscan mejor en Internet.
- Teclado: español.
- Installation Destination: marco solo el disco de 20 GiB (sda), el de 40 GiB (sdb) lo dejo sin marcar porque es el de datos. Particionado automático.
- Network & Host Name: nombre `infra`, IPv4 en manual con IP 10.10.10.10, máscara 24, puerta de enlace 10.10.10.1 (mi Windows) y DNS 1.1.1.1 y 8.8.8.8. Hay que activar el interruptor de la tarjeta para que salga Connected.
- Time & Date: Europe/Madrid con la hora de red activada.
- Software Selection: Minimal Install.
- Root Password: le pongo contraseña y dejo SIN marcar "Allow root SSH login with password".
- User Creation: usuario `bogdan` con "Make this user administrator" marcado, para que pueda usar sudo (lo mete en el grupo wheel).

¿Por qué no bloquear root del todo? Si lo bloqueo, nadie puede iniciar sesión como root, pero si algún día el sistema no arranca y entra en modo de emergencia, este pide la contraseña de root y no podría entrar; tendría que arrancar desde la ISO para recuperarlo. Con contraseña pero sin SSH tengo las dos cosas: nadie entra como root desde la red y puedo usar el modo de emergencia si hace falta.

Durante la instalación me salió un aviso sobre SMT (Hyper-Threading): tiene vulnerabilidades conocidas (Spectre, MDS...) y Red Hat avisa por si quieres desactivarlo. En mi caso no hace falta, las VMs solo ejecutan mi código y el kernel ya trae las mitigaciones activadas. Esto solo se plantea en entornos como nubes públicas donde varios clientes comparten hardware.

Paso 3: Quitar la ISO

Al terminar se pulsa Reboot System, esperas a que se reinicie y sacas la ISO del lector para que no vuelva a arrancar el instalador:

```powershell
Set-VMDvdDrive -VMName infra -Path $null
```

Problema: yo la quité MIENTRAS la VM se estaba apagando y salieron un montón de errores (`I/O error, dev sr0`, `SQUASHFS error`, `Failed to execute shutdown binary`) y la VM se quedó colgada. El motivo es que el instalador se ejecuta desde la propia ISO, así que al quitarla no podía leer sus propios ficheros para terminar de apagarse. La instalación en sí había terminado bien.

Solución: comprobar que el lector está vacío con `Get-VMDvdDrive -VMName infra | Select-Object VMName, Path`, apagarla a lo bruto con `Stop-VM infra -TurnOff` (equivale a quitarle la corriente, aquí no se pierde nada porque estaba colgada) y volver a encenderla con `Start-VM infra`.

Para las siguientes VMs: primero Reboot System, esperar a que se reinicie y luego quitar la ISO.

Paso 4: Comprobar que todo funciona

Dentro de la VM, con mi usuario:

- `ip -br a`: muestra las tarjetas de red. Me sale `eth0` en `UP` con `10.10.10.10/24`.
- `ping google.com`: responde, así que funcionan a la vez la puerta de enlace, la NAT y el DNS.
- `lsblk`: lista los discos. `sda` tiene el sistema (`/boot/efi`, `/boot` y LVM con `/` y la swap) y `sdb` (40 GB) está vacío, que es lo que quería. `sr0` es el lector de DVD, ya sin la ISO.

El instalador ha creado 2 GB de swap. En servidores de bases de datos la swap se deja pequeña porque si PostgreSQL empieza a usarla el rendimiento se hunde. Lo revisaré en la Fase 1.

Paso 5: Acceso SSH por clave desde Windows

En vez de entrar con contraseña se usa un par de claves: la privada se queda en mi PC y la pública se copia a cada servidor. Es más seguro y además es lo que necesitará Ansible para conectarse solo a las VMs.

1. Primero pruebo que entro por SSH con contraseña: `ssh bogdan@10.10.10.10` (la primera vez pregunta si me fío de la huella del servidor, se responde `yes`).

2. Creo una clave solo para el laboratorio, para no mezclarla con las de GitHub:

```powershell
ssh-keygen -t ed25519 -f $HOME\.ssh\id_ed25519_lab -C "bogdan@lab"
```

3. Copio la clave pública a infra:

```powershell
type $HOME\.ssh\id_ed25519_lab.pub | ssh bogdan@10.10.10.10 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && restorecon -R ~/.ssh"
```

`type` lee la clave y se la pasa por SSH a la VM, que crea la carpeta `~/.ssh` (solo accesible por mí), añade la clave a `authorized_keys` y con `restorecon` le pone la etiqueta de SELinux correcta. Sin esa etiqueta SELinux podría impedir que el servicio SSH lea las claves aunque los permisos estén bien.

4. Añado un alias al final de `$HOME\.ssh\config` para no tener que escribir la IP:

```
Host infra
    HostName 10.10.10.10
    User bogdan
    IdentityFile ~/.ssh/id_ed25519_lab
```

Para comprobarlo usé `ssh infra` y efectivamente, entra a la máquina sin pedir contraseña de forma muy cómoda, y dentro `sudo whoami` devuelve `root`, así que mi usuario puede administrar.

### BLOQUE 5: Instalación automática de pg1, pg2 y pg3 con Kickstart

En vez de repetir a mano la instalación tres veces he usado Kickstart, que es la forma estándar de instalar servidores RHEL/Rocky en serie. Es un fichero de texto (`ks.cfg`) con todas las respuestas del instalador: idioma, disco, red, usuarios, paquetes... Si el instalador lo encuentra, instala solo sin preguntar nada.

Para que lo encuentre sin tener que tocar el menú de arranque, lo meto en un disco pequeño con la etiqueta `OEMDRV`. El instalador de Rocky busca automáticamente un `ks.cfg` en cualquier disco que se llame así.

El Kickstart tiene lo mismo que elegí en infra (inglés, teclado español, Europe/Madrid, solo el disco sda, Minimal Install, root con contraseña y usuario bogdan en wheel) cambiando el nombre y la IP de cada VM. Además he añadido:

- `sshkey`: mete directamente mi clave pública en el usuario bogdan, así que no hace falta copiarla a mano como en infra.
- `selinux --enforcing` y `firewall --enabled --service=ssh`: SELinux activo y el firewall solo con SSH abierto.
- `poweroff`: la VM se apaga sola al terminar. Si se reiniciara volvería a arrancar desde la ISO y, con el disco OEMDRV puesto, se reinstalaría otra vez.

Antes de usarlo comprobé la sintaxis con `ksvalidator -v RHEL9 ks.cfg`, que es la herramienta oficial de Red Hat (paquete pykickstart).

Paso 1: Preparar los discos Kickstart

El script `scripts/hyperv/03-kickstart.ps1` (PowerShell como Admin) genera el `ks.cfg` de cada VM, crea un disco de 100 MB en FAT32 con la etiqueta OEMDRV (`New-VHD`, `Mount-VHD`, `Initialize-Disk`, `New-Partition` y `Format-Volume` encadenados), copia el `ks.cfg` dentro, lo desmonta y se lo conecta a la VM con `Add-VMHardDiskDrive`.

Las contraseñas de root y bogdan las pide el script al ejecutarlo con `Read-Host`, así no quedan escritas en el repo. Otro detalle: el `ks.cfg` se escribe quitando los saltos de línea de Windows (CRLF), porque Linux espera LF.

Paso 2: Lanzar las tres instalaciones a la vez

- `Start-VM pg1, pg2, pg3`: enciende las tres VMs.
- `vmconnect localhost pg1`: abre la consola para ver cómo va (lo mismo con pg2 y pg3).

En el menú de arranque de cada una elijo "Install Rocky Linux 9.8". Si no se toca nada, a los 60 segundos arranca la opción por defecto, que primero comprueba la ISO y luego instala igual. A partir de ahí la instalación va sola en modo texto y cada VM se apaga al terminar.

Paso 3: Quitar el instalador y arrancar

Cuando las tres están apagadas (`Get-VM` las muestra en `Off`) ejecuto `scripts/hyperv/04-tras-kickstart.ps1`, que les quita la ISO y el disco OEMDRV y las enciende ya desde su disco.

Paso 4: Alias SSH

Añado los nodos a `$HOME\.ssh\config`. El último bloque aplica el mismo usuario y la misma clave a las cuatro VMs para no repetirlo:

```
Host pg1
    HostName 10.10.10.11
Host pg2
    HostName 10.10.10.12
Host pg3
    HostName 10.10.10.13

Host infra pg1 pg2 pg3
    User bogdan
    IdentityFile ~/.ssh/id_ed25519_lab
```

Paso 5: Comprobar que todo funciona

Desde Windows, para cada nodo:

```powershell
ssh pg1 "hostname; ip -br a show eth0; lsblk -d; sudo -n true 2>&1 | head -1"
```

En los tres sale bien: el nombre correcto, `eth0` en `UP` con su IP (10.10.10.11, .12 y .13), solo los discos `sda` y `sdb` (el de Kickstart ya no está) y `sudo: a password is required`, que significa que tengo sudo pero me pide la contraseña, que es lo correcto. Y he entrado sin contraseña gracias a la clave que metió el Kickstart.

La primera vez que entras SSH pregunta si te fías de la huella del servidor. Se guarda en `known_hosts` y si algún día cambia avisa, que es la forma de detectar que alguien se está haciendo pasar por el servidor.

Hay una diferencia con producción real, y es que el instalador guarda una copia del Kickstart original en `/root/original-ks.cfg` con las contraseñas en claro. En producción las contraseñas irían cifradas (`rootpw --iscrypted`) y ese fichero se borraría después de instalar.

### BLOQUE 6: Actualizar las VMs y conectarlas entre sí

infra va a ser el nodo de control de Ansible, es decir, desde ahí se configurarán las demás VMs. Para eso necesita conocer a pg1, pg2 y pg3 por su nombre y poder entrar en ellas por SSH con clave. Antes de nada he actualizado las cuatro, que es lo primero que se hace en cualquier servidor recién instalado: la ISO tiene ya unas semanas y desde entonces han salido parches de seguridad.

Paso 1: Actualizar las 4 VMs

Desde Windows con un bucle que entra en cada VM, instala todas las actualizaciones y la reinicia para que cargue el kernel nuevo:

```powershell
foreach ($h in 'infra', 'pg1', 'pg2', 'pg3') { ssh -t $h "sudo dnf -y update && sudo reboot" }
```

El `-t` hace falta para que sudo pueda pedirme la contraseña (una vez por VM) y el `-y` responde que sí a la instalación. Al reiniciar se corta la conexión con un "Connection closed", que es normal.

Paso 2: Que se conozcan por nombre

Añado las 4 VMs al `/etc/hosts` de cada una, que es como la agenda local de nombres de Linux. Así puedo usar `pg1` en vez de la IP sin necesidad de un servidor DNS:

```powershell
foreach ($h in 'infra', 'pg1', 'pg2', 'pg3') { ssh -t $h "printf '10.10.10.10 infra\n10.10.10.11 pg1\n10.10.10.12 pg2\n10.10.10.13 pg3\n' | sudo tee -a /etc/hosts" }
```

`tee -a` añade las líneas al final del fichero con permisos de root. Ojo, hay que ejecutarlo una sola vez o se duplican las líneas. En producción esto lo resolvería un DNS interno.

Paso 3: Clave SSH de infra hacia los nodos

Dentro de infra creo su propio par de claves, sin passphrase (`-N ""`) porque Ansible tiene que poder usarlas sin que nadie escriba nada:

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
```

Y copio la clave pública a cada nodo con `ssh-copy-id`, que hace lo mismo que hice a mano desde Windows en el bloque 4 (crear `~/.ssh`, añadir la clave a `authorized_keys`, permisos y SELinux) pero de una vez. En cada nodo pide `yes` para la huella y la contraseña de bogdan:

```bash
for h in pg1 pg2 pg3; do ssh-copy-id $h; done
```

Paso 4: Comprobar que todo funciona

Desde infra:

- `for h in pg1 pg2 pg3; do ssh $h "hostname; uname -r"; done`: entra en cada nodo sin contraseña y me devuelve `pg1`, `pg2` y `pg3`, los tres con el mismo kernel ya actualizado (`5.14.0-687.58.1.el9_8.x86_64`).
- `ping -c 1 pg1` (y pg2, pg3): responden, así que la resolución por nombre del `/etc/hosts` funciona.

Algo que me ha llamado la atención: las huellas que me enseñó infra al conectar con pg1, pg2 y pg3 son las mismas que vi antes desde Windows. Eso confirma que en los dos casos hablé con el mismo servidor, que es justo para lo que sirven las huellas.

Con esto queda cerrada la Fase 0: las 4 VMs creadas con Rocky 9.8, red con IPs fijas y NAT, acceso SSH por clave desde Windows a todas y desde infra a los nodos, y el repo con su estructura.
