# ANTONIO MX - Instalador automático

Instalador unificado para VPS Ubuntu/Debian **x86_64**.

Instala:
- BTUN BHTTP principal: TCP 8080 hacia SSH local 22.
- BTUN BHTTP secundario: TCP 8880 hacia SSH local 22.
- VLESS XHTTP mediante Xray-core: TCP 8181.
- Servicios systemd habilitados para iniciar al reiniciar la VPS.
- Administrador de usuarios VLESS con UUID, enlaces, JSON y vencimientos.

## Dominio

El instalador configura `ionox.antoniomx.blog` como dirección y host de VLESS. Antes de usar clientes, crea un registro DNS **A** para ese dominio apuntando a la IP pública de la VPS.

## Instalación

Ejecutar como root en una VPS Ubuntu/Debian x86_64:

```bash
curl -fsSL https://raw.githubusercontent.com/luis579/antonio-mx-instalador/main/install-all.sh -o /root/install-all.sh && bash /root/install-all.sh
```

El instalador descarga los dos scripts y el binario desde este repositorio. Comprueba el SHA-256 del binario antes de instalarlo.

## Administrador VLESS

Después de instalar:

```bash
vless-xhttp-manager
```

Desde el menú puedes crear usuarios, generar enlaces/JSON, consultar vencimientos y eliminar usuarios.

## Puertos TCP

| Servicio | Puerto | Destino |
|---|---:|---|
| BTUN principal | 8080 | SSH local 22 |
| BTUN secundario | 8880 | SSH local 22 |
| VLESS XHTTP | 8181 | Xray-core |

Si el proveedor de VPS tiene un firewall externo, permite TCP 8080, 8880 y 8181.

## Nota importante sobre TLS

El instalador VLESS original incluido en este repositorio genera la configuración XHTTP con `security: none`. Por tanto, esta instalación **no configura TLS ni certificados**. No debe confundirse con VLESS XHTTP protegido mediante HTTPS/REALITY. Para habilitar TLS habrá que preparar y validar una configuración adicional antes de exponer el servicio públicamente.

## Compatibilidad

El binario `bilola-server` incluido es ELF Linux x86-64. Este instalador no es compatible con VPS ARM.
