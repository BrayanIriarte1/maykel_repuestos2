# Guía del código: cómo está armado y cómo estudiarlo

Está escrita para **aprender de a poco**. No necesitas memorizar nada: necesitas saber **dónde mirar**.

---

## 1. La idea general en 30 segundos

```
 Navegador (Chrome)                Servidor (tu PC)                       Base de datos
┌───────────────────┐   HTTP    ┌──────────────────────────┐   SQL    ┌──────────────┐
│ Flutter Web (app/)│ ───────►  │ API en Dart (backend/)   │ ───────► │ PostgreSQL   │
│ portada + panel   │ ◄───────  │ backend/bin/server.dart  │ ◄─────── │ maykel_...2  │
└───────────────────┘   JSON    └──────────────────────────┘          └──────────────┘
                                       ▲        │ guarda/lee fotos
   Sistema del cliente (Laravel)       │        ▼
   sistema.maykelrepuestos.cl ──► Agente de sync (tools/sync_agent.dart, cada 30 min)
```

- **Un solo programa sirve todo**: `server.dart` responde la API (`/api/...`), entrega la web compilada (`app/build/web`) y las fotos (`/media/...`). Por eso con una sola ventana abierta funciona toda la página.
- **Flutter no se ejecuta en el servidor**: se **compila** (`flutter build web`) a archivos HTML/JS y el servidor solo los entrega.
- El **agente de sync** es un programa aparte que *lee* el inventario del cliente y se lo manda a nuestra API en lotes de 200.

---

## 2. Mapa de carpetas (qué hay y para qué sirve)

```
maykel_repuestos2/
├─ iniciar.ps1                  ← enciende todo (compila web si falta + servidor)
├─ app/                         ← FRONTEND (Flutter / Dart)
│  ├─ pubspec.yaml              ← paquetes y assets (imágenes)
│  ├─ assets/images/            ← logo y fotos referenciales (repuestos/ + CREDITOS.md)
│  └─ lib/
│     ├─ main.dart              ← arranque: restaura sesión, rutas (#/admin)
│     ├─ config.dart            ← colores (AppColors), tema, kApiBase
│     ├─ models.dart            ← clases de datos: Repuesto, Reserva, Venta, DashboardData, ContenidoSitio…
│     ├─ api_service.dart       ← TODAS las llamadas HTTP al backend
│     ├─ screens/
│     │  ├─ home_screen.dart    ← portada pública (hero, marcas, categorías, catálogo…)  ~1500 líneas
│     │  ├─ admin_screen.dart   ← panel admin/vendedor (sidebar, Inicio, Analítica, Config…) ~2750 líneas
│     │  └─ aviso_legal_screen.dart
│     ├─ widgets/               ← piezas reutilizables
│     │  ├─ product_card.dart, carrusel_productos.dart, reserva_dialog.dart
│     │  ├─ admin_login_dialog.dart, admin_inventario.dart (tabla de stock), admin_reservas.dart
│     │  ├─ diseno.dart         ← Revelar, Marquesina, TarjetaMarca/Categoría/Info, fotos referenciales
│     │  └─ efectos.dart        ← HoverLift, TituloSeccion, Centrado, iconos por categoría
│     └─ utils/                 ← formato CLP, PDF, almacenamiento de sesión (sessionStorage)
├─ backend/                     ← BACKEND (Dart + shelf)
│  ├─ pubspec.yaml              ← paquetes del servidor
│  ├─ .env                      ← claves (NO está en GitHub). Plantilla: .env.example
│  ├─ bin/server.dart           ← LA API COMPLETA (~2300 líneas)  ← el archivo más importante
│  ├─ lib/
│  │  ├─ db.dart                ← conexión a PostgreSQL (pool) + lee .env + aplica migraciones
│  │  ├─ seguridad.dart         ← bcrypt (claves), JWT (sesiones), límite de intentos
│  │  ├─ notificador.dart       ← correo SMTP y WhatsApp al llegar una reserva
│  │  ├─ pdf_reserva.dart       ← comprobante PDF
│  │  └─ vehiculos.dart         ← deduce marca/modelo desde el nombre del producto
│  ├─ database/
│  │  ├─ schema.sql             ← crea las tablas + datos de ejemplo (instalación desde cero)
│  │  └─ migraciones.sql        ← cambios que se aplican solos al arrancar (índices, columnas)
│  ├─ tools/                    ← programas de apoyo (sync, respaldo, importar fotos, reportes…)
│  ├─ test/                     ← pruebas automáticas (api_test.dart, unit_test.dart)
│  └─ docs/openapi.yaml         ← documentación de la API (se ve en /api/docs)
└─ docs/                        ← manuales (esta guía, GUIA_OTRO_PC, DESPLIEGUE, MANUAL_USUARIO…)
```

---

## 3. El backend por dentro (`backend/bin/server.dart`)

### 3.1 Cómo entra una petición (el "pipeline")
Al final del archivo (busca `final pipeline = const Pipeline()`), cada petición pasa **en este orden**:

1. `logRequests()` → escribe una línea en la consola por cada petición.
2. `_cabecerasSeguras()` → agrega cabeceras de seguridad y *no-cache* a la API.
3. `_erroresComoJson()` → si algo falla, responde JSON (400/500) en vez de caerse.
4. `corsHeaders(...)` → permisos para que un navegador de otro dominio pueda llamar (ver `CORS_ORIGIN`).
5. `_authSoloAdmin()` → **el guardia**: si la ruta empieza con `/api/admin/`, exige un token válido y el permiso del rol.
6. El **router** → busca la ruta (`router.get('/api/...')`) y ejecuta su función.

### 3.2 Secciones del archivo (búscalas por su comentario `// N. ...`)
| Busca este comentario | Qué contiene |
|---|---|
| `// ---------- Contraseñas` | `hashPassword`, `verificarPassword` |
| `permisoPorRuta` | Qué permiso exige cada grupo de rutas admin |
| `// ---------- Contenido por defecto` | Textos de la web si la base no tiene nada guardado |
| `_validarCredenciales`, `_sesionDesdeToken`, `_refrescarSesion` | Login y sesión (JWT) |
| `// 1. HEALTHCHECK…` | `/api/health`, `/api/estado`, `/api/contenido` |
| `// 2. ENDPOINTS DE TAXONOMÍA` | marcas, categorías, modelos |
| `// 3. CATÁLOGO UNIFICADO` | `/api/repuestos` (público, **sin precios**) y `/api/catalogo/filtros` |
| `// 5. EMISIÓN Y GESTIÓN DE RESERVAS` | Crear reserva (público) y cambiar estado (admin) |
| `// 6. BACKOFFICE` | CRUD de productos, fotos, guardado masivo de precio/stock |
| `// 7. LOGIN, ROLES Y USUARIOS` | roles y usuarios del panel |
| `// 8. PIPELINE ETL` | Recibe el sync (`POST /api/v1/sync/inventory`) |
| `// 9. DASHBOARD…` | KPIs de Analítica |
| `// VENTAS EN SUCURSAL` | Registrar ventas |

### 3.3 Reglas del negocio que debes saber (están en el código)
- **Precios ocultos**: el catálogo público siempre devuelve `precio: 0`; el precio real solo lo ve el panel (`precio_referencia`).
- **Reservar NO descuenta stock.** El stock se mueve al cambiar el estado de la reserva (`PUT /api/admin/reservas/<id>`):
  | Estado | Efecto |
  |---|---|
  | `pendiente` | nada |
  | `confirmada` | descuenta (una vez, marca `stock_descontado=true`) |
  | `entregada` | además crea una **venta** (cuenta en Analítica) |
  | `rechazada` / volver a `pendiente` | repone el stock y anula la venta |
- **El sync manda sobre precio y stock**: cada 30 min el stock se reemplaza por el del cliente, **menos** lo retenido por reservas confirmadas.
- **"Eliminar" un producto = ocultarlo** (`estado_catalogo='OCULTO'`), porque el sync lo volvería a crear. `?definitivo=1` lo borra de verdad (solo si no tiene reservas).
- **Stock bajo = 3 unidades o menos.** El número 3 aparece en: dashboard (SQL en `construirDatosDashboard`), `admin_inventario.dart`, `product_card.dart` y `home_screen.dart` (`_ultimas`).

### 3.4 Seguridad (qué hace cada pieza)
- **Claves de usuarios**: bcrypt (`seguridad.dart`). Nunca se guardan en texto.
- **Sesión**: token **JWT** firmado con `JWT_SECRET`, dura 8 h (`JWT_HORAS`). El navegador lo manda en `Authorization: Bearer ...`.
- **Roles**: cada rol es una lista de permisos (`dashboard, catalogo, reservas, stock, usuarios, configuracion`). Si agregas un permiso, debe estar en **dos** listas iguales: `permisosDisponibles` (server.dart) y `kPermisosDisponibles` (models.dart).
- **Anti fuerza bruta**: 5 intentos fallidos por usuario+IP → bloqueo de 15 min (`LimitadorIntentos`).
- **Auditoría**: cada acceso admin queda en `logs_auditoria`.
- **Sync**: solo acepta el token `SYNC_API_TOKEN`.

---

## 4. La base de datos (PostgreSQL)

| Tabla | Para qué sirve | Detalles que importan |
|---|---|---|
| `productos` | Catálogo | `codigo_interno` = SKU (único) · `precio_referencia` · `stock_actual` · `es_agotado` (calculado solo: stock ≤ 0) · `estado_catalogo` (`PUBLICADO` / `OCULTO` / `PENDIENTE`) · `imagen_url` |
| `categorias` | Categorías | Se crean solas al sincronizar |
| `marcas`, `modelos`, `versiones_vehiculo`, `producto_compatibilidad` | Compatibilidad vehicular | Hoy se usan poco; la marca/modelo real está en `productos.marca_referencia/modelo_referencia` |
| `reservas` + `reserva_detalles` | Reservas (cabecera + líneas) | `folio` (RES-xxxx) automático · `stock_descontado` |
| `ventas` | Ventas | `reserva_id` si nació de una reserva entregada |
| `usuarios`, `roles` | Panel | `roles.permisos` es JSON |
| `configuracion_sitio` | Textos editables de la web | Una fila `principal` con JSON |
| `logs_sincronizacion` | Una fila por sync exitoso | Alimenta "Sync hace X min" |
| `logs_auditoria` | Quién entró a qué | |
| `metricas_demanda` | Búsquedas sin resultado, clics en agotados | Alimenta Analítica |

- `schema.sql` **borra y recrea** todo (úsalo solo en una base vacía).
- `migraciones.sql` es **seguro de repetir**: el servidor lo ejecuta al arrancar (`db.migrar`). Si necesitas una columna nueva, agrégala ahí con `ADD COLUMN IF NOT EXISTS`.

---

## 5. El frontend por dentro (`app/lib`)

- **Estado**: se usa `setState` simple (no hay librerías de estado). Cada pantalla es un `StatefulWidget` que carga sus datos en `initState` y los guarda en variables (`_reservas`, `_dashboard`…).
- **`main.dart`**: antes de dibujar, llama `ApiService.instance.restaurarSesion()` (por eso refrescar no te saca). Define las rutas `/` y `/admin`.
- **`api_service.dart`**: un solo lugar para hablar con el backend. Todas las peticiones pasan por `_ClienteApi`: si el servidor responde **401** con sesión activa, cierra la sesión y avisa. Para agregar un endpoint nuevo: un método aquí + su modelo en `models.dart`.
- **`models.dart`**: clases con `fromJson`. `SiteContent.actual` guarda los textos editables que se muestran en la portada.
- **`config.dart`**: **colores** (`AppColors`), tema general y `kApiBase`.
- **`home_screen.dart`**: el orden de las secciones está en el método `build` (lista `children`); cada sección es un método `_buildAlgo()`.
- **`admin_screen.dart`**: el menú lateral sale de la lista `_secciones`; la pantalla activa la decide `_buildContenido()`. Cada pestaña es un método `_buildXTab()` o un widget aparte (`InventarioAdmin`, `ReservasPanel`).
- **Refrescos automáticos** (Timers): panel cada 30 s, tabla de stock cada 60 s, portada cada 2 min, token cada 30 min.

---

## 6. Tres recorridos completos (síguelos con el código abierto)

**① Un cliente reserva**
`product_card.dart` (botón *Reservar*) → `reserva_dialog.dart` → `ApiService.crearReserva` → `POST /api/reservas` (server.dart, sección 5: valida datos, inserta en `reservas` y `reserva_detalles` dentro de una transacción) → en segundo plano `Notificador` manda correo/WhatsApp → responde con el folio.

**② El vendedor confirma y entrega**
`admin_reservas.dart` (botones) → `_cambiarEstadoReserva` en `admin_screen.dart` → `ApiService.actualizarEstadoReserva` → `PUT /api/admin/reservas/<id>` (descuenta stock / crea venta en una transacción) → el panel se vuelve a cargar (`_cargarResumen`) y Analítica muestra la venta.

**③ Se sincroniza el inventario**
Tarea programada → `tools/sync_programado.ps1` → `tools/sync_agent.dart --sistema` (entra al sistema del cliente, lee la bodega 1, arma lotes de 200) → `POST /api/v1/sync/inventory` → server.dart sección 8 (actualiza stock/precio, crea productos nuevos, resta lo retenido por reservas) → una fila en `logs_sincronizacion`.

---

## 7. Recetas: "quiero cambiar X, ¿dónde toco?"

| Quiero… | Dónde |
|---|---|
| Cambiar un **texto** de la portada | Lo más fácil: **Admin → Configuración**. Los valores por defecto están en `models.dart` (`ContenidoSitio.porDefecto`) y `server.dart` (`contenidoPorDefecto`) |
| Cambiar **colores** | `app/lib/config.dart` → `AppColors` |
| Cambiar el **orden o quitar una sección** de la portada | `home_screen.dart` → método `build` |
| Cambiar el **umbral de stock bajo** (3) | Los 4 lugares de §3.3 |
| Agregar una **pestaña al panel** | 1) `_secciones` en `admin_screen.dart`, 2) un `case` en `_buildContenido()`, 3) su método `_buildXTab()`, 4) si necesita permiso nuevo, §3.4 |
| Agregar un **endpoint** | `server.dart` (`router.get/post/put/delete`) → documéntalo en `docs/openapi.yaml` → método en `api_service.dart` → test en `api_test.dart` |
| Agregar un **campo** a un producto | `migraciones.sql` (`ADD COLUMN IF NOT EXISTS`) → consultas SQL del server que lo usan → `models.dart` (`Repuesto.fromJson`) → pantalla |
| Agregar una **foto referencial** nueva | Archivo en `app/assets/images/repuestos/` + regla en `diseno.dart` (`_reglasImagen`) + línea en `CREDITOS.md` |
| Cambiar la **frecuencia del sync** | `powershell -ExecutionPolicy Bypass -File tools\instalar_sync.ps1 -Minutos 15` |
| Cambiar el **máximo de fotos** o tamaño | `_maxBytesImagen` en `server.dart` |
| Agregar una **marca** al filtro | No hace falta: sale sola de `productos.marca_referencia`. Si el sync no la detecta, edita `lib/vehiculos.dart` |

---

## 8. Plan de estudio sugerido (7 sesiones)

1. **Encender y mirar** (1 h): `iniciar.ps1`, recorre la página y el panel, abre `/api/docs`, revisa `psql` con las consultas de la guía de traslado. Objetivo: ver el sistema funcionando.
2. **La base de datos** (1–2 h): lee `schema.sql`; ejecuta `select` a cada tabla; entiende `productos`, `reservas`, `ventas`.
3. **Una ruta simple de punta a punta** (2 h): `GET /api/estado`. Búscala en `server.dart`, léela, llámala en el navegador y en `/api/docs`.
4. **Reservas** (2–3 h): el recorrido ① y ② de §6, leyendo el código real. Es el corazón del negocio.
5. **Seguridad** (1–2 h): `seguridad.dart` + `_authSoloAdmin`. Haz login con `curl` o desde `/api/docs` y mira el token.
6. **Frontend** (3 h): `main.dart` → `api_service.dart` → una pantalla pequeña (`admin_reservas.dart`). Cambia un color y recompila para ver el efecto.
7. **Sync y pruebas** (2 h): `sync_agent.dart` y `api_test.dart`. Rompe algo a propósito y mira cómo lo detecta `dart test`.

**Ejercicios cortos** (haz uno por sesión, después de cada uno corre `dart analyze`, `flutter analyze` y `dart test`):
- Cambia el texto del botón *Reservar* por *Apartar*.
- Muestra el SKU en la tarjeta del carrusel principal.
- Agrega un filtro "Con foto" en la tabla de Stock (pista: ya existe `sinfoto`).
- Cambia el nombre del estado "Por retirar" por otro texto (pista: `kEstadosReserva` en `admin_reservas.dart`).

### Cómo depurar (encontrar errores)
- **Backend**: mira la consola donde corre `iniciar.ps1`; cada petición aparece con su código (`[200]`, `[400]`, `[500]`). Un 500 imprime el error.
- **Frontend**: en Chrome, `F12` → pestañas **Console** (errores) y **Network** (ve cada petición y su respuesta).
- **Base de datos**: `psql` para comprobar qué quedó guardado.
- **Antes de subir cambios**: `dart analyze` (backend), `flutter analyze` (app), `dart test`.

---

## 9. Mini glosario

| Palabra | Significa |
|---|---|
| **API** | Las "ventanillas" del servidor a las que el navegador pide datos (`/api/...`) |
| **Endpoint / ruta** | Una de esas ventanillas |
| **JSON** | Formato de texto en que viajan los datos |
| **JWT / token** | "Carné" firmado que prueba quién eres sin volver a pedir la clave |
| **bcrypt** | Forma de guardar claves de manera que nadie las pueda leer |
| **Middleware** | Un filtro por el que pasa cada petición |
| **Transacción** | Varias operaciones SQL que se guardan **todas o ninguna** |
| **Pool** | Grupo de conexiones a la base que se reutilizan |
| **Migración** | Un cambio a la estructura de la base de datos |
| **Widget** | Una pieza de pantalla en Flutter |
| **SKU** | Código interno del producto (`codigo_interno`) |
| **Sync / ETL** | Copiar el inventario del cliente a nuestra base |
| **`.env`** | Archivo con claves y configuración que no se sube a GitHub |

---

## 10. Pendientes conocidos (para que no te sorprendan)

- Faltan las claves de **correo (`SMTP_PASS`)** y **WhatsApp** para que lleguen avisos de reservas.
- Cambiar claves demo y la contraseña del sistema del cliente (ver `GUIA_OTRO_PC.md`, sección D).
- Subir fotos reales de productos (hoy hay fotos referenciales por categoría).
- 71 productos sin precio y 1.135 sin marca (archivo `reporte_calidad` para el cliente).
- Despliegue con dominio y HTTPS (`DESPLIEGUE.md`).
- Las pestañas **Usuarios** y **Configuración** del panel aún no tienen el rediseño nuevo.
