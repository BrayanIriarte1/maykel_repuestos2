# Backend — Maykel Repuestos 2 (Dart + PostgreSQL)

API REST escrita en Dart con [`shelf`](https://pub.dev/packages/shelf) que
guarda todo en **PostgreSQL**. También sirve la app Flutter ya compilada
(`../app/build/web`), así que el sitio completo corre en un solo puerto.

## Requisitos

- [Dart SDK](https://dart.dev/get-dart) 3.0 o superior (viene incluido con Flutter).
- [PostgreSQL](https://www.postgresql.org/download/) 14 o superior.

## 1. Crear la base de datos

```bash
# Crea la base (te pedirá la clave del usuario postgres)
createdb -U postgres maykel_repuestos2_db

# Crea las tablas y carga los datos de ejemplo
psql -U postgres -d maykel_repuestos2_db -f database/schema.sql
```

En Windows también puedes abrir `database/schema.sql` en pgAdmin y
ejecutarlo con la base `maykel_repuestos_db` seleccionada.

> Ojo: `schema.sql` borra y vuelve a crear todas las tablas. Úsalo solo
> para instalar desde cero o reiniciar los datos de demostración.

## 2. Configurar la conexión

```bash
cp .env.example .env     # en Windows: copy .env.example .env
```

Edita `.env` con la clave de tu usuario de PostgreSQL (`DB_PASS`). El
archivo `.env` no se sube a GitHub.

## 3. Correr el servidor

```bash
dart pub get
dart run bin/server.dart
```

Verás `✅ Conectado exitosamente a PostgreSQL` y luego la URL del servidor
(por defecto `http://localhost:8080`).

## Usuarios de demostración del panel

| Usuario    | Contraseña  | Rol                 |
|------------|-------------|---------------------|
| `admin`    | `maykel2026`| Superadministrador  |
| `daniel`   | `maykel2026`| Superadministrador  |
| `vendedor` | `ventas2026`| Vendedor            |

Las contraseñas se guardan como hash SHA-256 con sal (`sha256$<sal>$<hash>`).
Cámbialas desde el panel (Usuarios) antes de usar el sistema en producción.

## Tablas principales

| Tabla | Para qué sirve |
|---|---|
| `productos` | Catálogo con stock, precio de referencia (solo interno) y estado |
| `categorias`, `marcas`, `modelos`, `versiones_vehiculo`, `producto_compatibilidad` | Búsqueda por vehículo (marca → modelo → año → motor) |
| `reservas`, `reserva_detalles` | Reservas hechas desde el sitio público, con folio `RES-####` |
| `ventas` | Ventas registradas en sucursal desde el panel; descuentan stock |
| `usuarios`, `roles` | Acceso al panel con permisos por rol |
| `configuracion_sitio` | Textos editables del sitio (historia, servicios, contacto, aviso legal) |
| `metricas_demanda` | Búsquedas sin resultado y consultas de productos agotados |
| `logs_sincronizacion`, `logs_auditoria` | Registro de sincronizaciones de stock y accesos |

## Documentación interactiva (Swagger)

Con el servidor corriendo, abre `http://localhost:8080/api/docs`. Ahí puedes ver
y probar todos los endpoints; para los de `/api/admin/*` pulsa **Authorize** e
ingresa usuario y contraseña del panel. La especificación está en
`docs/openapi.yaml` (y se sirve en `/api/docs/openapi.yaml`). La página carga
Swagger UI desde un CDN, así que necesita internet. Si cambias o agregas un
endpoint en `bin/server.dart`, actualiza también ese archivo.

## Endpoints

Públicos:

- `GET /api/health`, `GET /api/estado`
- `GET /api/contenido` — textos del sitio
- `GET /api/categorias`, `GET /api/marcas`, `GET /api/modelos`, `GET /api/versiones`
- `GET /api/repuestos` (alias `/api/productos`) — catálogo sin precios; filtros `buscar`, `categoria`, `marca`, `modelo`, `anio`, `disponible=1`
- `POST /api/reservas` — crea una reserva
- `POST /api/metricas/agotado` — registra interés en un producto agotado

Panel admin (autenticación básica, usuario y contraseña):

- `GET /api/admin/verificar`
- `GET /api/admin/dashboard`, `GET /api/admin/analytics`
- `GET|POST|PUT /api/admin/repuestos`, `DELETE /api/admin/repuestos/<id>`
- `GET /api/admin/reservas`, `PUT /api/admin/reservas/<folio>`
- `GET|POST /api/admin/ventas`
- `GET|POST /api/admin/roles`, `PUT|DELETE /api/admin/roles/<id>` (permiso `usuarios`)
- `GET|POST /api/admin/usuarios`, `PUT|DELETE /api/admin/usuarios/<id>` (permiso `usuarios`)
- `PUT /api/admin/contenido`

Sincronización de bodega:

- `POST /api/v1/sync/inventory` con `Authorization: Bearer <SYNC_API_TOKEN>`

La colección `Maykel_Repuestos_2_Postman_Collection.json` sirve para probar
la API desde Postman.
