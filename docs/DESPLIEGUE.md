# Despliegue en producción (RNF03, RNF05)

## 1. Servidor
VPS Linux (Ubuntu 22.04, 1 vCPU / 2 GB) o equipo Windows con IP pública. Dominio `.cl` apuntando al servidor (registro A).

## 2. Instalar
```bash
sudo apt install postgresql nginx certbot python3-certbot-nginx
# Instalar Dart SDK (https://dart.dev/get-dart) y Flutter para compilar la web
sudo -u postgres createdb maykel_repuestos2
sudo -u postgres psql -d maykel_repuestos2 -f backend/database/schema.sql
cd app && flutter build web --no-web-resources-cdn
```

## 3. `.env` de producción (`backend/.env`)
- `DB_PASS`: clave NUEVA (no la de desarrollo).
- `JWT_SECRET`: cadena aleatoria larga (>= 32 caracteres). Obligatorio.
- `SYNC_API_TOKEN`: token aleatorio, el mismo que usa el agente de sincronización.
- `SMTP_*`, `EMAIL_DESTINO`, `WHATSAPP_*`: ver `.env.example`.
- Cambiar las claves demo (`admin`, `daniel`, `vendedor`) desde el panel de Usuarios.

## 4. Servicio (systemd) `/etc/systemd/system/maykel.service`
```
[Unit]
Description=Maykel Repuestos
After=postgresql.service
[Service]
WorkingDirectory=/opt/maykel/backend
ExecStart=/usr/lib/dart/bin/dart run bin/server.dart
Restart=always
[Install]
WantedBy=multi-user.target
```
`sudo systemctl enable --now maykel`

## 5. HTTPS (TLS 1.2/1.3) con nginx
```
server { server_name tu-dominio.cl; location / { proxy_pass http://127.0.0.1:8080; proxy_set_header X-Forwarded-For $remote_addr; } }
```
`sudo certbot --nginx -d tu-dominio.cl` (renovación automática).

## 6. Respaldo y restauración (RNF05)
```bash
pg_dump -U postgres -Fc maykel_repuestos2 > respaldo_$(date +%F).dump     # diario con cron
pg_restore -U postgres -d maykel_repuestos2 --clean respaldo_2026-01-01.dump
```
Windows: Programador de tareas con `"C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" -U postgres -Fc -f C:\respaldos\maykel.dump maykel_repuestos2`.

## 7. Agente de sincronización en la bodega (Windows)
Programador de tareas, cada 30 min (desde la carpeta `backend`, con las variables `SISTEMA_*` en `.env`):
`dart run tools\sync_agent.dart --sistema`
(alternativa con CSV: `dart run tools\sync_agent.dart --archivo C:\inventario\stock.csv --url https://tu-dominio.cl --token TU_TOKEN`)
Si pasan 2 h sin sincronizar el sistema marca "Stock desactualizado".

## 8. Pendientes de seguridad recomendados
Restringir CORS al dominio propio y proteger `/api/docs` en producción.
