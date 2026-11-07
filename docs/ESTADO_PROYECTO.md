# Estado del proyecto y trazabilidad (ES1 → código)

Producción: https://maykel-repuestos2.cl · Backend Dart/shelf + PostgreSQL 16 · Frontend Flutter Web.
Verificado el 06-11-2026 con 51 pruebas automáticas (`dart test`), `dart analyze` y `flutter analyze` sin hallazgos,
y prueba de carga de 50 usuarios simultáneos contra producción (p95 = 625 ms, 0 errores).

| Requisito | Estado | Evidencia / observación |
|---|---|---|
| RF01 Vitrina sin precios | Hecho | La API pública devuelve `precio_oculto:true` y `precio:0`; el panel sí ve precios |
| RF02 Búsqueda Marca → Modelo → Año → Motor | **Parcial** | El sitio filtra por texto, categoría, marca y modelo (derivados del catálogo del cliente). La BD y la API ya soportan año/motor/cilindrada (`versiones_vehiculo`, `producto_compatibilidad`), pero el sistema del cliente no entrega esos datos; falta cargarlos y mostrar los selectores |
| RF03 Reserva con lista y PDF con folio | Hecho | Lista de reserva (`utils/carrito.dart`), `POST /api/reservas` con ítems y PDF (Roboto, tildes y ñ), descarga automática |
| RF04 WhatsApp + correo | Código hecho; **faltan credenciales** | `SMTP_*` y `WHATSAPP_*` en el `.env` del servidor. Si WhatsApp falla, el correo igual se envía |
| RF05 Sincronización y «Agotado» | Hecho | `sync_agent --sistema` cada 30 min (cron en el VPS); los productos que el cliente deja de enviar quedan en stock 0 |
| RF06 Analítica de demanda | Hecho | Búsquedas sin resultado (automático) e interés en agotados (botón «Me interesa») |
| RF07 Administración de catálogo | Hecho | CRUD, ocultar, stock masivo, fotos |
| RNF01 Responsivo (≥ 360 px) | Hecho | Flutter Web; probar en más dispositivos en UAT |
| RNF02 ≤ 1,8 s con 50 usuarios | **Cumple** | Producción: media 162 ms, p95 625 ms, máx 1,5 s, 0 errores (`tools/prueba_carga.dart`) |
| RNF03 RBAC + JWT + bcrypt ≥ 10 + TLS | **Cumple** | `lib/seguridad.dart`; HTTPS con TLS 1.2/1.3 (TLS 1.1 rechazado); HSTS; SSH solo con llave y fail2ban |
| RNF04 Disponibilidad ≥ 99 % | En operación | Servicio con reinicio automático; falta medir un mes con un monitor externo (UptimeRobot) |
| RNF05 Sincronización unidireccional | Hecho (variante) | El agente corre **en el VPS** y solo consulta (GET/POST de lectura) el sistema del cliente por HTTPS saliente; la web no escribe en el sistema del cliente y la sucursal no abre puertos |
| RNF06 PDF y aviso ≤ 5 s | **Cumple** | Reserva con 2 repuestos y PDF: 375 ms en producción |
| Respaldos | Hecho | `pg_dump` diario 03:00, 14 días, en `/opt/respaldos` (guía de restauración en `docs/DESPLIEGUE.md`) |
| Pruebas automatizadas | Hecho | 51 pruebas (API + unitarias) |
| UAT con ≥ 10 usuarios | Pendiente | Depende del equipo y del cliente |
| Capacitación | Documentado | `docs/MANUAL_USUARIO.md` |

## Diferencias con el ES1 que conviene declarar en el informe
- Backend: **Dart (shelf)**, no Node.js/Express. Frontend servido por el mismo VPS (Nginx), no por Firebase Hosting.
- Integración: no hay POS ni planillas; se consume el sistema web del cliente (bodega 1 = Sucursal), por API autenticada.
- La reserva **no** descuenta stock al crearse; descuenta al **confirmarse** (y se repone si se rechaza).

## Pendientes operativos
1. Credenciales SMTP/WhatsApp. 2. Fotos reales de productos. 3. El cliente debe corregir 71 productos sin precio y ~1.136 sin marca.
4. Cambiar la clave de PostgreSQL del PC de desarrollo y la del sistema del cliente (se compartieron). 5. UAT y acta de aceptación.
6. Cargar compatibilidad vehicular (año/motor) si se quiere cumplir RF02 completo.
