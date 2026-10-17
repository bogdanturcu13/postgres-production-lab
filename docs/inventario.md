# Inventario

| VM    | IP          | vCPU | RAM  | Disco SO | Disco datos | Rol |
|-------|-------------|------|------|----------|-------------|-----|
| infra | 10.10.10.10 | 2    | 4 GB | 20 GB    | 40 GB       | HAProxy, PgBouncer, pgBackRest, MinIO, monitorización, Ansible |
| pg1   | 10.10.10.11 | 2    | 3 GB | 20 GB    | 20 GB       | PostgreSQL 16 + Patroni + etcd |
| pg2   | 10.10.10.12 | 2    | 3 GB | 20 GB    | 20 GB       | PostgreSQL 16 + Patroni + etcd |
| pg3   | 10.10.10.13 | 2    | 3 GB | 20 GB    | 20 GB       | PostgreSQL 16 + Patroni + etcd |

Red: 10.10.10.0/24 · Puerta de enlace: 10.10.10.1 (host Windows, NAT)

Sistema operativo: Rocky Linux 9.8 (Minimal) · Hipervisor: Hyper-V, VMs de generación 2
Discos: E:\HyperV\VHD\<vm>.vhdx (sistema) y <vm>-datos.vhdx (datos)
