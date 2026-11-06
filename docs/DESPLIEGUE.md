# Despliegue y mantenimiento en producción

Producción actual: **https://maykel-repuestos2.cl** en un VPS de MOX (Ubuntu 24.04, 2 GB RAM, 5 GB de disco).

```
Navegador ──HTTPS──> Nginx (80/443) ──> servidor Dart (127.0.0.1:8080) ──> PostgreSQL 16
                                              ▲
                  cron cada 30 min: sync_agent ┘──> sistema.maykelrepuestos.cl
```

Carpetas en el servidor:

| Ruta | Contenido |
|---|---|
| `/opt/maykel/backend/bin/server` | servidor compilado (binario Linux) |
| `/opt/maykel/backend/tools/sync_agent` | agente de sincronización compilado |
| `/opt/maykel/backend/.env` | claves de producción (permisos 600, **nunca** a GitHub) |
| `/opt/maykel/backend/docs`, `database` | `openapi.yaml`, `schema.sql`, `migraciones.sql` |
| `/opt/maykel/backend/uploads` | fotos subidas desde el panel (**no** van en el respaldo de la BD) |
| `/opt/maykel/app/build/web` | web Flutter compilada |
| `/opt/respaldos` | respaldos diarios de la BD (14 días) |

> El servidor busca todo relativo al binario: debe quedar en `<carpeta>/backend/bin/server` y la web en `<carpeta>/app/build/web`.

En los comandos, `$h` y `$k` son variables de PowerShell (se definen una vez por ventana):
```powershell
$h = "root@179.61.200.126"
$k = "$env:USERPROFILE\.ssh\maykel_vps"      # llave SSH, sin contraseña
```
Entrar al servidor: `ssh -i $k $h`. Salir: `exit`.

---

## 1. Actualizar la página (lo que harás más seguido)

Todo se ejecuta **desde tu PC**, en `C:\Users\chunc\Maykel_Repuestos-master`.
Ruta de Dart/Flutter si no están en el PATH: `$env:Path = "C:\Users\chunc\flutter\bin;C:\Users\chunc\flutter\bin\cache\dart-sdk\bin;" + $env:Path`

### 1A. Solo cambió el frontend (pantallas, textos, estilos)
```powershell
cd app
flutter build web --release --no-web-resources-cdn
cd ..
tar -czf web.tar.gz -C app\build web
scp -i $k web.tar.gz "${h}:/root/"
ssh -i $k $h "rm -rf /opt/maykel/app/build/web && tar -xzf /root/web.tar.gz -C /opt/maykel/app/build && rm /root/web.tar.gz"
Remove-Item web.tar.gz
```
No hace falta reiniciar nada. Recarga con **Ctrl+F5**.

### 1B. Cambió el backend (API, sync, base de datos)
```powershell
cd backend
dart compile exe --target-os linux --target-arch x64 bin/server.dart -o ..\server_linux
dart compile exe --target-os linux --target-arch x64 tools/sync_agent.dart -o ..\sync_agent_linux
cd ..
scp -i $k server_linux "${h}:/opt/maykel/backend/bin/server.nuevo"
scp -i $k sync_agent_linux "${h}:/opt/maykel/backend/tools/sync_agent.nuevo"
scp -i $k backend\database\migraciones.sql backend\database\schema.sql "${h}:/opt/maykel/backend/database/"
scp -i $k backend\docs\openapi.yaml "${h}:/opt/maykel/backend/docs/"
ssh -i $k $h "cd /opt/maykel/backend && chmod +x bin/server.nuevo tools/sync_agent.nuevo && mv bin/server.nuevo bin/server && mv tools/sync_agent.nuevo tools/sync_agent && systemctl restart maykel && sleep 3 && systemctl is-active maykel"
Remove-Item server_linux, sync_agent_linux
```
- Las migraciones (`migraciones.sql`) se aplican solas al arrancar el servidor. Son idempotentes.
- Debe responder `active`. Si no: `ssh -i $k $h "journalctl -u maykel -n 40 --no-pager"`.

### 1C. Cambiaron los dos
Haz 1A y luego 1B.

### 1D. Verificar después de actualizar
```powershell
curl.exe -s https://maykel-repuestos2.cl/api/health
```
Debe mostrar `"status":"ok"`. Abre la web, inicia sesión, haz una reserva de prueba y confírmala.

### Subir el código a GitHub
```powershell
git add -A
git commit -m "descripción del cambio"
git push
```
GitHub guarda solo el código. El servidor **no** se actualiza con `git push`: sigue 1A/1B.

---

## 2. Operación diaria

```powershell
ssh -i $k $h "systemctl status maykel --no-pager | head -n 5"     # ¿está corriendo?
ssh -i $k $h "journalctl -u maykel -n 50 --no-pager"               # últimos logs del servidor
ssh -i $k $h "tail -n 20 /var/log/maykel_sync.log"                 # últimas sincronizaciones
ssh -i $k $h "systemctl restart maykel"                            # reiniciar
ssh -i $k $h "df -h / | tail -n 1; free -m | head -n 2"            # disco y memoria
```
Sincronizar a mano ahora: `ssh -i $k $h "cd /opt/maykel/backend && ./tools/sync_agent --sistema"`.

### Cambiar claves o correo/WhatsApp (`.env`)
```powershell
ssh -i $k $h
nano /opt/maykel/backend/.env        # Ctrl+O, Enter para guardar; Ctrl+X para salir
systemctl restart maykel
```
Variables: ver `backend/.env.example` (`SMTP_*`, `EMAIL_DESTINO`, `WHATSAPP_*`, `SISTEMA_EMAIL`, `SISTEMA_PASS`, `CORS_ORIGIN`, `TRUST_PROXY=1`).
Si cambia la clave del sistema del cliente, solo actualiza `SISTEMA_PASS`.

### Respaldos
- Automático: todos los días 3:00 en `/opt/respaldos/maykel_AAAA-MM-DD.dump`.
- Descargar uno a tu PC: `scp -i $k "${h}:/opt/respaldos/*.dump" .`
- Respaldo manual ahora: `ssh -i $k $h "sudo -u postgres pg_dump -Fc maykel_repuestos2 > /opt/respaldos/manual.dump"`
- Fotos de productos (no están en el respaldo de la BD): `scp -i $k -r "${h}:/opt/maykel/backend/uploads" .\respaldo_uploads`
- Restaurar (¡reemplaza los datos actuales!):
  ```bash
  systemctl stop maykel
  sudo -u postgres pg_restore -d maykel_repuestos2 --clean --if-exists --no-owner /opt/respaldos/ARCHIVO.dump
  systemctl start maykel
  ```
  Un `.dump` hecho en PostgreSQL 18 (tu PC) **no** se puede restaurar con `pg_restore` 16 del servidor.
  Para pasar datos de tu PC al servidor usa formato SQL: `pg_dump -Fp --no-owner --no-privileges -f maykel.sql maykel_repuestos2` y en el servidor `psql -d maykel_repuestos2 -f maykel.sql` (borra antes la línea `SET transaction_timeout`).

### Sincronización con el sistema del cliente
Cron del servidor (`/etc/cron.d/maykel`): `sync_agent --sistema` cada 30 min.
Si pasan 2 h sin sincronizar, el sitio marca "Stock desactualizado". Los productos del cliente que dejan de venir en un sync completo quedan en stock 0.
No ejecutes además la tarea programada de Windows (`instalar_sync.ps1`): sobraría.

---

## 3. Seguridad (estado y reglas)

- Firewall `ufw`: solo SSH (22), 80 y 443. PostgreSQL y el puerto 8080 **no** son públicos.
- HTTPS con Let's Encrypt, renovación automática (`certbot renew --dry-run` para probarla).
- Acceso al servidor solo por llave SSH. No compartas por chat contraseñas, `.env` ni la llave privada `maykel_vps`.
- Las claves de `admin`, `daniel` y `vendedor` se cambian en **Admin → Usuarios**.
- `/api/docs` es público; no expone datos, pero los endpoints `/api/admin/*` exigen sesión.
- El repositorio es público: jamás subas `.env`, claves ni respaldos.

---

## 4. Problemas comunes

| Síntoma | Causa y solución |
|---|---|
| `502 Bad Gateway` | El servidor Dart no corre: `systemctl status maykel` y `journalctl -u maykel -n 50` |
| La web muestra la versión vieja | Ctrl+F5; si sigue, repite 1A |
| `Permission denied (publickey)` al hacer `ssh` | Falta la llave en el servidor: entra por la consola de MOX y agrega la llave pública (`maykel_vps.pub`) a `~/.ssh/authorized_keys` |
| `413` al subir una foto | `client_max_body_size` de Nginx (hoy 5M); el backend acepta hasta 3 MB |
| Error de contraseña de la BD | `DB_PASS` del `.env` distinto a la clave del usuario `postgres` |
| Stock desactualizado | `tail -n 20 /var/log/maykel_sync.log`; ¿cambió la clave del sistema del cliente? |
| Disco lleno (solo 5 GB) | `df -h /`; limpiar con `apt clean`, `journalctl --vacuum-size=100M`; o pedir más disco a MOX |
| Al pegar en la consola de MOX salen `^[[200~` | Escribe el comando a mano o pega con clic derecho |

---

## 5. Instalación desde cero (otro VPS)

Resumen de lo que se hizo; usa Ubuntu 24.04 LTS con acceso root por SSH y ≥ 20 GB de disco si es posible.

1. **DNS:** registros `A` para `@` y `www` hacia la IP del VPS (`nslookup tudominio.cl`).
2. **Llave SSH:** `ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\maykel_vps -N '""'` y agrega la `.pub` a `/root/.ssh/authorized_keys` del servidor.
3. **Programas:** `apt update && apt install -y postgresql nginx certbot python3-certbot-nginx ufw`
4. **Carpetas y archivos:** crea `/opt/maykel/{backend/{bin,tools,docs,database,uploads},app/build}` y sube con `scp`: `server`, `sync_agent` (compilados con `--target-os linux`, ver 1B), `openapi.yaml`, `schema.sql`, `migraciones.sql`, y la web (1A).
5. **Base de datos:** `sudo -u postgres createdb maykel_repuestos2`, restaura `maykel.sql` (ver Respaldos) o usa `schema.sql` + `migraciones.sql` si parte vacía. Clave nueva: `ALTER USER postgres PASSWORD '...'`. El archivo SQL debe estar en `/tmp` (el usuario `postgres` no lee `/root`).
6. **`.env`** (`chmod 600`): `PORT=8080`, `DB_*`, `JWT_SECRET` y `SYNC_API_TOKEN` (`openssl rand -hex 32`), `CORS_ORIGIN=https://tudominio.cl`, `TRUST_PROXY=1`, `SISTEMA_URL/EMAIL/PASS/BODEGAS`.
7. **Servicio** `/etc/systemd/system/maykel.service`:
   ```
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
   ```
   `systemctl daemon-reload && systemctl enable --now maykel`
8. **Nginx** `/etc/nginx/sites-available/maykel` (enlazado en `sites-enabled`, sin el `default`):
   ```
   server {
       listen 80 default_server;
       server_name tudominio.cl www.tudominio.cl _;
       client_max_body_size 5M;
       location / {
           proxy_pass http://127.0.0.1:8080;
           proxy_set_header Host $host;
           proxy_set_header X-Forwarded-For $remote_addr;
           proxy_set_header X-Forwarded-Proto $scheme;
       }
   }
   ```
   `nginx -t && systemctl reload nginx`
9. **HTTPS:** `certbot --nginx -d tudominio.cl -d www.tudominio.cl --redirect --agree-tos -m tu@correo.cl -n`
10. **Firewall:** `ufw allow OpenSSH && ufw allow 'Nginx Full' && ufw --force enable`
11. **Cron** `/etc/cron.d/maykel` (permisos 644):
    ```
    SHELL=/bin/bash
    */30 * * * * root cd /opt/maykel/backend && ./tools/sync_agent --sistema >> /var/log/maykel_sync.log 2>&1
    0 3 * * * postgres pg_dump -Fc maykel_repuestos2 > /opt/respaldos/maykel_$(date +\%F).dump && find /opt/respaldos -name '*.dump' -mtime +14 -delete
    ```
    y `mkdir -p /opt/respaldos && chown postgres /opt/respaldos`.
12. **Prueba final:** `https://tudominio.cl`, login, reserva de prueba, `/api/docs`, y `./tools/sync_agent --sistema` sin errores.
