# Estado del proyecto y trazabilidad

Backend real: Dart/shelf + PostgreSQL (ES1 y ClickUp dicen Node/Express: actualizar documentos).

| Requisito | Estado | Evidencia / pendiente |
|---|---|---|
| HU-01/RF01 Catálogo y búsqueda sin precio | Hecho | `/api/repuestos`, filtros por vehículo |
| HU-02/RF02 Búsqueda por vehículo | Hecho | `/api/versiones`, marca→modelo→año |
| HU-03/RF03 Reserva con folio | Hecho | `POST /api/reservas` |
| HU-04/RF04 Notificación WhatsApp + email | Hecho (falta credenciales reales) | `lib/notificador.dart`, `.env` |
| PDF de reserva | Hecho | `lib/pdf_reserva.dart` |
| HU-05/RF05 Sincronización de stock | Hecho (conector directo con el sistema del cliente, bodega Sucursal + CSV) | `tools/sync_agent.dart --sistema`; falta programarlo cada 30 min |
| HU-06 Alerta stock desactualizado (2 h) | Parcial | verificar visualización en dashboard |
| HU-07/RF07 Dashboard/analítica | Hecho | panel Analítica |
| RNF03 JWT + bcrypt | Hecho | `lib/seguridad.dart` |
| RNF03 HTTPS/TLS | Pendiente | `docs/DESPLIEGUE.md` (nginx + Let's Encrypt) |
| RNF02 50 usuarios concurrentes | Pendiente | prueba de carga |
| RNF05 Respaldos | Documentado | `docs/DESPLIEGUE.md`; falta programarlo |
| Pruebas automatizadas | Hecho | 21 integración + 8 unitarias |
| UAT con >= 10 usuarios | Pendiente | depende del equipo |
| Despliegue + dominio .cl | Pendiente | depende del equipo |
| Capacitación | Documentado | `docs/MANUAL_USUARIO.md` |

## Para ClickUp
Marcar como hechas: búsqueda jerárquica, PDF, notificaciones (código), pipeline de sync (código), dashboard, pruebas, seguridad JWT/bcrypt, manual.
Siguen abiertas: revisión de diseño (vencida), QA/UAT, despliegue, HTTPS, prueba de carga.
Actualizar ES2: la BD es PostgreSQL (no JSON) y la reserva no descuenta stock; solo la venta.
