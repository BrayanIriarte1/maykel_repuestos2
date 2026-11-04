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
[despliegue en producción](docs/DESPLIEGUE.md) y
[estado del proyecto y trazabilidad](docs/ESTADO_PROYECTO.md).

## Inicio rápido

Necesitas [Flutter](https://docs.flutter.dev/get-started/install) (incluye
Dart) y [PostgreSQL](https://www.postgresql.org/download/).

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
