# Guía de despliegue paso a paso (dominio + VPS + HTTPS)

Resultado final: `https://tudominio.cl` muestra la tienda, el panel admin y la API, con candado HTTPS,
la base de datos con todos los productos y la sincronización cada 30 min funcionando sola.

> En los comandos, reemplaza `tudominio.cl` por tu dominio e `IP_DEL_VPS` por la IP que te den.
> Los comandos con `PS>` van en **PowerShell de tu PC**; los que tienen `$` van en el **VPS** (Linux).

---

## Paso 0. Qué comprar (≈ $10.000 CLP/año + ≈ USD 6/mes)

1. **Dominio `.cl`** en https://www.nic.cl (≈ $9.950 CLP/año). Necesitas RUT y Clave Única o cuenta NIC.
   - Ojo: el cliente **ya tiene `maykelrepuestos.cl`** (su sistema está en `sistema.maykelrepuestos.cl`).
     Si quien administra ese dominio te crea un registro A, puedes usar `tienda.maykelrepuestos.cl`
     **sin comprar nada**. Pregúntale antes de comprar.
2. **Servidor VPS** con **Ubuntu 24.04**, mínimo 1 vCPU / 2 GB RAM / 25 GB disco.
   Opciones: Vultr (tiene datacenter en **Santiago**, menor latencia), DigitalOcean, Hetzner, Contabo.
   Al crearlo te entregan una **IP pública** y la clave de `root`.

## Paso 1. Apuntar el dominio al VPS (DNS)

En el panel donde administras el dominio (NIC Chile → "Servidores DNS", o el DNS del proveedor del VPS),
crea estos registros:

| Tipo | Nombre | Valor |
|---|---|---|
| A | `@` (tudominio.cl) | IP_DEL_VPS |
| A | `www` | IP_DEL_VPS |

Comprueba (puede tardar de minutos a unas horas):
```powershell
PS> nslookup tudominio.cl      # debe responder IP_DEL_VPS
```

## Paso 2. Preparar en tu PC lo que vas a subir

```powershell
PS> cd C:\Users\chunc\Maykel_Repuestos-master
# 2.1 Compilar la web
PS> cd app; flutter build web --release --no-web-resources-cdn; cd ..
# 2.2 Respaldo de la base de datos (productos, usuarios, reservas, configuración)
PS> $env:PGPASSWORD='TU_CLAVE_POSTGRES_LOCAL'
PS> & "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" -U postgres -h localhost -Fc -f maykel.dump maykel_repuestos2
# 2.3 Empaquetar web compilada + fotos subidas
PS> tar -czf web.tar.gz -C app\build web
PS> tar -czf uploads.tar.gz -C backend uploads
# 2.4 Subir todo al VPS (Windows ya trae scp)
PS> scp maykel.dump web.tar.gz uploads.tar.gz root@IP_DEL_VPS:/root/
```

## Paso 3. Entrar al VPS e instalar programas

```powershell
PS> ssh root@IP_DEL_VPS
```
```bash
$ apt update && apt upgrade -y
$ apt install -y git nginx certbot python3-certbot-nginx ufw curl gnupg postgresql-common
# PostgreSQL 18 (la MISMA versión de tu PC; Ubuntu trae la 16 y no lee respaldos de la 18)
$ /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
$ apt install -y postgresql-18
# Dart SDK
$ wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg
$ echo 'deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' > /etc/apt/sources.list.d/dart_stable.list
$ apt update && apt install -y dart
$ dart --version
# Cortafuegos: solo SSH, HTTP y HTTPS (PostgreSQL y el 8080 quedan cerrados al exterior)
$ ufw allow OpenSSH && ufw allow 'Nginx Full' && ufw --force enable
```

## Paso 4. Código, base de datos y fotos

```bash
$ git clone https://github.com/BrayanIriarte1/maykel_repuestos2.git /opt/maykel
$ mkdir -p /opt/maykel/app/build
$ tar -xzf /root/web.tar.gz -C /opt/maykel/app/build
$ tar -xzf /root/uploads.tar.gz -C /opt/maykel/backend
# Clave NUEVA para postgres (no reutilices la de tu PC, quedó expuesta en el historial de GitHub)
$ sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'CLAVE_NUEVA_LARGA';"
$ sudo -u postgres createdb maykel_repuestos2
$ sudo -u postgres pg_restore -d maykel_repuestos2 --no-owner /root/maykel.dump
$ sudo -u postgres psql -d maykel_repuestos2 -f /opt/maykel/backend/database/migraciones.sql
$ sudo -u postgres psql -d maykel_repuestos2 -c "select count(*) from productos;"   # ≈ 6.330
```
(Instalación desde cero sin respaldo: `-f backend/database/schema.sql` y luego `migraciones.sql`.)

## Paso 5. Archivo `.env` de producción

```bash
$ cd /opt/maykel/backend
$ cp .env.example .env
$ openssl rand -hex 32     # ejecútalo 2 veces: uno para JWT_SECRET y otro para SYNC_API_TOKEN
$ nano .env                # editar; guardar con Ctrl+O, Enter, salir con Ctrl+X
$ chmod 600 .env
```
Valores a poner:
```
PORT=8080
DB_PASS=CLAVE_NUEVA_LARGA
JWT_SECRET=<primer openssl rand>
SYNC_API_TOKEN=<segundo openssl rand>
CORS_ORIGIN=https://tudominio.cl
TRUST_PROXY=1
SISTEMA_URL=https://sistema.maykelrepuestos.cl
SISTEMA_EMAIL=<correo del sistema del cliente>
SISTEMA_PASS=<clave del sistema del cliente>
SISTEMA_BODEGAS=1
# SMTP_* y WHATSAPP_* cuando los tengas
```

## Paso 6. Compilar el servidor y dejarlo como servicio

```bash
$ cd /opt/maykel/backend && dart pub get
$ dart compile exe bin/server.dart -o bin/server     # binario rápido, no necesita "dart run"
$ ./bin/server     # prueba manual: debe decir que escucha en 8080. Ctrl+C para salir
```
Crear el servicio para que arranque solo y se reinicie si falla:
```bash
$ cat > /etc/systemd/system/maykel.service <<'EOF'
[Unit]
Description=Maykel Repuestos 2
After=network.target postgresql.service

[Service]
WorkingDirectory=/opt/maykel/backend
ExecStart=/opt/maykel/backend/bin/server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
$ systemctl daemon-reload && systemctl enable --now maykel
$ systemctl status maykel          # debe decir "active (running)"
$ curl -s localhost:8080/api/health
```

## Paso 7. Nginx + HTTPS (candado)

```bash
$ cat > /etc/nginx/sites-available/maykel <<'EOF'
server {
    listen 80;
    server_name tudominio.cl www.tudominio.cl;
    client_max_body_size 5M;            # fotos de productos (el backend acepta hasta 3 MB)

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
$ ln -s /etc/nginx/sites-available/maykel /etc/nginx/sites-enabled/
$ rm -f /etc/nginx/sites-enabled/default
$ nginx -t && systemctl reload nginx
$ certbot --nginx -d tudominio.cl -d www.tudominio.cl --redirect -m tu@correo.cl --agree-tos -n
```
Certbot instala el certificado (TLS 1.2/1.3), redirige http→https y lo renueva solo.
Abre **https://tudominio.cl** 🎉

## Paso 8. Sincronización automática con el sistema del cliente (cada 30 min)

El agente puede correr en el mismo VPS (lee `SISTEMA_*` y `SYNC_API_TOKEN` del `.env` y usa `http://localhost:8080`):
```bash
$ cd /opt/maykel/backend && dart compile exe tools/sync_agent.dart -o tools/sync_agent
$ ./tools/sync_agent --sistema          # prueba manual: debe terminar "OK"
$ crontab -e
```
Agregar al final:
```
*/30 * * * * cd /opt/maykel/backend && ./tools/sync_agent --sistema >> /var/log/maykel_sync.log 2>&1
```
Ya no necesitas la tarea programada de tu PC: quítala con `backend\tools\instalar_sync.ps1 -Quitar`.

## Paso 9. Respaldo diario de la base de datos

```bash
$ mkdir -p /opt/respaldos && crontab -e
```
```
0 3 * * * sudo -u postgres pg_dump -Fc maykel_repuestos2 > /opt/respaldos/maykel_$(date +\%F).dump && find /opt/respaldos -mtime +14 -delete
```
Cada cierto tiempo descarga uno a tu PC: `PS> scp root@IP_DEL_VPS:/opt/respaldos/*.dump .`
Restaurar: `sudo -u postgres pg_restore -d maykel_repuestos2 --clean --no-owner archivo.dump`

## Paso 10. Lista final antes de entregar

- [ ] Cambiar las claves de `admin`, `daniel` y `vendedor` desde **Admin → Usuarios**.
- [ ] El cliente cambia la clave de su sistema (y la actualizas en `SISTEMA_PASS` del `.env`).
- [ ] https://tudominio.cl carga, el login funciona, se puede hacer una reserva y el stock baja al confirmarla.
- [ ] `/api/docs` abre (opcional: ocultarlo en producción).
- [ ] `tail /var/log/maykel_sync.log` muestra sincronizaciones OK cada 30 min.
- [ ] Prueba de carga desde tu PC: `dart run tools\prueba_carga.dart 50 20 https://tudominio.cl`

## Actualizar la página después de cambiar código

```powershell
PS> git push                                   # en tu PC
PS> cd app; flutter build web --release --no-web-resources-cdn; cd ..
PS> tar -czf web.tar.gz -C app\build web; scp web.tar.gz root@IP_DEL_VPS:/root/
```
```bash
$ cd /opt/maykel && git pull
$ rm -rf app/build/web && tar -xzf /root/web.tar.gz -C app/build
$ sudo -u postgres psql -d maykel_repuestos2 -f backend/database/migraciones.sql
$ cd backend && dart pub get && dart compile exe bin/server.dart -o bin/server && systemctl restart maykel
```

## Problemas comunes

| Síntoma | Causa / solución |
|---|---|
| `502 Bad Gateway` | El servidor Dart no corre: `systemctl status maykel` y `journalctl -u maykel -n 50` |
| Certbot falla | El DNS aún no apunta al VPS (`nslookup`) o el puerto 80 está cerrado (`ufw status`) |
| `413` al subir foto | Falta `client_max_body_size` en Nginx |
| Error de contraseña BD | `DB_PASS` del `.env` distinto a la clave de `ALTER USER` |
| `pg_restore: unsupported version` | El VPS tiene PostgreSQL más antiguo que tu PC: instalar la 18 (Paso 3) |
