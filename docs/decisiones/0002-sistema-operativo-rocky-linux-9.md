# 0002 · Sistema operativo: Rocky Linux 9

- Fecha: 2026-10-17
- Estado: Aceptada

## Contexto
El objetivo del laboratorio es parecerse a un entorno de producción de empresa grande
o consultora, donde predomina la familia RHEL. El planteamiento inicial era Debian 12,
que ya está al final de su soporte normal.

## Decisión
Usar Rocky Linux 9 (compatible 1:1 con RHEL 9) en las 4 VMs, con SELinux en modo enforcing
y firewalld activo. PostgreSQL 16 desde los repositorios PGDG para EL9.

## Alternativas consideradas
- Debian 12/13: más sencilla, pero menos representativa de entornos empresariales.
- Ubuntu LTS: habitual en startups y cloud.
- Rocky Linux 10: más reciente, pero la 9 es la más desplegada hoy (soporte hasta 2032).

## Consecuencias
- Paquetes con dnf/rpm; rutas de PostgreSQL en /var/lib/pgsql/16/data.
- Hay que gestionar contextos y puertos de SELinux (semanage, restorecon) y reglas de firewalld.
- No se desactiva SELinux para "hacer que funcione", cada excepción se documenta.
- En Hyper-V: VMs de generación 2 con la plantilla de arranque seguro "Microsoft UEFI Certificate Authority".
