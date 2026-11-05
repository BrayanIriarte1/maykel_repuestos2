# Guía: llevar el proyecto a otro computador y encenderlo (sin IA)

Todos los comandos son para **PowerShell** en Windows. Cada uno está probado en este proyecto.
Si algo falla, ve a la sección **"Si algo sale mal"** al final.

---

## 0. Qué hay que llevar (son 4 cosas)

| Cosa | Dónde está | Cómo viaja |
|---|---|---|
| **El código** | GitHub (`BrayanIriarte1/maykel_repuestos2`) | `git clone` |
| **El archivo `backend\.env`** (claves y contraseñas) | Solo en el PC antiguo. **No está en GitHub a propósito** | Pendrive o nube privada. **Nunca por correo ni a GitHub** |
| **La base de datos** (productos, usuarios, reservas, ventas) | PostgreSQL del PC antiguo | Archivo de respaldo `.dump` |
| **Las fotos subidas** | `backend\uploads\` | Archivo `.zip` |

---

## A. En el PC ANTIGUO (preparar el traslado)

**A1. Confirma que todo el código está en GitHub**
```powershell
cd C:\Users\chunc\Maykel_Repuestos-master
git status -sb
git push origin main
```
Debe decir `## main...origin/main` sin nada más. Si hay archivos modificados: `git add -A` → `git commit -m "mensaje"` → `git push origin main`.

**A2. Crea el respaldo de la base de datos y de las fotos**
```powershell
cd backend
powershell -ExecutionPolicy Bypass -File tools\respaldo.ps1
```
Genera en `backend\respaldos\`: `bd_FECHA.dump` (la base) y `fotos_FECHA.zip` (las fotos).

**A3. Copia a un pendrive (o nube privada) estos 3 archivos:**
1. `backend\.env`
2. `backend\respaldos\bd_FECHA.dump` (el más reciente)
3. `backend\respaldos\fotos_FECHA.zip` (el más reciente)

> ⚠️ `.env` contiene contraseñas y tokens. Guárdalo como un secreto.

---

## B. En el PC NUEVO

### Paso 1 — Instala los programas (una sola vez)

| Programa | Descarga | Nota |
|---|---|---|
| **Git** | https://git-scm.com/download/win | Todo por defecto |
| **PostgreSQL 18** (o más nuevo) | https://www.postgresql.org/download/windows/ | Durante la instalación te pide **la contraseña del usuario `postgres`**: **anótala**. Puerto `5432`. Debe ser la **misma versión o más nueva** que la del PC antiguo (18), si no el respaldo no se restaura |
| **Flutter** (trae Dart) | https://docs.flutter.dev/get-started/install/windows/web | Descomprime en `C:\src\flutter` (sin espacios ni tildes en la ruta) |
| **Google Chrome** | https://www.google.com/chrome/ | Para ver la página |
| **VS Code** (opcional) | https://code.visualstudio.com | Con las extensiones *Dart* y *Flutter* |

### Paso 2 — Agrega Flutter, Dart y PostgreSQL al PATH

Agrega estas dos rutas a las **variables de entorno del usuario** (Windows → buscar "variables de entorno" → *Path* → Editar → Nuevo):
```
C:\src\flutter\bin
C:\Program Files\PostgreSQL\18\bin
```
**Cierra y vuelve a abrir PowerShell**, y permite ejecutar los scripts del proyecto (una sola vez; responde `S` si pregunta):
```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
Comprueba que todo se reconoce:
```powershell
flutter --version
dart --version
psql --version
git --version
flutter doctor
```
`flutter doctor` puede quejarse de Android o Visual Studio: **no importa**, solo necesitamos Chrome y "Flutter" en verde.

### Paso 3 — Descarga el código
```powershell
cd C:\
mkdir proyectos
cd proyectos
git clone https://github.com/BrayanIriarte1/maykel_repuestos2.git
cd maykel_repuestos2
dir
```
Debes ver las carpetas `app`, `backend`, `docs` y el archivo `iniciar.ps1`.

### Paso 4 — Crea la base de datos

```powershell
createdb -U postgres maykel_repuestos2
```
(pide la contraseña de `postgres`). Ahora elige **una** de estas opciones:

**Opción A (recomendada): restaurar el respaldo.** Trae todo: productos reales, usuarios, reservas, ventas, configuración.
```powershell
pg_restore -U postgres -d maykel_repuestos2 --no-owner "D:\ruta\del\pendrive\bd_FECHA.dump"
```

**Opción B: empezar desde cero** (solo 20 productos de ejemplo + 3 usuarios demo). Los productos reales se cargan después con el sync (Paso 7 y 8: con el servidor encendido, `dart run tools\sync_agent.dart --sistema` desde `backend`).
```powershell
psql -U postgres -d maykel_repuestos2 -f backend\database\schema.sql
```

Comprueba:
```powershell
psql -U postgres -d maykel_repuestos2 -c "select count(*) from productos"
```
Con la opción A debería dar unos **6.318**; con la B, **20**.

### Paso 5 — Copia el archivo de configuración `.env`

Copia `.env` del pendrive a `backend\.env` y **edita la línea `DB_PASS=`** con la contraseña de `postgres` **de este PC nuevo**:
```powershell
copy "D:\ruta\del\pendrive\.env" backend\.env
notepad backend\.env
```
Líneas importantes del `.env`:

| Variable | Qué es |
|---|---|
| `DB_PASS` | Contraseña de PostgreSQL de **este** PC |
| `JWT_SECRET`, `SYNC_API_TOKEN` | Secretos internos (no los compartas) |
| `SISTEMA_EMAIL` / `SISTEMA_PASS` | Acceso al sistema del cliente (para sincronizar el inventario) |
| `SMTP_*`, `WHATSAPP_*` | Correo y WhatsApp (opcionales) |

¿No tienes el `.env` viejo? Parte de la plantilla y genera secretos nuevos:
```powershell
copy backend\.env.example backend\.env
notepad backend\.env
cd backend
dart pub get
dart run tools\rotar_secretos.dart
cd ..
```
(luego completa `DB_PASS` y las claves de `SISTEMA_*`).

### Paso 6 — Restaura las fotos
```powershell
Expand-Archive -Path "D:\ruta\del\pendrive\fotos_FECHA.zip" -DestinationPath backend -Force
```
Deben quedar en `backend\uploads\productos\`. (Si todavía no hay fotos subidas, sáltate este paso.)

### Paso 7 — Enciende la página 🚀
```powershell
cd C:\proyectos\maykel_repuestos2
powershell -ExecutionPolicy Bypass -File iniciar.ps1
```
La primera vez descarga paquetes y compila la web (1 a 3 minutos). Luego verás:
```
Servidor en http://localhost:8080  (Ctrl+C para detenerlo)
```
Abre **http://localhost:8080** en Chrome. El panel se abre con el botón **Admin** (arriba a la derecha).
Documentación de la API: **http://localhost:8080/api/docs**.

### Paso 8 — Activa la sincronización cada 30 minutos (opcional)

Solo en el PC que va a quedar encendido y funcionando como servidor:
```powershell
cd backend
powershell -ExecutionPolicy Bypass -File tools\instalar_sync.ps1
```
Para probarla a mano una vez: `dart run tools\sync_agent.dart --sistema`
El resultado queda en `backend\logs\sync.log`.

> **Importante:** deja la sincronización activa en **un solo** PC. En el PC antiguo desactívala con:
> `powershell -ExecutionPolicy Bypass -File tools\instalar_sync.ps1 -Quitar`

### Paso 9 — Verifica que todo funciona (lista de chequeo)

- [ ] `http://localhost:8080` muestra la portada con productos.
- [ ] El botón **Admin** acepta tu usuario y entra al panel.
- [ ] Refrescas la página (F5) estando en el panel y **no te saca**.
- [ ] Admin → Stock muestra productos y la hora de la última sincronización.
- [ ] (Con el servidor encendido) en otra ventana, dentro de `backend`: `dart test` → debe decir **All tests passed!**

---

## C. Comandos del día a día

| Qué quiero hacer | Comando (desde la carpeta indicada) |
|---|---|
| **Encender la página** | `.\iniciar.ps1` *(carpeta del proyecto; si da error de scripts: `powershell -ExecutionPolicy Bypass -File iniciar.ps1`)* |
| **Apagarla** | `Ctrl + C` en esa ventana |
| Cambié código de **Flutter** (pantallas) → recompilar | `.\iniciar.ps1 -Compilar` |
| Cambié código del **backend** (`server.dart`…) | `Ctrl + C` y volver a `.\iniciar.ps1` |
| Ver la página con recarga rápida mientras programo | `cd app` → `flutter run -d chrome --dart-define=API_BASE=http://localhost:8080` *(con el backend encendido)* |
| Revisar errores de código Flutter | `cd app` → `flutter analyze` |
| Revisar errores de código backend | `cd backend` → `dart analyze` |
| Correr las pruebas automáticas | `cd backend` → `dart test` *(con el servidor encendido)* |
| Sincronizar el inventario ahora | `cd backend` → `dart run tools\sync_agent.dart --sistema` |
| Hacer un respaldo | `cd backend` → `powershell -ExecutionPolicy Bypass -File tools\respaldo.ps1` |
| Generar el CSV de datos a corregir para el cliente | `cd backend` → `dart run tools\reporte_calidad.dart` |
| Importar fotos por SKU (carpeta con `SKU.jpg`) | `cd backend` → `dart run tools\importar_imagenes.dart C:\fotos` *(agrega `--simular` para solo probar)* |
| Prueba de carga (50 usuarios) | `cd backend` → `dart run tools\prueba_carga.dart 50 20` |
| Cambiar secretos (JWT y token de sync) | `cd backend` → `dart run tools\rotar_secretos.dart` y reiniciar |
| Ver la base de datos | `psql -U postgres -d maykel_repuestos2` (o pgAdmin 4) |
| Bajar cambios de GitHub | `git pull` |
| Subir mis cambios | `git add -A` → `git commit -m "qué cambié"` → `git push origin main` |

Consultas útiles en `psql` (termina cada una con `;`, sal con `\q`):
```sql
select count(*) from productos;
select folio, cliente_nombre, estado from reservas order by id desc limit 5;
select usuario, activo from usuarios;
select max(fecha_inicio) from logs_sincronizacion where estado = 'EXITOSO';
```

---

## D. Seguridad: haz esto en el PC nuevo

1. **Cambia la contraseña de `postgres`** si alguna vez usaste la antigua. Esa contraseña estuvo escrita en `backend\.env.example` en GitHub (repositorio público) hasta hoy. Ya se quitó del archivo, pero **queda en el historial** de Git. Cámbiala así y actualiza `DB_PASS` en `backend\.env`:
   ```powershell
   psql -U postgres -c "ALTER USER postgres PASSWORD 'nueva_clave_larga_y_unica';"
   ```
   (No expongas el puerto 5432 a internet.)
2. **Cambia las claves demo** de `admin`, `daniel` y `vendedor` desde Admin → Usuarios. Las claves demo están escritas en `backend\README.md`, que es público.
3. Pídele al cliente que **cambie su contraseña** del sistema (se compartió por chat) y actualiza `SISTEMA_PASS` en el `.env`.
4. Ejecuta `dart run tools\rotar_secretos.dart` si el `.env` pasó por un medio poco seguro.
5. **Nunca** subas `backend\.env`, respaldos ni la carpeta `uploads` a GitHub (ya están en `.gitignore`).

---

## E. Si algo sale mal

| Síntoma | Causa probable | Solución |
|---|---|---|
| `dart / flutter / psql no se reconoce` | No está en el PATH, o la terminal es anterior al cambio | Revisa el Paso 2 y **abre una PowerShell nueva** |
| `la ejecución de scripts está deshabilitada` | Política de PowerShell | Usa siempre `powershell -ExecutionPolicy Bypass -File ...` como en esta guía |
| `password authentication failed` | `DB_PASS` del `.env` no coincide con la clave de `postgres` | Corrige `backend\.env` (o cambia la clave con el `ALTER USER` de arriba) |
| `connection refused` / `No se pudo conectar` al puerto 5432 | PostgreSQL no está encendido | `Get-Service *postgres*` y `Start-Service postgresql-x64-18` (PowerShell como administrador) |
| `Address already in use` (puerto 8080) | Ya hay un servidor encendido | `Get-NetTCPConnection -LocalPort 8080 -State Listen` → anota el `OwningProcess` → `Stop-Process -Id ESE_NUMERO`. O cambia `PORT=` en `.env` |
| `pg_restore: error: ... version` | PostgreSQL del PC nuevo es **más antiguo** que el del respaldo | Instala PostgreSQL 18 o superior |
| `database "maykel_repuestos2" already exists` | Ya la habías creado | Salta `createdb` y restaura con `pg_restore -U postgres -d maykel_repuestos2 --clean --if-exists --no-owner archivo.dump` |
| La página abre pero sin productos | Base vacía o sin restaurar | Revisa el Paso 4 y la consulta `select count(*) from productos` |
| La página muestra una versión vieja | Caché del navegador | `Ctrl + F5` |
| Pantalla en blanco / "Cargando…" eterno | La web no está compilada o hubo error | `.\iniciar.ps1 -Compilar` y mira la consola |
| `Faltan SISTEMA_EMAIL y SISTEMA_PASS` | Falta completar el `.env` | Paso 5 |
| El sync dice `401` o `rechazó` | El token del `.env` cambió | Reinicia el servidor y vuelve a probar el sync (usan el mismo `.env`) |
| Error raro al compilar Flutter | Caché de compilación | `cd app` → `flutter clean` → `flutter pub get` → `.\iniciar.ps1 -Compilar` |
| `Login 401` tras restaurar | Usuarios o claves distintos | Con el respaldo valen los usuarios del PC antiguo; con `schema.sql`, los demo del README |
| No llegan correos / WhatsApp | Faltan `SMTP_PASS`, `WHATSAPP_TOKEN`, `WHATSAPP_PHONE_ID` | Son opcionales; la reserva igual funciona |

---

## F. Subir esto a Internet (despliegue)

Esta guía sirve para otro computador. Para dejar la página en un servidor con dominio y HTTPS, sigue `docs\DESPLIEGUE.md` (hay que sumar `CORS_ORIGIN` y `TRUST_PROXY=1` en el `.env`).
