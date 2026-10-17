# Preguntas de repaso

Preguntas tipo entrevista de cada fase. Las respuestas están plegadas para poder intentar contestar antes de mirarlas: en GitHub se despliegan pulsando en "Respuesta".

## FASE 0: Preparación del entorno

### 1. ¿Por qué se separan los datos de PostgreSQL en un disco distinto al del sistema operativo?

<details>
<summary>Respuesta</summary>

- **Aislamiento ante el llenado:** si los datos o el WAL llenan el disco, PostgreSQL se para pero el sistema operativo sigue funcionando y se puede entrar por SSH a arreglarlo. Con un solo disco, el sistema también se queda sin espacio y puede que ni se pueda entrar.
- **Crecimiento independiente:** se amplía solo el disco de datos cuando la base de datos crece, sin tocar el del sistema.
- **Rendimiento:** se pueden poner los datos (o el WAL) en discos más rápidos y separar su E/S de la del sistema. En producción es habitual incluso un tercer disco solo para el WAL.
- **Independencia:** se puede reinstalar el sistema operativo sin tocar los datos, o mover el disco de datos a otra máquina.

No es un motivo de seguridad: los permisos van por usuario y fichero, no por disco.
</details>

### 2. ¿Qué diferencia hay entre un hipervisor de tipo 1 y uno de tipo 2? ¿De qué tipo es Hyper-V y por qué puede parecer que no lo es?

<details>
<summary>Respuesta</summary>

- **Tipo 1 (bare metal):** se ejecuta directamente sobre el hardware. Ejemplos: Hyper-V, VMware ESXi, Xen, KVM.
- **Tipo 2 (hosted):** se ejecuta como una aplicación dentro de un sistema operativo. Ejemplos: VirtualBox, VMware Workstation.

Hyper-V es de tipo 1. Parece de tipo 2 porque se activa desde Windows y Windows sigue funcionando como siempre, pero al arrancar el equipo lo primero que se carga es el hipervisor, y Windows se ejecuta encima de él en la **partición raíz** (root partition): una VM con privilegios especiales que gestiona los drivers y crea el resto de VMs.
</details>

### 3. En un servidor de base de datos virtualizado, ¿por qué no conviene usar memoria dinámica (ballooning)?

<details>
<summary>Respuesta</summary>

PostgreSQL dimensiona su memoria al arrancar según la RAM que tiene: `shared_buffers` se reserva una vez y no se adapta, y `effective_cache_size` le dice al planificador cuánta caché de disco puede esperar.

Con ballooning, el hipervisor le quita RAM a la VM en caliente. Lo primero que se pierde es la caché de disco de Linux, así que aumentan las lecturas a disco y el rendimiento se vuelve impredecible. En el peor caso la VM empieza a usar swap o el OOM killer de Linux mata a PostgreSQL por falta de memoria.

Una base de datos necesita memoria predecible; por eso se usa RAM fija.
</details>

### 4. ¿Por qué se bloquea el acceso de root por SSH y se administra con un usuario y sudo? ¿Qué problema tiene bloquear la cuenta de root por completo?

<details>
<summary>Respuesta</summary>

- **Seguridad:** "root" es un nombre de usuario conocido y el primero que prueban los ataques de fuerza bruta. Si no se puede entrar como root, el atacante tiene que adivinar también el usuario.
- **Trazabilidad:** cada `sudo` queda registrado con el usuario que lo ejecutó (en Rocky/RHEL en `/var/log/secure`; en Debian/Ubuntu en `/var/log/auth.log`). Si todos entran como root, no se sabe quién hizo qué.
- **Menos accidentes:** se trabaja como usuario normal y solo se elevan privilegios cuando hace falta.

Bloquear la cuenta root por completo **no impide usar sudo** (sudo pide la contraseña del propio usuario). Lo que se pierde es el **modo de emergencia/rescate**, que pide la contraseña de root: si el sistema no arranca habría que recuperarlo desde la ISO. Por eso lo habitual es dejar root con contraseña (guardada en un gestor de secretos) pero sin acceso por SSH.
</details>

### 5. ¿Cómo funciona la autenticación SSH por clave pública? ¿Qué clave va en cada sitio y para qué sirve la huella del servidor?

<details>
<summary>Respuesta</summary>

Se basa en criptografía asimétrica. Se genera un par de claves (en el laboratorio, **Ed25519**, que usa el algoritmo **EdDSA**; no confundir con ECDSA):

- La **clave privada** se queda solo en el cliente y nunca sale de ahí.
- La **clave pública** se copia al servidor, en `~/.ssh/authorized_keys` del usuario.

Al conectar, el cliente **firma** datos de la sesión con su clave privada y el servidor **verifica la firma** con la clave pública. Si es válida, deja entrar sin contraseña.

La **huella** es el hash (SHA256) de la clave pública **del propio servidor** (`/etc/ssh/ssh_host_ed25519_key.pub`). La primera vez se pregunta si se confía en ella y se guarda en `~/.ssh/known_hosts`. Si en una conexión futura la huella no coincide, SSH avisa: puede ser un ataque man-in-the-middle (alguien haciéndose pasar por el servidor) o que el servidor se ha reinstalado.

La primera conexión funciona por **TOFU** (Trust On First Use): se confía sin verificar. Lo correcto es comprobar la huella por otro canal (por ejemplo, desde la consola del servidor).
</details>

### 6. ¿Qué diferencia hay entre un switch virtual interno con NAT y uno externo conectado a la tarjeta física?

<details>
<summary>Respuesta</summary>

Los dos son switches virtuales de Hyper-V; la diferencia es a dónde conectan:

| | Interno + NAT | Externo |
|---|---|---|
| Qué hace | Red privada entre el host y las VMs; salen a Internet a través del host | Conecta las VMs directamente a la red física, como si fueran equipos enchufados al router |
| IPs | Fijas y propias (10.10.10.x), no dependen de la red donde esté el portátil | Las da el router (DHCP); cambian al cambiar de red |
| Acceso desde fuera | Solo desde el host, salvo que se abran puertos (`Add-NetNatStaticMapping`) | Cualquier equipo de la red las ve |
| Riesgos | Pocos, está aislado | Expone las VMs a la red; con wifi el puente puede dar problemas |

Para un laboratorio en un portátil que cambia de red, la opción interna con NAT es la adecuada.
</details>

### 7. "No te preocupes por los backups, tengo un checkpoint de Hyper-V de esta mañana". ¿Qué respondes?

<details>
<summary>Respuesta</summary>

Un checkpoint de la VM (que incluye todos sus discos) no es un backup válido de una base de datos:

- **Está en el mismo almacenamiento:** si falla el disco físico se pierden las VMs y los checkpoints a la vez. Un backup tiene que estar en otro sitio.
- **Consistencia:** un snapshot de PostgreSQL en marcha equivale a un corte de luz. Arrancará haciendo recuperación, pero no es una copia limpia.
- **Sin PITR:** solo permite volver a ese momento exacto y se pierde todo lo posterior. Con un backup más el archivo de WAL se puede volver a cualquier instante (por ejemplo, justo antes de un `DROP TABLE`).
- **No está coordinado** entre los nodos del clúster.
- **Rendimiento:** las cadenas de checkpoints son discos diferenciales que penalizan la E/S.

Los backups de PostgreSQL se hacen con herramientas específicas como pgBackRest o pg_basebackup.
</details>

### 8. ¿Qué es SELinux, qué hace restorecon y qué pasa si no se ejecuta tras crear ~/.ssh a mano?

<details>
<summary>Respuesta</summary>

**SELinux** (Security-Enhanced Linux) es un módulo de seguridad del kernel que añade un control de acceso obligatorio (MAC) por encima de los permisos normales. Cada proceso y cada fichero tienen una **etiqueta** (contexto), y una política define qué etiquetas de proceso pueden acceder a qué etiquetas de fichero.

`restorecon` **restaura la etiqueta por defecto** que la política define para una ruta.

Si `~/.ssh` se crea a mano puede quedar con una etiqueta genérica de carpeta personal (`user_home_t`) en lugar de la de SSH (`ssh_home_t`). Como `sshd` está confinado por SELinux, no puede leer `authorized_keys` y **pide contraseña aunque los permisos sean correctos**. `ssh-copy-id` ya se encarga de esto.
</details>

### 9. ¿Qué es Kickstart, cómo lo encuentra el instalador en el laboratorio y por qué se usa poweroff en lugar de reboot?

<details>
<summary>Respuesta</summary>

**Kickstart** es un fichero de texto (`ks.cfg`) con todas las respuestas del instalador de RHEL/Rocky (Anaconda): idioma, discos, red, usuarios, paquetes... Permite instalar servidores (físicos o virtuales) de forma automática y repetible.

En el laboratorio, el `ks.cfg` va en un disco pequeño con la **etiqueta** `OEMDRV`. Durante el arranque, el initramfs del instalador (dracut) detecta los discos, encuentra el volumen con esa etiqueta, lo monta y busca `ks.cfg` en su raíz. Si lo encuentra, Anaconda instala sin preguntar nada. Tiene menos prioridad que pasar `inst.ks=` en el menú de arranque.

Se usa `poweroff` porque con `reboot` la VM volvería a arrancar desde la ISO, el instalador encontraría de nuevo el disco `OEMDRV` y **se reinstalaría en bucle**. Con la VM apagada, el script `04-tras-kickstart.ps1` quita la ISO y el disco Kickstart (no lo borra, solo lo desconecta) y la enciende ya desde su disco.
</details>

### 10. ¿Qué significa que los discos de las VMs sean dinámicos? ¿Qué ventajas y riesgos tiene en un servidor de base de datos?

<details>
<summary>Respuesta</summary>

Un disco **dinámico** tiene un tamaño máximo, pero el fichero `.vhdx` solo ocupa en el host lo que realmente contiene y va creciendo según se escribe.

**Ventajas:** ahorra espacio en el host y permite crear discos grandes sin reservarlos de golpe.

**Riesgos:**
- **Sobreasignación:** las VMs creen tener más espacio del que el host puede darles. Si el disco del host se llena, Hyper-V **pausa todas las VMs a la vez** (estado Paused-Critical).
- **Rendimiento:** la primera escritura en cada zona nueva obliga a hacer crecer el fichero, lo que añade latencia y fragmentación.
- **No se encogen solos:** si se borran datos, el `.vhdx` sigue ocupando lo mismo hasta hacer `Optimize-VHD` con la VM apagada.

Por eso en producción las bases de datos suelen ir en discos de tamaño fijo.
</details>
