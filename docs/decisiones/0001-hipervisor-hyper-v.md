# 0001 · Hipervisor: Hyper-V

- Fecha: 2026-10-16
- Estado: Aceptada

## Contexto
Host Windows 11 Pro, i5-11400H (6c/12t), 32 GB RAM, 484 GB libres en E:.
Necesito 4 VMs con E/S de disco realista para PostgreSQL.

## Decisión
Usar Hyper-V, con VMs y discos en E:\HyperV.

## Alternativas consideradas
- VirtualBox: sobre la capa de Hyper-V (WSL2, integridad de memoria) pierde rendimiento de E/S.
- Proxmox: requiere una máquina dedicada.

## Consecuencias
- Creación de VMs automatizable con PowerShell (scripts/hyperv/).
- Memoria dinámica desactivada: PostgreSQL dimensiona con la RAM fija.
