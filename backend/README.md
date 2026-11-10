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
createdb -U postgres maykel_repuestos2

# Crea las tablas y carga los datos de ejemplo
psql -U postgres -d maykel_repuestos2 -f database/schema.sql
```

En Windows también puedes abrir `database/schema.sql` en pgAdmin y
ejecutarlo con la base `maykel_repuestos2` seleccionada.

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

Las contraseñas se guardan con **bcrypt** (costo 10). Los hashes antiguos
(`sha256$...`) siguen funcionando y se convierten a bcrypt automáticamente en
el primer inicio de sesión. Cámbialas desde el panel (Usuarios) antes de usar
el sistema en producción.

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
y probar todos los endpoints; para los de `/api/admin/*` ejecuta primero
`POST /api/auth/login`, copia el `token` de la respuesta y pulsa **Authorize**. La especificación está en
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

Panel admin (token JWT en `Authorization: Bearer <token>`):

- `POST /api/auth/login` — público; devuelve el token (bloqueo tras 5 intentos fallidos)
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

## Seguridad (RNF03)

- Sesión del panel con **JWT** (HS256) firmado con `JWT_SECRET` (obligatorio en producción) y duración `JWT_HORAS` (8 por defecto). Ya no se acepta autenticación Basic.
- Contraseñas con **bcrypt** (costo 10).
- Bloqueo de 15 minutos tras 5 intentos fallidos por usuario e IP.
- Tabla `logs_auditoria`: registra `LOGIN_OK`, `LOGIN_FALLIDO`, `BLOQUEADO_429`, `NO_AUTENTICADO_401` y `DENEGADO_403`.
- `SYNC_API_TOKEN` es obligatorio: sin él la sincronización responde 503 (ya no existe un token por defecto).
- HTTPS/TLS: se configura en el proxy inverso (ver `../docs/DESPLIEGUE.md`).

## Notificaciones de reservas (RF04)

Al crearse una reserva se envían en segundo plano, sin demorar la respuesta al cliente:
un **WhatsApp** (Meta Cloud API) y un **correo SMTP con el PDF adjunto** al equipo de ventas.
Cada canal es independiente: si uno falla se registra y el otro se envía igual.
Si no hay credenciales en `.env` no se envía nada (variables `WHATSAPP_*`, `SMTP_*`, `EMAIL_DESTINO` en `.env.example`).
`reservas.notificado_whatsapp` y `notificado_email` reflejan lo realmente enviado.

## Agente de sincronización de inventario (RF05)

`tools/sync_agent.dart` lee un CSV exportado desde el POS o Excel (columnas `codigo_interno;nombre;stock`)
y lo envía por HTTPS saliente a `/api/v1/sync/inventory`. Ver `tools/ejemplo_inventario.csv`.

```bash
dart run tools/sync_agent.dart --archivo C:\inventario\stock.csv --url https://tu-dominio.cl --token TU_TOKEN --cada 30
dart run tools/sync_agent.dart --archivo tools/ejemplo_inventario.csv --simular   # solo valida
```

### Conexión directa con el sistema del cliente (`--sistema`)

Sin CSV: el agente inicia sesión (solo lectura) en `https://sistema.maykelrepuestos.cl`, lee
`/materiales_data/<bodega>?filtro_estado=todos` y envía código, nombre, categoría, stock y valor.
Configuración en `backend/.env` (no versionado):

```
SISTEMA_URL=https://sistema.maykelrepuestos.cl
SISTEMA_EMAIL=correo_del_sistema
SISTEMA_PASS=clave_del_sistema
SISTEMA_BODEGAS=1        # 1 = Repuestos Bodega Sucursal (la de Maykel, ~6.300 productos); 2 = Bodega Central (otro local)
```

```bash
dart run tools/sync_agent.dart --sistema --simular      # solo valida
dart run tools/sync_agent.dart --sistema                # sincroniza una vez
dart run tools/sync_agent.dart --sistema --cada 30      # repite cada 30 min
```

Reglas: los productos nuevos se **publican** (con o sin stock); los deshabilitados quedan con stock 0;
nombre vacío o "0" se reemplaza por "Categoría - código"; código vacío o "0" → `SYS-<id>`;
código repetido → `<código>-<id>`. El precio se guarda como referencia interna (no se muestra al público). La marca y el modelo del vehículo se deducen del nombre (`lib/vehiculos.dart`) y alimentan el filtro Marca → Modelo del sitio.


```bash
dart test test/unit_test.dart   # unitarias (JWT, bcrypt, PDF): no necesitan servidor
dart test test/api_test.dart    # integración: requiere el servidor corriendo en :8080
```

Si cambiaste las claves demo, define `TEST_ADMIN_USER` y `TEST_ADMIN_PASS`.

La colección `Maykel_Repuestos_2_Postman_Collection.json` sirve para probar
la API desde Postman.
