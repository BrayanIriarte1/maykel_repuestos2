# Maykel Repuestos — Flutter + Dart

Catálogo público de repuestos y panel de administración de Maykel
Repuestos (Calama, Chile), reescrito completamente en **Flutter Web**
(frontend) y **Dart puro** (backend), sin ninguna dependencia nativa o
compilada — corre igual en Windows, macOS o Linux con solo los SDKs de
Flutter y Dart instalados.

Esta es la reescritura en Flutter/Dart de la versión anterior en
Node.js + HTML/JS. Mantiene exactamente el mismo diseño, flujo de uso y
reglas de negocio:

- Catálogo público con búsqueda y filtro por categoría.
- Reserva de productos (sin mostrar precio), con ticket para enviar por
  WhatsApp o correo.
- Panel de administración único, con 4 pestañas: **Dashboard**, **Ventas**,
  **Reservas** y **Stock**.
- Registro de ventas en sucursal que descuenta stock automáticamente; el
  producto pasa a "Agotado" en el catálogo público cuando llega a 0. Las
  reservas web quedan "pendientes" hasta que un vendedor las confirma.
- Sección de historia y giro comercial, y mapa con la ubicación de la
  sucursal (Vargas #2275, Calama).
- Base de datos **PostgreSQL** (ver `backend/database/schema.sql`).
- Gestión de productos desde el panel: **agregar y eliminar productos**
  del catálogo directamente desde la pestaña Stock, sin tocar el archivo
  de datos a mano.
- Descarga de reportes de ventas, reservas y **stock** en PDF.
- Aviso legal / términos de uso.
- Acceso al panel admin protegido con usuario y contraseña (varios
  administradores posibles).
- Panel admin con navegación lateral: Inicio, Analítica (gráficos), Catálogo,
  Reservas, Stock, Usuarios y Configuración.
- Módulo de **Usuarios y roles**: crear roles con permisos específicos y
  cuentas de acceso al panel para el equipo.
- **Todo el texto del sitio público es editable desde el panel** (pestaña
  Configuración): nombre del negocio, portada (título, subtítulo, botones
  y estadísticas), encabezados de cada sección, historia de la empresa,
  servicios, datos de contacto y aviso legal — todo se edita ahí y se
  guarda en el backend; el sitio público lo muestra al instante, sin
  tocar código ni volver a compilar.

## Estructura

```
maykel_flutter/
  backend/    — servidor Dart (shelf) con la API REST y la base de datos PostgreSQL
  app/        — app Flutter Web (catálogo público + panel admin)
```

Cada carpeta tiene su propio `README.md` con instrucciones detalladas de
instalación y ejecución:

- [`backend/README.md`](backend/README.md)
- [`app/README.md`](app/README.md)

Documentación del proyecto en [`docs/`](docs/): [manual de usuario](docs/MANUAL_USUARIO.md),
[**llevar el proyecto a otro PC**](docs/GUIA_OTRO_PC.md),
[**guía para estudiar el código**](docs/GUIA_DEL_CODIGO.md),
[despliegue en producción](docs/DESPLIEGUE.md) y
[estado del proyecto y trazabilidad](docs/ESTADO_PROYECTO.md).

## Inicio rápido

Necesitas [Flutter](https://docs.flutter.dev/get-started/install) (incluye
Dart) y [PostgreSQL](https://www.postgresql.org/download/).
Con todo instalado y el `backend/.env` listo, **un solo comando** enciende la página
(compila la web si hace falta y arranca el servidor en `http://localhost:8080`):

```powershell
powershell -ExecutionPolicy Bypass -File iniciar.ps1
```

Paso a paso, a mano:

```bash
# 1. Base de datos: crea la base y carga tablas + datos de ejemplo
createdb -U postgres maykel_repuestos2
psql -U postgres -d maykel_repuestos2 -f backend/database/schema.sql

# 2. Compila la app Flutter
cd app
flutter pub get
flutter build web --no-web-resources-cdn

# 3. Configura y corre el backend (sirve la API y la app, todo en un puerto)
cd ../backend
cp .env.example .env      # pon tu clave de PostgreSQL en DB_PASS y define JWT_SECRET y SYNC_API_TOKEN
dart pub get
dart run bin/server.dart
```

Abre `http://localhost:8080` en tu navegador. Para entrar al panel usa el
enlace **Admin** con `admin` / `maykel2026` (ver más usuarios en
[`backend/README.md`](backend/README.md)).

`--no-web-resources-cdn` deja los archivos del motor gráfico dentro del
build, así el sitio funciona aunque no haya internet en la presentación.

### Fotos de productos

- **Foto propia:** una a una desde Admin → Stock, o en lote con el importador por SKU (más abajo).
- **Foto referencial:** mientras un producto no tenga foto propia, la web muestra una imagen
  genérica según su categoría (filtro, pastillas, batería…), marcada como *"Imagen referencial"*.
  Son fotos de Wikimedia Commons con licencia libre; los créditos están en
  `app/assets/images/repuestos/CREDITOS.md`. Cuando suban la foto real, esa reemplaza a la referencial.
- Una a una: Admin → Stock → ícono de foto de cada fila (JPG/PNG/WebP, máx. 3 MB).
- En lote: nombra cada archivo con el SKU (`MR-001.jpg`) y ejecuta
  `cd backend` y `dart run tools\importar_imagenes.dart C:\fotos` (agrega
  `--simular` para ver qué haría sin cambiar nada). Se guardan en
  `backend/uploads/productos/` (excluida de Git: respáldala al desplegar).

### Cómo se comporta el panel y el inventario

- **Sesión:** el administrador sigue con sesión al refrescar la página (el token vive en
  `sessionStorage`, se renueva en `/api/auth/refresh` y se cierra al cerrar la pestaña).
  Si el servidor la rechaza (venció o desactivaron al usuario) vuelve al inicio con un aviso.
- **Inventario al día:** el sync con el sistema del cliente corre cada 30 min
  (tarea `MaykelRepuestos-Sync`). El panel se refresca solo cada minuto y la portada cada
  2 min; ambos muestran "sincronizado hace X" y avisan si pasan más de 2 h sin novedades.
- **Stock paginado:** el servidor entrega 25 productos por página con búsqueda y filtros
  (agotados, stock bajo, sin precio, sin foto, ocultos). Solo se guardan las filas editadas.
- **Reservas y stock:** una reserva nueva queda *pendiente* y no toca el stock. Al pasar a
  *confirmada* o *entregada* el stock se descuenta (una sola vez); si se *rechaza* o vuelve a
  *pendiente* se repone. Si no alcanza el stock, el panel avisa y no cambia nada. Mientras una
  reserva está *confirmada*, el sync de 30 min no devuelve esas unidades al stock.
- **Reservas y Analítica:** *confirmada* aparece como "Por retirar" (unidades y valor apartados);
  *entregada* se registra como una venta (suma a ventas, monto, gráfico de 14 días y ventas por
  categoría). Si la reserva deja de estar entregada, esa venta se anula.
- **Horas:** la base guarda las fechas en UTC; el panel las muestra en la hora local del navegador.
- **Eliminar = ocultar:** así el sync no vuelve a publicar un producto retirado.
- **Base de datos:** `backend/database/migraciones.sql` se aplica solo al arrancar el servidor
  (índices de búsqueda, integridad). Los logs antiguos se limpian automáticamente.
- **Mantenimiento:** `tools\rotar_secretos.dart`, `tools\respaldo.ps1`,
  `tools\reporte_calidad.dart` y `tools\prueba_carga.dart` (ver `docs/DESPLIEGUE.md`).
