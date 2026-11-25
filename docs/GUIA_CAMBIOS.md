# Guía práctica: cómo hacer cambios en la página

Esta guía es para cuando te piden: *"cámbiame este logo"*, *"cambia esta palabra"*, *"ponle otro color a esta parte"*.
Para entender el sistema completo (servidor, base de datos, reservas, sync) lee también [GUIA_DEL_CODIGO.md](GUIA_DEL_CODIGO.md).

> **Truco que sirve para todo:** abre la carpeta del proyecto en VS Code y aprieta **Ctrl+Shift+F** (buscar en todos los archivos).
> Escribe la palabra exacta que ves en la página (por ejemplo `Productos destacados`) y VS Code te lleva al archivo y la línea donde está.
> Los números de línea de esta guía son **aproximados** (cambian cuando se edita el código); lo que no cambia es el texto que hay que buscar.

---

## 1. Cómo funciona la página (versión corta)

```
 El navegador abre https://maykel-repuestos2.cl
        │
        ▼
 app/lib/main.dart ──► arranca la app y decide la pantalla:
        │                 "/"       → portada pública  (screens/home_screen.dart)
        │                 "/#/admin" → panel admin      (screens/admin_screen.dart)
        ▼
 home_screen.dart ──► initState(): pide los datos al servidor (api_service.dart)
        │              y muestra el flyer (widgets/flyer_sucursal.dart)
        ▼
 build(): dibuja la portada como una lista de secciones, de arriba hacia abajo
```

- **`app/`** es la página (Flutter, lenguaje Dart). Lo que ves en el navegador sale de aquí.
- **`backend/`** es el servidor (también Dart): entrega los productos, guarda reservas y textos editables.
- Flutter **se compila**: después de cambiar algo en `app/` hay que volver a compilar para verlo (ver §5).

### Las secciones de la portada, en orden

Están en `build()` de [home_screen.dart](../app/lib/screens/home_screen.dart) (busca `for (final seccion in <Widget>[`). Cada una es un método:

| # | Lo que ves en la página | Método (búscalo en `home_screen.dart`) |
|---|---|---|
| — | Barra de arriba (logo, menú Historia/Marcas/…, botón Admin) | `_buildNavbar` |
| 1 | Portada: "REPUESTOS QUE MUEVEN CALAMA", botones, carrusel | `_buildHero` |
| 2 | Cinta roja con avisos que se mueve | `_buildMarquesina` |
| 3 | Tarjetas "Retiro en sucursal", "Reserva en línea"… + cifras + "¿No encuentras tu repuesto?" | `_buildInfoCards` |
| 4 | "Productos destacados" | `SeccionCarrusel(... titulo: 'Productos destacados')` |
| 5 | "¿Buscas un repuesto para marcas chinas?" + cintas de logos | `_buildMarcasRapidas` (usa `widgets/cinta_marcas.dart`) |
| 6 | "Desde 2015 moviendo a Calama" | `_buildHistoria` |
| 7 | Servicios | `_buildServicios` |
| 8 | "Últimas unidades" | `SeccionCarrusel(... titulo: 'Últimas unidades')` |
| 9 | Categorías con foto | `_buildCategoriasRapidas` |
| 10 | Pasos "Busca tu repuesto…" | `_buildPasos` |
| 11 | Catálogo con buscador y filtros | `_buildCatalogo`, `_buildPanelBusqueda`, `_buildFiltros` |
| 12 | Contacto (WhatsApp, correo, mapa) | `_buildContacto` |
| 13 | Pie de página | `_buildFooter` |
| — | Ventana del flyer al abrir | `widgets/flyer_sucursal.dart` |

**Quitar o mover una sección** = borrar o cambiar de lugar su línea en esa lista.

### Archivos que más vas a tocar

| Archivo | Para qué |
|---|---|
| `app/lib/config.dart` | **Colores** de toda la página (`AppColors`) y tema |
| `app/lib/screens/home_screen.dart` | **Portada**: textos fijos, orden de secciones, tamaños |
| `app/lib/widgets/flyer_sucursal.dart` | **Flyer** al abrir: imagen, textos, número de WhatsApp |
| `app/lib/widgets/cinta_marcas.dart` | **Cinta de logos** de marcas (velocidad, tamaño) |
| `app/lib/widgets/diseno.dart` | Piezas de diseño: lista de **logos de marcas**, fotos de categorías, tarjetas |
| `app/lib/widgets/product_card.dart` | La **tarjeta de cada producto** |
| `app/lib/widgets/portada_extra.dart` | Íconos de redes, horario, botón de WhatsApp |
| `app/assets/images/` | **Imágenes**: logo, flyer, logos de marcas, fotos de categorías |
| `app/web/index.html`, `app/web/manifest.json` | **Título de la pestaña**, ícono, descripción para Google |

---

## 2. Cambiar un TEXTO

### Paso 1: ¿se puede cambiar desde el panel? (sin tocar código)
Entra a `https://maykel-repuestos2.cl/#/admin` → **Configuración**. Ahí se editan, y se ven al instante sin compilar:

- Nombre del negocio, **título principal y subtítulo** de la portada
- Texto de los botones «Ver catálogo» y «Contáctanos»
- Las 3 **cifras** de la portada (etiquetas y valores)
- **Título y subtítulo de la sección de marcas** ("¿Buscas un repuesto para marcas chinas?")
- Encabezado del catálogo y texto del buscador
- **Historia** (título, texto y fichas), **Servicios**, **Contacto** (WhatsApp, correo, dirección, mapa, horario)
- Pie de página y **Aviso legal**

> Si el texto está en esta lista, **cámbialo desde el panel**, no en el código. Si lo cambias en el código, el panel lo seguirá tapando con el valor guardado en la base de datos.

### Paso 2: si no está en el panel, está escrito en el código
1. **Ctrl+Shift+F** → escribe el texto tal como se ve (respeta tildes y mayúsculas).
2. Cambia solo lo que está **entre comillas** `'...'`.
3. Compila y revisa (§5).

**Ejemplo:** el profesor dice *"cambia «Productos destacados» por «Lo más vendido»"*.
Buscas `Productos destacados` → aparece en `home_screen.dart`, cerca de la línea 883:
```dart
kicker: 'Lo más buscado',
titulo: 'Productos destacados',     // ← cambia esto por 'Lo más vendido'
```

**Textos fijos frecuentes y dónde están:**

| Texto en la página | Archivo | Busca |
|---|---|---|
| "Productos destacados" / "Lo más buscado" | `home_screen.dart` | `'Productos destacados'` |
| "Últimas unidades" | `home_screen.dart` | `'Últimas unidades'` |
| "Retiro en sucursal" y las otras tarjetas | `home_screen.dart` | `'Retiro en sucursal'` (método `_buildInfoCards`) |
| "¿No encuentras tu repuesto?" | `home_screen.dart` | `¿No encuentras tu repuesto` |
| Avisos de la cinta roja ("Retiro en Vargas…") | `home_screen.dart` | método `_buildMarquesina` |
| Menú de arriba ("Historia", "Marcas"…) | `home_screen.dart` | `EnlaceNav(` |
| Botón "Escríbenos" | `home_screen.dart` | `'Escríbenos'` |
| "¡Y muchas marcas más!" (flyer) | `flyer_sucursal.dart` | `muchas marcas más` |
| Mensaje que llega por WhatsApp desde el flyer | `flyer_sucursal.dart` | `_mensajeWhatsapp` |
| Botón "Agregar a reserva" (y "Agotado · Me interesa") | `product_card.dart` (tarjetas) y `carrusel_productos.dart` (carrusel principal) | `Agregar a reserva` |
| **Título de la pestaña del navegador** | `app/web/index.html` | `<title>` |
| Nombre al instalar en el celular | `app/web/manifest.json` | `"name"` y `"short_name"` |

> **Cuidado con las comillas:** si el texto lleva un apóstrofo, escríbelo con `\'` (ej.: `'Maykel\'s'`), o el código no compila.

---

## 3. Cambiar un LOGO o una IMAGEN

**Regla de oro:** si reemplazas la imagen por otra con **el mismo nombre de archivo**, no hay que tocar nada de código. Solo copias el archivo, compilas y despliegas.

| Imagen | Archivo | Dónde aparece |
|---|---|---|
| **Logo principal** "Maykel Repuestos II" | `app/assets/images/logo_maykel.jpg` | Barra de arriba, pie de página, ventana de login y panel admin |
| **Flyer** de la casa matriz | `app/assets/images/flyer_sucursal.jpg` | Ventana que aparece al abrir |
| **Ícono de la pestaña** del navegador | `app/web/favicon.png` (64×64 px) | Pestaña del navegador |
| Ícono al "instalar" en el celular | `app/web/icons/Icon-192.png`, `Icon-512.png` (y los `maskable`) | Pantalla de inicio del celular |
| **Logos de marcas de autos** | `app/assets/images/marcas/<nombre>.png` | Cinta de marcas |
| Fotos de categorías (aceites, frenos…) | `app/assets/images/repuestos/<nombre>.jpg` | Tarjetas de categorías y productos sin foto |

**Ejemplo 1: "cambia el logo de la página".**
1. Pide el logo nuevo, idealmente PNG o JPG de unos 800 px de ancho.
2. Guárdalo como `app/assets/images/logo_maykel.jpg` (reemplazando el anterior). Si viene en PNG, o lo conviertes a JPG o cambias `logo_maykel.jpg` por `logo_maykel.png` en los 4 lugares (busca `logo_maykel`) **y** en `app/pubspec.yaml`.
3. Si el logo nuevo es más alto o más bajo, ajusta su tamaño: en `home_screen.dart` busca `logo_maykel.jpg` y cambia `height: esAngosto ? 46 : 74` (46 = celular, 74 = computador).

**Ejemplo 2: "cambia el logo de Chery" o "agrega el logo de una marca nueva".**
1. Guarda el logo en `app/assets/images/marcas/`, en PNG con **fondo transparente** (ej.: `kia.png`).
2. En `app/lib/widgets/diseno.dart`, busca `_logosMarca` y agrega una línea con el nombre de la marca **en MAYÚSCULAS, igual que en el inventario**, y el nombre del archivo sin `.png`:
   ```dart
   'KIA': 'kia',
   ```
3. Las marcas que no tienen logo se muestran con su nombre en letras. La lista de marcas sale sola del inventario (las 30 con más productos).

**Ejemplo 3: "cambia el flyer por uno nuevo".**
Reemplaza `app/assets/images/flyer_sucursal.jpg`. Si el flyer nuevo **no mide 1236×1600** (u otra imagen con la misma proporción), cambia en `flyer_sucursal.dart` la línea `static const _proporcion = 1236 / 1600;` por `ancho / alto` de la imagen nueva.
Si el "¡COTIZA AQUÍ!" impreso cambia de lugar, ajusta la zona tocable (busca `El "¡COTIZA AQUÍ!" impreso`): `left/top/width/height` son fracciones de la imagen (0.04 = 4 % desde la izquierda).

> **Tamaño de imágenes:** usa fotos de menos de ~200 KB. Imágenes pesadas vuelven lenta la página en el celular.

---

## 4. Cambiar un COLOR

### Cómo se escribe un color
`Color(0xFFD91E2B)` = `0xFF` (opaco) + el código HTML del color sin `#` (`D91E2B`).
Para elegir un color usa cualquier "color picker" (por ejemplo, busca *color picker* en Google), copia el código `#RRGGBB` y escríbelo como `Color(0xFFRRGGBB)`.

### Cambiar un color en TODA la página
Todos los colores principales están en `app/lib/config.dart`, clase `AppColors`:

| Nombre | Color actual | Se usa en |
|---|---|---|
| `red` | `#D91E2B` rojo | Botones, títulos destacados, línea bajo los títulos, bordes al pasar el mouse |
| `redDark` | `#9E1119` rojo oscuro | Degradados de botones y del flyer |
| `char` | `#1A1A1C` casi negro | Texto principal, fondos oscuros |
| `char2` | `#242427` | Fondos oscuros secundarios |
| `steel` | `#767B84` gris | Textos secundarios (subtítulos) |
| `paper` | `#F2EFE9` crema | Fondo general de la página |
| `paper2` | `#E7E2D8` | Bordes suaves de tarjetas |
| `yellow` | `#FF5A64` rojo claro (no es amarillo, el nombre es histórico) | Acentos sobre fondos oscuros |
| `ok` / `warn` / `bad` | verde / ámbar / rojo | Estados: disponible, poco stock, agotado |

**Ejemplo:** *"quiero que el rojo sea más oscuro"* → en `config.dart`:
```dart
static const Color red = Color(0xFFB71C1C);   // antes 0xFFD91E2B
```
Esto cambia el rojo en toda la página de una vez. Si también quieres cambiar el color de la barra del celular, cambia `"theme_color"` en `app/web/manifest.json`.

### Cambiar el color de UNA sola parte
1. Encuentra la sección en la tabla de §1 (ej.: barra de arriba = `_buildNavbar`).
2. Dentro de ese método busca `color:`, `gradient:` o `backgroundColor:`.
3. Cambia **solo ahí** el color, por ejemplo `AppColors.red` por `Color(0xFF1565C0)`.

**Ejemplos:**
- **Fondo de la barra de arriba:** en `_buildNavbar` está
  `gradient: LinearGradient(colors: [Color(0xFF141416), Color(0xFF241013), Color(0xFF141416)])`.
  Es un degradado de 3 colores (izquierda, centro, derecha). Para que sea de un solo color, pon los tres iguales.
- **Fondo de la sección de marcas:** en `_buildMarcasRapidas` cambia `color: Colors.white` (y en la llamada a `CintaMarcas` agrega `fondo: <el mismo color>`, así el difuminado de los bordes coincide).
- **Verde de WhatsApp:** es `Color(0xFF25D366)`; búscalo con Ctrl+Shift+F (aparece en `home_screen.dart`, `flyer_sucursal.dart` y `portada_extra.dart`).
- **Franja roja del flyer:** en `flyer_sucursal.dart`, `_PanelInferior` → `gradient: LinearGradient(colors: [AppColors.red, AppColors.redDark])`.

---

## 5. Otros cambios comunes

| Quiero… | Dónde y qué cambiar |
|---|---|
| **Tamaño de un texto** | Su `TextStyle(fontSize: ...)`. Muchas veces dice `esAngosto ? 28 : 40` = 28 en celular, 40 en computador (`esAngosto` = pantalla de menos de 760 px de ancho) |
| Poner un texto en **negrita** o normal | `fontWeight: FontWeight.w900` (muy negrita) … `FontWeight.w400` (normal) |
| **Velocidad de la cinta de logos** | `cinta_marcas.dart` → `this.velocidad = 45` (píxeles por segundo; más = más rápido) |
| **Tamaño de los logos** en la cinta | `home_screen.dart` → `_buildMarcasRapidas` → `final alto = esAngosto ? 56.0 : 80.0;` |
| Velocidad de la **cinta roja** de avisos | `home_screen.dart` → `_buildMarquesina` → agrega `velocidad: 30,` dentro de `Marquesina(` (sin ese parámetro usa 45, definido en `diseno.dart`) |
| Cada cuánto cambia el **carrusel principal** | `carrusel_productos.dart` → `HeroCarrusel` → `Duration(seconds: 5)` |
| **Número de WhatsApp del flyer** | `flyer_sucursal.dart` → `_whatsappCasaMatriz = '56973877811'` (sin `+` ni espacios) **y** el texto del botón `'Cotiza aquí: +56 9 7387 7811'` |
| **Número de WhatsApp general** de la página | Panel → **Configuración** → Contacto |
| **Desactivar el flyer** | `home_screen.dart` → busca `mostrarFlyerSucursal(context)` y borra (o comenta con `//`) esas 3 líneas del `addPostFrameCallback` |
| **Quitar una sección** | `home_screen.dart` → `build()` → borra su línea de la lista (§1) |
| Cambiar el **"30+" marcas** u otras cifras | Panel → Configuración → Estadísticas de la portada |

---

## 6. Probar el cambio y publicarlo

### Opción A: ver cambios al instante mientras editas (recomendado para practicar)
Abre **dos** terminales de PowerShell en la carpeta del proyecto:

```powershell
cd backend; dart run bin/server.dart
```

```powershell
cd app; flutter run -d chrome --dart-define=API_BASE=http://localhost:8080
```

Se abre Chrome con la página. Cada vez que guardes un archivo, aprieta **`r`** en la segunda terminal (*hot reload*) y el cambio aparece en 1–2 segundos. Con **`R`** reinicia la página completa, y con **`q`** se cierra.

### Opción B: ver la versión compilada (como queda en internet)
```powershell
powershell -ExecutionPolicy Bypass -File iniciar.ps1 -Compilar
```
Abre `http://localhost:8080`. Tarda 1–3 minutos en compilar.

### Antes de publicar, revisa que no haya errores
```powershell
cd app; flutter analyze
```
Debe decir `No issues found!`. Si marca un error, te dice el archivo y la línea (casi siempre falta una coma, un paréntesis o una comilla).

### Publicar en internet
```powershell
powershell -ExecutionPolicy Bypass -File .\desplegar.ps1 -Web
```
Compila y sube la página a `https://maykel-repuestos2.cl`. Necesita la llave SSH en `C:\Users\<tu usuario>\.ssh\maykel_vps` (ver [DESPLIEGUE.md](DESPLIEGUE.md)).
Después, recarga la página con **Ctrl+F5**.

### Guardar el cambio en GitHub
```powershell
git add -A; git commit -m "Cambia el logo principal"; git push
```

### Si algo salió mal
| Problema | Solución |
|---|---|
| Quiero deshacer lo que cambié en un archivo (antes del commit) | `git checkout -- app/lib/screens/home_screen.dart` |
| Ya hice commit y quiero volver atrás | `git revert HEAD` (crea un commit que deshace el último) y vuelve a desplegar |
| La imagen nueva no aparece | ¿El nombre del archivo es exactamente igual (mayúsculas, `.jpg` vs `.png`)? ¿Recompilaste? ¿Hiciste Ctrl+F5? |
| La página queda en blanco | Abre la consola con **F12** → pestaña *Console* y mira el error en rojo; corre `flutter analyze` |
| El servidor no arranca: `address already in use` / `errno = 10048` / puerto 8080 | Ya hay otro servidor abierto (otra terminal, o uno que quedó colgado). Ciérralo con **Ctrl+C** en su terminal, o en PowerShell: `Stop-Process -Id (Get-NetTCPConnection -LocalPort 8080 -State Listen).OwningProcess -Force` |
| Uso **Git Bash** y no funciona `iniciar.ps1` | Los `.ps1` son de PowerShell. En Git Bash escribe `powershell -ExecutionPolicy Bypass -File iniciar.ps1`, o cambia la terminal de VS Code a PowerShell (flecha ⌄ junto al **+** de la terminal) |

---

## 7. Mini glosario para leer el código Flutter

| Verás… | Significa |
|---|---|
| `Text('Hola', style: TextStyle(...))` | Un texto y su estilo (tamaño, color, negrita) |
| `Container(color: ..., padding: ..., child: ...)` | Una caja: fondo, espacio interno y lo que lleva dentro |
| `Column(children: [...])` / `Row(children: [...])` | Pone cosas una debajo de otra / una al lado de otra |
| `SizedBox(height: 20)` | Un espacio vacío de 20 px |
| `EdgeInsets.all(16)` | Margen o relleno de 16 px por todos lados |
| `Image.asset('assets/images/...')` | Muestra una imagen del proyecto |
| `Icon(Icons.search)` | Un ícono (catálogo: https://fonts.google.com/icons) |
| `BorderRadius.circular(20)` | Esquinas redondeadas de 20 px |
| `onTap: ...` / `onPressed: ...` | Lo que pasa al tocar |
| `esAngosto ? A : B` | Si es celular usa A, si es computador usa B |
| `AppColors.red` | El rojo definido en `config.dart` |
| `// texto` | Un comentario: el programa lo ignora, es una nota para personas |
