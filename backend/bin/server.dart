// ============================================================================
// SERVER.DART UNIFICADO - MAYKEL REPUESTOS 2 (CALAMA)
// Arquitectura de 3 Capas: Flutter Web -> API REST Dart (Shelf) -> PostgreSQL
// Cumple IEEE 830 (RF01-RF07, RNF01-RNF06) y 100% compatible con Frontend app/
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

import '../lib/db.dart';
import '../lib/notificador.dart';
import '../lib/seguridad.dart';
import '../lib/vehiculos.dart';

final db = DatabaseService();

final String _dirBackend = p.dirname(p.dirname(Platform.script.toFilePath()));
late final String rutaBuildWeb =
    p.join(p.dirname(_dirBackend), 'app', 'build', 'web');

const List<String> permisosDisponibles = [
  'dashboard',
  'catalogo',
  'reservas',
  'stock',
  'usuarios',
  'configuracion',
];

// ---------- Helpers de respuesta JSON ----------

Response _jsonResponse(Object? body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Response _errorResponse(String mensaje, {int status = 400}) =>
    _jsonResponse({'error': mensaje}, status: status);

Future<Map<String, dynamic>?> _leerJsonBody(Request request) async {
  // allowMalformed: un cliente que envía una codificación distinta a UTF-8 no debe provocar un 500.
  final texto = utf8.decode(await request.read().expand((c) => c).toList(), allowMalformed: true);
  if (texto.isEmpty) return {};
  try {
    return jsonDecode(texto) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

num _numDe(dynamic v, [num porDefecto = 0]) {
  if (v == null) return porDefecto;
  if (v is num) return v;
  return num.tryParse(v.toString()) ?? porDefecto;
}

/// Política mínima de contraseñas para usuarios del panel.
String? _validarClaveNueva(String clave) {
  if (clave.length < 8) return 'La contraseña debe tener al menos 8 caracteres.';
  if (clave.length > 72) return 'La contraseña no puede superar los 72 caracteres.';
  if (!RegExp(r'[A-Za-z]').hasMatch(clave) || !RegExp(r'\d').hasMatch(clave)) {
    return 'La contraseña debe combinar letras y números.';
  }
  return null;
}

Future<bool> _rolExiste(int id) async {
  final r = await db.conn.execute(
    Sql.named('SELECT 1 FROM roles WHERE id = @id'),
    parameters: {'id': id},
  );
  return r.isNotEmpty;
}

/// Comprueba los primeros bytes (firma) para no confiar solo en el Content-Type declarado.
bool _firmaImagenValida(List<int> b, String ext) {
  bool empieza(List<int> f) => b.length >= f.length && List.generate(f.length, (i) => b[i] == f[i]).every((x) => x);
  switch (ext) {
    case 'jpg':
      return empieza([0xFF, 0xD8, 0xFF]);
    case 'png':
      return empieza([0x89, 0x50, 0x4E, 0x47]);
    case 'webp':
      return b.length > 12 && empieza([0x52, 0x49, 0x46, 0x46]) && String.fromCharCodes(b.sublist(8, 12)) == 'WEBP';
  }
  return false;
}

/// Escapa los comodines de LIKE para que "%" o "_" en una búsqueda se traten como texto.
String _escaparLike(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

// ---------- Contraseñas (bcrypt, ver lib/seguridad.dart) ----------

/// Hash a guardar en `usuarios.password_hash` (bcrypt, costo 10).
String hashPassword(String password) => hashBcrypt(password);

/// Compara una contraseña con el hash guardado (bcrypt, sha256 antiguo o texto plano).
bool verificarPassword(String password, String guardado) =>
    verificarClave(password, guardado);

late final Jwt jwt;
final limitadorLogin = LimitadorIntentos();

Future<void> _auditar(String? usuario, String ruta, String metodo,
    String resultado, String? ip) async {
  try {
    await db.conn.execute(
      Sql.named('''
        INSERT INTO logs_auditoria (usuario_email, ruta_accedida, metodo_http, resultado, ip_origen)
        VALUES (@u, @r, @m, @res, @ip)
      '''),
      parameters: {
        'u': usuario,
        'r': ruta.length > 150 ? ruta.substring(0, 150) : ruta,
        'm': metodo,
        'res': resultado,
        'ip': ip,
      },
    );
  } catch (e) {
    print('⚠️ No se pudo registrar auditoría: $e');
  }
}

String? _ipDe(Request req) {
  // Tras Nginx todas las conexiones llegan desde 127.0.0.1: con TRUST_PROXY=1
  // se usa la IP real que informa el proxy.
  if (db.env['TRUST_PROXY'] == '1') {
    final xff = req.headers['x-forwarded-for'];
    if (xff != null && xff.isNotEmpty) return xff.split(',').first.trim();
  }
  final info = req.context['shelf.io.connection_info'];
  if (info is HttpConnectionInfo) return info.remoteAddress.address;
  return null;
}

/// Permiso que exige cada grupo de rutas /api/admin/<grupo>.
/// Las rutas que no aparecen aquí solo requieren haber iniciado sesión.
const Map<String, String> permisoPorRuta = {
  'usuarios': 'usuarios',
  'roles': 'usuarios',
  'contenido': 'configuracion',
  'repuestos': 'stock',
  'ventas': 'stock',
  'reservas': 'reservas',
  'dashboard': 'dashboard',
  'analytics': 'dashboard',
};

/// Origen permitido por CORS. En producción definir CORS_ORIGIN=https://tudominio.cl
String get _origenCors => db.env['CORS_ORIGIN'] ?? '*';

final String _dirUploads = p.join(_dirBackend, 'uploads', 'productos');
const int _maxBytesImagen = 3 * 1024 * 1024;
const Map<String, String> _extensionesImagen = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

// ---------- Contenido por defecto del Sitio Web (Editable en PostgreSQL) ----------

Map<String, dynamic> contenidoPorDefecto() {
  return {
    'textos': {
      'nombreNegocio': 'MAYKEL REPUESTOS 2',
      'heroTitulo': 'REPUESTOS QUE\nMUEVEN CALAMA',
      'heroSubtitulo':
          'Especialistas en repuestos para marcas chinas e insumos mineros en Calama. '
              'Consulta compatibilidad técnica y reserva en línea.',
      'heroBotonCatalogo': 'Ver catálogo',
      'heroBotonContacto': 'Contáctanos',
      'heroEstadisticaProductosEtiqueta': 'Productos en catálogo',
      'heroEstadisticaMarcasValor': '8+',
      'heroEstadisticaMarcasEtiqueta': 'Marcas chinas y faena',
      'heroEstadisticaCategoriasValor': '5',
      'heroEstadisticaCategoriasEtiqueta': 'Líneas técnicas',
      'historiaKicker': 'NUESTRA HISTORIA',
      'serviciosKicker': 'QUÉ OFRECEMOS',
      'serviciosTitulo': 'Servicios',
      'catalogoKicker': 'CATÁLOGO TÉCNICO',
      'catalogoTitulo': 'Busca tu repuesto compatible',
      'catalogoBusquedaHint': 'Buscar por nombre, código OEM o SKU...',
      'contactoKicker': 'CONTACTO',
      'contactoTitulo': 'Sucursal Maykel Repuestos 2',
      'footerDerechos':
          'Maykel Repuestos Limitada. Todos los derechos reservados.',
    },
    'historia': {
      'titulo': 'Desde 2015 moviendo a Calama',
      'texto':
          'Maykel Repuestos Limitada nació en Calama e inició actividades el 22 de octubre de 2015. '
              'Desde entonces se ha especializado en repuestos para vehículos de marcas chinas '
              '(Great Wall, Haval, Maxus, Chery, JAC, Jetour, Changan y MG, entre otras), '
              'atendiendo a conductores particulares y talleres mecánicos de la ciudad. '
              'Con los años sumó una línea de insumos para vehículos de faena minera, como pértigas, '
              'balizas y elementos de señalización.\n\n'
              'Nuestra misión es proveer repuestos, accesorios e insumos de calidad que garanticen la '
              'continuidad operativa de nuestros clientes, con asesoría técnica experta y un inventario '
              'confiable. Nuestra visión es ser el proveedor de referencia en la Región de Antofagasta, '
              'digitalizando nuestros procesos para responder con rapidez a cada cliente.',
      'fichas': [
        {'etiqueta': 'Ubicación', 'valor': 'Vargas #2275, Calama'},
        {
          'etiqueta': 'Giro comercial',
          'valor':
              'Venta al por mayor y menor de partes, piezas y accesorios para vehículos'
        },
        {'etiqueta': 'Especialidad', 'valor': 'Marcas chinas e insumos mineros'},
        {'etiqueta': 'En Calama desde', 'valor': '2015'},
        {'etiqueta': 'Atención', 'valor': 'Presencial, WhatsApp y reserva en línea'},
      ],
    },
    'servicios': [
      {
        'titulo': 'Catálogo de Marcas Chinas',
        'descripcion':
            'Especialistas en Great Wall, Chery, Maxus, JAC, Changan, MG y Haval.'
      },
      {
        'titulo': 'Insumos para Faena Minera',
        'descripcion':
            'Pértigas, balizas estroboscópicas y elementos de señalización.'
      },
      {
        'titulo': 'Reserva Formal en PDF',
        'descripcion':
            'Genera tu comprobante con folio único y coordina con nuestros ejecutivos.'
      },
      {
        'titulo': 'Atención a Talleres',
        'descripcion':
            'Búsqueda técnica rápida por Marca, Modelo, Año y Motorización.'
      },
    ],
    'contacto': {
      'whatsapp': '56969170551',
      'email': 'contacto@maykelrepuestos.cl',
      'direccion': 'Vargas #2275, Calama, Región de Antofagasta',
      'mapsUrl':
          'https://www.google.com/maps/place/Maykel+Repuestos/@-22.4608953,-68.9286172,21z',
      'horario': 'Lunes a viernes, 9:00 – 18:30\nSábado, 9:30 – 14:00',
    },
    'avisoLegal': {
      'actualizado': 'octubre de 2026',
      'secciones': [
        {
          'titulo': '1. Identificación',
          'texto':
              'Plataforma operada por Maykel Repuestos Limitada (RUT 76.555.098-K), '
                  'Sucursal Maykel Repuestos 2, ubicada en Vargas #2275, Calama.',
          'items': [],
        },
        {
          'titulo': '2. Modalidad de Reserva y Precios (Art. 30 Ley N° 19.496)',
          'texto':
              'Este portal opera como canal digital de consulta de disponibilidad y reserva asistida (ROPO). '
                  'El precio final y la disponibilidad física son confirmados directamente por un ejecutivo de ventas '
                  'antes de formalizar cualquier acto de compra o pago en sucursal.',
          'items': [],
        },
        {
          'titulo': '3. Protección de Datos Personales (Ley N° 19.628 y Ley N° 21.719)',
          'texto':
              'Los datos de contacto recopilados en el formulario de reserva (nombre, teléfono y correo) '
                  'se utilizan exclusivamente para emitir el comprobante PDF y contactar al cliente respecto a su solicitud.',
          'items': [],
        },
      ],
    },
  };
}

// ---------- Autenticación y Control de Acceso Basado en Roles (RBAC - RNF03) ----------

/// Valida usuario/clave contra ADMIN_USERS o la tabla usuarios y devuelve la sesión.
Future<Map<String, dynamic>?> _validarCredenciales(
    String usuarioInput, String passwordInput) async {
  try {
    // Usuarios de emergencia opcionales: ADMIN_USERS=usuario:clave,usuario2:clave2
    final envAdmins = db.env['ADMIN_USERS'] ?? '';
    for (final par in envAdmins.split(',')) {
      final partes = par.split(':');
      if (partes.length >= 2 &&
          partes[0].trim() == usuarioInput &&
          tokensIguales(partes.sublist(1).join(':').trim(), passwordInput)) {
        return {
          'usuario': usuarioInput,
          'permisos': permisosDisponibles,
          'esSuperAdmin': true,
          'rolNombre': 'Superadministrador',
        };
      }
    }

    final rows = await db.conn.execute(
      Sql.named('''
        SELECT u.usuario, u.nombre, u.rol, u.activo, r.nombre AS rol_nombre, r.permisos, u.password_hash
        FROM usuarios u
        LEFT JOIN roles r ON u.rol_id = r.id
        WHERE (u.usuario = @usr OR u.email = @usr) AND u.activo = TRUE
        LIMIT 1
      '''),
      parameters: {'usr': usuarioInput},
    );

    if (rows.isNotEmpty &&
        verificarPassword(passwordInput, rows.first[6] as String)) {
      final r = rows.first;
      final guardado = r[6] as String;
      // Migración transparente a bcrypt al iniciar sesión.
      if (!esBcrypt(guardado)) {
        await db.conn.execute(
          Sql.named('UPDATE usuarios SET password_hash = @h WHERE usuario = @u'),
          parameters: {'h': hashPassword(passwordInput), 'u': r[0]},
        );
      }
      final rolSistema = r[2] as String;
      final rawPermisos = r[5];
      List<String> permisos = permisosDisponibles;
      if (rawPermisos is List) {
        permisos = rawPermisos.map((e) => e.toString()).toList();
      } else if (rawPermisos is String) {
        permisos = List<String>.from(jsonDecode(rawPermisos) as List);
      }

      return {
        'usuario': r[0],
        'nombre': r[1],
        'permisos': permisos,
        'esSuperAdmin': rolSistema == 'SUPERADMIN',
        'rolNombre': r[4] ?? rolSistema,
      };
    }
  } catch (e) {
    print('⚠️ Aviso en autenticación: $e');
  }
  return null;
}

/// Lee la sesión desde `Authorization: Bearer <jwt>`.
Map<String, dynamic>? _sesionDesdeToken(Request request) {
  final authHeader = request.headers['authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) return null;
  final datos = jwt.verificar(authHeader.substring(7).trim());
  if (datos == null) return null;
  return {
    'usuario': datos['usuario'],
    'nombre': datos['nombre'],
    'permisos': datos['permisos'] ?? <String>[],
    'esSuperAdmin': datos['esSuperAdmin'] == true,
    'rolNombre': datos['rolNombre'],
  };
}

/// Vuelve a leer rol y estado del usuario en la base (cache de 15 s) para que
/// desactivar un usuario o cambiarle el rol tenga efecto de inmediato y no
/// recién cuando venza su token. Devuelve null si ya no puede entrar.
final Map<String, ({DateTime hasta, Map<String, dynamic>? sesion})> _cacheSesiones = {};

Future<Map<String, dynamic>?> _refrescarSesion(Map<String, dynamic> sesion) async {
  final usuario = sesion['usuario']?.toString() ?? '';
  final emergencia = (db.env['ADMIN_USERS'] ?? '')
      .split(',')
      .any((par) => par.split(':').first.trim() == usuario);
  if (emergencia) return sesion;

  final ahora = DateTime.now();
  final cacheado = _cacheSesiones[usuario];
  if (cacheado != null && cacheado.hasta.isAfter(ahora)) return cacheado.sesion;

  final rows = await db.conn.execute(
    Sql.named('''
      SELECT u.nombre, u.rol, r.nombre, r.permisos
      FROM usuarios u LEFT JOIN roles r ON u.rol_id = r.id
      WHERE u.usuario = @usr AND u.activo = TRUE
    '''),
    parameters: {'usr': usuario},
  );
  Map<String, dynamic>? vigente;
  if (rows.isNotEmpty) {
    final r = rows.first;
    final rolSistema = r[1] as String;
    final raw = r[3];
    final permisos = raw is List
        ? raw.map((e) => e.toString()).toList()
        : raw is String
            ? List<String>.from(jsonDecode(raw) as List)
            : List<String>.from(permisosDisponibles);
    vigente = {
      'usuario': usuario,
      'nombre': r[0],
      'permisos': permisos,
      'esSuperAdmin': rolSistema == 'SUPERADMIN',
      'rolNombre': r[2] ?? rolSistema,
    };
  }
  _cacheSesiones[usuario] = (hasta: ahora.add(const Duration(seconds: 15)), sesion: vigente);
  return vigente;
}

/// Convierte cualquier excepción no controlada en un JSON 500 sin filtrar detalles internos.
Middleware _erroresComoJson() {
  return (Handler inner) {
    return (Request request) async {
      try {
        return await inner(request);
      } on _ErrorNegocio catch (e) {
        return _errorResponse(e.mensaje, status: e.status);
      } catch (e, st) {
        print('❌ ${request.method} /${request.url.path}: $e\n$st');
        return _errorResponse('Error interno del servidor.', status: 500);
      }
    };
  };
}

/// Cabeceras de seguridad y de caché: la API nunca se cachea (así el stock que
/// ve el usuario es siempre el real) y el sitio se revalida en cada visita.
Middleware _cabecerasSeguras() {
  return (Handler inner) {
    return (Request request) async {
      final resp = await inner(request);
      final ruta = request.url.path;
      final h = <String, String>{
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'SAMEORIGIN',
        'Referrer-Policy': 'strict-origin-when-cross-origin',
      };
      if (ruta.startsWith('api/')) {
        h['Cache-Control'] = 'no-store';
      } else if (ruta.startsWith('media/')) {
        h['Cache-Control'] = 'public, max-age=31536000, immutable';
      } else {
        h['Cache-Control'] = 'no-cache';
      }
      return resp.change(headers: h);
    };
  };
}

/// Borra registros antiguos para que las tablas de logs no crezcan sin límite.
Future<void> _limpiarRegistrosAntiguos() async {
  try {
    await db.conn.execute(
        "DELETE FROM logs_sincronizacion WHERE fecha_inicio < NOW() - INTERVAL '60 days'");
    await db.conn.execute(
        "DELETE FROM logs_auditoria WHERE fecha < NOW() - INTERVAL '180 days'");
    await db.conn.execute(
        "DELETE FROM metricas_demanda WHERE fecha_evento < NOW() - INTERVAL '365 days'");
  } catch (e) {
    print('⚠️ No se pudo limpiar registros antiguos: $e');
  }
}

Middleware _authSoloAdmin() {
  return (Handler innerHandler) {
    return (Request request) async {
      // CRÍTICO PARA CHROME (CORS PREFLIGHT):
      // Si el navegador envía una consulta OPTIONS para verificar permisos CORS,
      // debemos dejarla pasar sin exigir contraseña.
      if (request.method.toUpperCase() == 'OPTIONS') {
        return Response.ok('', headers: {
          'Access-Control-Allow-Origin': _origenCors,
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization, Accept',
        });
      }

      if (request.url.path.startsWith('api/admin/')) {
        final firmada = _sesionDesdeToken(request);
        final sesion = firmada == null ? null : await _refrescarSesion(firmada);
        final grupo = request.url.pathSegments.length > 2
            ? request.url.pathSegments[2]
            : '';
        if (sesion != null) {
          // Ver el catálogo interno (GET) basta con el permiso "catalogo" o "stock".
          final lecturaCatalogo = grupo == 'repuestos' && request.method == 'GET';
          final requerido = lecturaCatalogo ? null : permisoPorRuta[grupo];
          final permisos = (sesion['permisos'] as List).cast<String>();
          final sinAcceso = lecturaCatalogo
              ? !(permisos.contains('catalogo') || permisos.contains('stock'))
              : (requerido != null && !permisos.contains(requerido));
          if (sesion['esSuperAdmin'] != true && sinAcceso) {
            await _auditar(sesion['usuario']?.toString(), '/${request.url.path}',
                request.method, 'DENEGADO_403', _ipDe(request));
            return Response(
              403,
              body: jsonEncode({'error': 'Tu rol no tiene permiso para esta sección.'}),
              headers: {
                'content-type': 'application/json; charset=utf-8',
                'Access-Control-Allow-Origin': _origenCors,
              },
            );
          }
          final actualizado = request.change(context: {'adminSesion': sesion});
          return innerHandler(actualizado);
        }

        await _auditar(null, '/${request.url.path}', request.method,
            'NO_AUTENTICADO_401', _ipDe(request));
        return Response(
          401,
          body: jsonEncode({
            'error': 'Sesión no válida o expirada. Inicia sesión nuevamente.'
          }),
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'Access-Control-Allow-Origin': _origenCors,
          },
        );
      }
      return innerHandler(request);
    };
  };
}

void main(List<String> args) async {
  await db.init();
  await db.migrar(_dirBackend);
  await _limpiarRegistrosAntiguos();
  Timer.periodic(const Duration(hours: 24), (_) => _limpiarRegistrosAntiguos());

  final secreto = db.env['JWT_SECRET'];
  if (secreto == null || secreto.length < 16) {
    print('⚠️ JWT_SECRET no definido (o menor a 16 caracteres): se usa uno '
        'aleatorio y las sesiones se cerrarán al reiniciar el servidor.');
  }
  jwt = Jwt(
    (secreto != null && secreto.length >= 16) ? secreto : Jwt.secretoAleatorio(),
    duracion: Duration(hours: int.tryParse(db.env['JWT_HORAS'] ?? '') ?? 8),
  );
  if ((db.env['SYNC_API_TOKEN'] ?? '').isEmpty) {
    print('⚠️ SYNC_API_TOKEN no definido: la sincronización de inventario '
        'queda deshabilitada.');
  }

  final router = Router();

  router.post('/api/auth/login', (Request req) async {
    final body = await _leerJsonBody(req);
    final usuario = (body?['usuario'] ?? '').toString().trim();
    final password = (body?['password'] ?? '').toString();
    if (usuario.isEmpty || password.isEmpty) {
      return _errorResponse('Debes ingresar usuario y contraseña.');
    }
    final ip = _ipDe(req) ?? 'desconocida';
    final clave = '${usuario.toLowerCase()}|$ip';
    if (limitadorLogin.bloqueado(clave)) {
      await _auditar(usuario, '/api/auth/login', 'POST', 'BLOQUEADO_429', ip);
      return _jsonResponse({
        'error': 'Demasiados intentos fallidos. Espera 15 minutos e inténtalo de nuevo.'
      }, status: 429);
    }
    final sesion = await _validarCredenciales(usuario, password);
    if (sesion == null) {
      limitadorLogin.registrarFallo(clave);
      await _auditar(usuario, '/api/auth/login', 'POST', 'LOGIN_FALLIDO', ip);
      return _jsonResponse(
          {'error': 'Usuario o contraseña incorrectos.'}, status: 401);
    }
    limitadorLogin.reiniciar(clave);
    await _auditar(usuario, '/api/auth/login', 'POST', 'LOGIN_OK', ip);
    return _jsonResponse({
      'token': jwt.emitir(sesion),
      'tipo': 'Bearer',
      'expira_en_segundos': jwt.duracion.inSeconds,
      ...sesion,
    });
  });

  // Renueva la sesión mientras el token siga vigente (el panel lo usa al
  // recargar la página para no obligar a iniciar sesión otra vez).
  router.post('/api/auth/refresh', (Request req) async {
    final firmada = _sesionDesdeToken(req);
    final sesion = firmada == null ? null : await _refrescarSesion(firmada);
    if (sesion == null) {
      return _jsonResponse({'error': 'Sesión no válida o expirada.'}, status: 401);
    }
    return _jsonResponse({
      'token': jwt.emitir(sesion),
      'tipo': 'Bearer',
      'expira_en_segundos': jwt.duracion.inSeconds,
      ...sesion,
    });
  });

  // ==========================================================================
  // 1. HEALTHCHECK, ESTADO Y CONTENIDO DEL SITIO (RNF04 + Frontend Compañera)
  // ==========================================================================
  router.get('/api/health', (Request req) async {
    final syncResult = await db.conn.execute(
      '''
        SELECT fecha_inicio, estado, total_procesados 
        FROM logs_sincronizacion 
        WHERE estado = 'EXITOSO' 
        ORDER BY fecha_inicio DESC LIMIT 1
      ''',
    );

    DateTime? ultimaSync;
    bool stockDesactualizado = false;

    if (syncResult.isNotEmpty) {
      ultimaSync = syncResult.first[0] as DateTime?;
      if (ultimaSync != null) {
        stockDesactualizado =
            DateTime.now().difference(ultimaSync).inHours >= 2;
      }
    }

    return _jsonResponse({
      'status': 'ok',
      'sucursal': 'Maykel Repuestos 2 - Calama',
      'ultima_sincronizacion': ultimaSync?.toIso8601String(),
      'alerta_stock_desactualizado': stockDesactualizado,
    });
  });

  router.get('/api/estado', (Request req) async {
    final r = await db.conn.execute('''
      SELECT COUNT(*),
             COUNT(*) FILTER (WHERE stock_actual > 0),
             COUNT(*) FILTER (WHERE stock_actual <= 0),
             (SELECT to_char(MAX(fecha_inicio), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') FROM logs_sincronizacion WHERE estado = 'EXITOSO'),
             (SELECT EXTRACT(EPOCH FROM (LOCALTIMESTAMP - MAX(fecha_inicio)))::int FROM logs_sincronizacion WHERE estado = 'EXITOSO')
      FROM productos WHERE estado_catalogo = 'PUBLICADO'
    ''');
    final fila = r.first;
    return _jsonResponse({
      'esDatosDeEjemplo': false,
      'totalProductos': _numDe(fila[0]).toInt(),
      'disponibles': _numDe(fila[1]).toInt(),
      'agotados': _numDe(fila[2]).toInt(),
      // Hora UTC (termina en Z) y segundos transcurridos, para mostrar
      // "actualizado hace X min" sin depender del reloj del navegador.
      'ultimaSincronizacion': fila[3],
      'haceSegundos': fila[4],
    });
  });

  router.get('/api/contenido', (Request req) async {
    final rows = await db.conn.execute(
      "SELECT contenido FROM configuracion_sitio WHERE clave = 'principal' LIMIT 1",
    );
    if (rows.isEmpty) {
      return _jsonResponse(contenidoPorDefecto());
    }
    final raw = rows.first[0];
    if (raw is String) return _jsonResponse(jsonDecode(raw));
    return _jsonResponse(raw);
  });

  router.put('/api/admin/contenido', (Request req) async {
    final body = await _leerJsonBody(req);
    if (body == null) return _errorResponse('JSON inválido');

    await db.conn.execute(
      Sql.named('''
        INSERT INTO configuracion_sitio (clave, contenido, actualizado_en)
        VALUES ('principal', @contenido::jsonb, CURRENT_TIMESTAMP)
        ON CONFLICT (clave) DO UPDATE 
        SET contenido = EXCLUDED.contenido, actualizado_en = CURRENT_TIMESTAMP
      '''),
      parameters: {'contenido': jsonEncode(body)},
    );
    return _jsonResponse(body);
  });

  // ==========================================================================
  // 2. ENDPOINTS DE TAXONOMÍA VEHICULAR Y CATEGORÍAS (HU-02 / RF02 + Frontend)
  // ==========================================================================
  // Nota: Si el frontend pide ?formato=objetos devuelve [{id, nombre}],
  // por defecto devuelve lista de Strings para no romper los Dropdowns actuales de app/
  router.get('/api/marcas', (Request req) async {
    final formato = req.url.queryParameters['formato'];
    final rows = await db.conn.execute(
      'SELECT id, nombre, origen FROM marcas WHERE activo = TRUE ORDER BY nombre ASC',
    );
    if (formato == 'objetos') {
      return _jsonResponse(rows
          .map((r) => {'id': r[0], 'nombre': r[1], 'origen': r[2]})
          .toList());
    }
    return _jsonResponse(rows.map((r) => r[1].toString()).toList());
  });

  router.get('/api/categorias', (Request req) async {
    final formato = req.url.queryParameters['formato'];
    final rows = await db.conn.execute(
      'SELECT id, nombre, descripcion, es_insumo_minero FROM categorias ORDER BY nombre ASC',
    );
    if (formato == 'objetos') {
      return _jsonResponse(rows
          .map((r) => {
                'id': r[0],
                'nombre': r[1],
                'descripcion': r[2],
                'es_insumo_minero': r[3],
              })
          .toList());
    }
    return _jsonResponse(rows.map((r) => r[1].toString()).toList());
  });

  router.get('/api/modelos', (Request req) async {
    final marcaId = int.tryParse(req.url.queryParameters['marca_id'] ?? '');
    final marcaNombre = req.url.queryParameters['marca'];

    if (marcaId != null) {
      final rows = await db.conn.execute(
        Sql.named(
            'SELECT id, nombre FROM modelos WHERE marca_id = @marcaId ORDER BY nombre ASC'),
        parameters: {'marcaId': marcaId},
      );
      return _jsonResponse(
          rows.map((r) => {'id': r[0], 'nombre': r[1]}).toList());
    } else if (marcaNombre != null && marcaNombre.isNotEmpty) {
      final rows = await db.conn.execute(
        Sql.named('''
          SELECT mo.id, mo.nombre 
          FROM modelos mo
          JOIN marcas m ON mo.marca_id = m.id
          WHERE m.nombre ILIKE @nombreMarca
          ORDER BY mo.nombre ASC
        '''),
        parameters: {'nombreMarca': marcaNombre},
      );
      return _jsonResponse(
          rows.map((r) => {'id': r[0], 'nombre': r[1]}).toList());
    }
    return _errorResponse('Parámetro marca_id o marca es requerido');
  });

  router.get('/api/versiones', (Request req) async {
    final modeloId = int.tryParse(req.url.queryParameters['modelo_id'] ?? '');
    if (modeloId == null) {
      return _errorResponse('Parámetro modelo_id es requerido');
    }
    final rows = await db.conn.execute(
      Sql.named('''
        SELECT id, anio, motor, cilindrada 
        FROM versiones_vehiculo 
        WHERE modelo_id = @modeloId 
        ORDER BY anio DESC, motor ASC
      '''),
      parameters: {'modeloId': modeloId},
    );
    return _jsonResponse(rows
        .map((r) => {
              'id': r[0],
              'anio': r[1],
              'motor': r[2],
              'cilindrada': r[3],
            })
        .toList());
  });

  // ==========================================================================
  // 3. CATÁLOGO UNIFICADO (/api/productos y /api/repuestos) CON PRECIOS OCULTOS
  // ==========================================================================
  Future<Response> manejarConsultaCatalogo(Request req) async {
    final qp = req.url.queryParameters;
    final queryRaw = (qp['q'] ?? qp['buscar'])?.trim();
    final queryText = (queryRaw != null && queryRaw.length > 80) ? queryRaw.substring(0, 80) : queryRaw;
    final categoriaParam = qp['categoria_id'] ?? qp['categoria'];
    final marcaParam = qp['marca_id'] ?? qp['marca'];
    final modeloParam = qp['modelo_id'] ?? qp['modelo'];
    final anio = int.tryParse(qp['anio'] ?? '');
    final versionId = int.tryParse(qp['version_id'] ?? '');
    final disponible = qp['disponible'];

    final conditions = <String>["p.estado_catalogo = 'PUBLICADO'"];
    final params = <String, dynamic>{};

    if (queryText != null && queryText.isNotEmpty) {
      conditions.add(
          '(p.nombre ILIKE @q OR p.codigo_interno ILIKE @q OR p.codigo_oem ILIKE @q OR p.descripcion_tecnica ILIKE @q)');
      params['q'] = '%${_escaparLike(queryText)}%';
    }
    if (categoriaParam != null && categoriaParam.isNotEmpty) {
      final catId = int.tryParse(categoriaParam);
      if (catId != null) {
        conditions.add('p.categoria_id = @catId');
        params['catId'] = catId;
      } else {
        conditions.add('c.nombre ILIKE @catNombre');
        params['catNombre'] = categoriaParam;
      }
    }
    if (versionId != null) {
      conditions.add('vv.id = @versionId');
      params['versionId'] = versionId;
    } else {
      if (marcaParam != null && marcaParam.isNotEmpty) {
        final mId = int.tryParse(marcaParam);
        if (mId != null) {
          conditions.add('m.id = @mId');
          params['mId'] = mId;
        } else {
          conditions.add(
              '(m.nombre ILIKE @mNombre OR p.marca_referencia ILIKE @mNombre)');
          params['mNombre'] = marcaParam;
        }
      }
      if (modeloParam != null && modeloParam.isNotEmpty) {
        final moId = int.tryParse(modeloParam);
        if (moId != null) {
          conditions.add('mo.id = @moId');
          params['moId'] = moId;
        } else {
          conditions.add(
              '(mo.nombre ILIKE @moNombre OR p.modelo_referencia ILIKE @moNombre)');
          params['moNombre'] = '%${_escaparLike(modeloParam)}%';
        }
      }
      if (anio != null) {
        conditions.add('vv.anio = @anio');
        params['anio'] = anio;
      }
    }
    if (disponible == '1') {
      conditions.add('p.stock_actual > 0');
    }

    final whereClause = conditions.join(' AND ');

    // Los JOIN de compatibilidad (lentos con miles de productos) solo si el filtro los usa.
    final usaCompat = RegExp(r'\b(vv|mo|m)\.').hasMatch(whereClause);
    final desde = '''
      FROM productos p
      LEFT JOIN categorias c ON p.categoria_id = c.id
      ${usaCompat ? '''
      LEFT JOIN producto_compatibilidad pc ON p.id = pc.producto_id
      LEFT JOIN versiones_vehiculo vv ON pc.version_vehiculo_id = vv.id
      LEFT JOIN modelos mo ON vv.modelo_id = mo.id
      LEFT JOIN marcas m ON mo.marca_id = m.id''' : ''}
    ''';

    // Paginación opcional: con ?limite=N responde {total, items}; sin él, la lista completa.
    final limite = int.tryParse(qp['limite'] ?? '');
    final pagina = (int.tryParse(qp['pagina'] ?? '') ?? 1).clamp(1, 100000);
    var total = 0;
    var paginacion = 'LIMIT 1000';
    if (limite != null && limite > 0) {
      final cant = await db.conn.execute(
        Sql.named('SELECT COUNT(DISTINCT p.id) $desde WHERE $whereClause'),
        parameters: params,
      );
      total = cant.first[0] as int;
      paginacion = 'LIMIT ${limite.clamp(1, 200)} OFFSET ${(pagina - 1) * limite.clamp(1, 200)}';
    }

    final sql = '''
      SELECT DISTINCT
        p.id,
        p.codigo_interno,
        p.codigo_oem,
        p.nombre,
        p.descripcion_tecnica,
        p.categoria_id,
        COALESCE(c.nombre, 'General') AS categoria_nombre,
        p.marca_referencia,
        p.modelo_referencia,
        p.imagen_url,
        p.stock_actual,
        p.es_agotado,
        p.es_insumo_faena,
        p.ultima_sincronizacion
      $desde
      WHERE $whereClause
      ORDER BY p.es_agotado ASC, p.nombre ASC, p.id ASC
      $paginacion
    ''';

    final rows = await db.conn.execute(Sql.named(sql), parameters: params);

    // COLECTOR ANALÍTICO ASÍNCRONO (HU-06 Escenario 1: Búsqueda sin resultados)
    if (rows.isEmpty &&
        (queryText != null || marcaParam != null || modeloParam != null)) {
      Future.microtask(() async {
        try {
          await db.conn.execute(
            Sql.named('''
              INSERT INTO metricas_demanda 
              (tipo_evento, termino_buscado, marca_consultada, modelo_consultado, anio_consultado)
              VALUES ('BUSQUEDA_SIN_RESULTADO', @termino, @marca, @modelo, @anio)
            '''),
            parameters: {
              'termino': queryText ?? 'Filtro sin coincidencia',
              'marca': marcaParam,
              'modelo': modeloParam,
              'anio': anio,
            },
          );
        } catch (_) {}
      });
    }

    // Por RF01 y HU-01: Precio oculto en catálogo público (se envía 0 referencial para compatibilidad de parseo en models.dart)
    final productos = rows.map((r) {
      final stock = r[10] as int;
      final agotado = r[11] as bool;
      return {
        'id': r[0],
        'sku': r[1],
        'codigo': r[1],
        'codigo_interno': r[1],
        'codigo_oem': r[2],
        'nombre': r[3],
        'descripcion': r[4] ?? '',
        'categoria_id': r[5],
        'categoria': r[6],
        'marca': r[7] ?? 'General',
        'modelo': r[8] ?? 'Compatible',
        'precio': 0, // Política de Precios Ocultos (HU-01)
        'precio_oculto': true,
        'imagen_url': r[9],
        'stock': stock,
        'disponible': !agotado,
        'estado_stock': agotado ? 'Agotado' : 'Disponible',
        'es_insumo_faena': r[12],
        'es_ejemplo': false,
        'ultima_sincronizacion': (r[13] as DateTime?)?.toIso8601String(),
      };
    }).toList();

    if (limite != null && limite > 0) {
      return _jsonResponse({'total': total, 'pagina': pagina, 'items': productos});
    }
    return _jsonResponse(productos);
  }

  router.get('/api/productos', manejarConsultaCatalogo);
  router.get('/api/repuestos', manejarConsultaCatalogo);

  // Filtro jerárquico Marca -> Modelo con conteos, calculado sobre lo publicado.
  router.get('/api/catalogo/filtros', (Request req) async {
    final marca = req.url.queryParameters['marca']?.trim() ?? '';
    final marcas = await db.conn.execute('''
      SELECT marca_referencia, COUNT(*) FROM productos
      WHERE estado_catalogo = 'PUBLICADO' AND COALESCE(marca_referencia, 'General') <> 'General'
      GROUP BY 1 ORDER BY 2 DESC, 1 ASC
    ''');
    final modelos = marca.isEmpty
        ? []
        : await db.conn.execute(
            Sql.named('''
              SELECT modelo_referencia, COUNT(*) FROM productos
              WHERE estado_catalogo = 'PUBLICADO' AND marca_referencia ILIKE @m
                AND COALESCE(modelo_referencia, 'General') NOT IN ('General', 'Compatible')
              GROUP BY 1 ORDER BY 2 DESC, 1 ASC
            '''),
            parameters: {'m': marca},
          );
    final categorias = await db.conn.execute('''
      SELECT c.nombre, COUNT(*) FROM productos p JOIN categorias c ON c.id = p.categoria_id
      WHERE p.estado_catalogo = 'PUBLICADO' AND p.stock_actual > 0 AND length(c.nombre) <= 30
      GROUP BY c.nombre ORDER BY 2 DESC, 1 ASC LIMIT 40
    ''');
    return _jsonResponse({
      'marcas': marcas.map((r) => {'nombre': r[0], 'total': r[1]}).toList(),
      'modelos': modelos.map((r) => {'nombre': r[0], 'total': r[1]}).toList(),
      'categorias': categorias.map((r) => {'nombre': r[0], 'total': r[1]}).toList(),
    });
  });

  // ==========================================================================
  // 4. REGISTRO DE INTERACCIÓN CON PRODUCTO AGOTADO (HU-06)
  // ==========================================================================
  router.post('/api/metricas/agotado', (Request req) async {
    final payload = await _leerJsonBody(req);
    if (payload == null) return _errorResponse('JSON inválido');
    final productoId = _numDe(payload['producto_id']).toInt();
    final termino =
        payload['nombre_producto']?.toString() ?? 'Producto agotado';

    await db.conn.execute(
      Sql.named('''
        INSERT INTO metricas_demanda (tipo_evento, termino_buscado, producto_id)
        VALUES ('INTERACCION_AGOTADO', @termino, @productoId)
      '''),
      parameters: {
        'termino': termino,
        'productoId': productoId > 0 ? productoId : null
      },
    );

    return _jsonResponse({'registrado': true}, status: 201);
  });

  // ==========================================================================
  // 5. EMISIÓN Y GESTIÓN DE RESERVAS (Soporta formato simple y múltiple - HU-03)
  // ==========================================================================
  router.post('/api/reservas', (Request req) async {
    final body = await _leerJsonBody(req);
    if (body == null) return _errorResponse('JSON inválido');

    final nombre =
        (body['cliente_nombre'] ?? body['nombre'])?.toString().trim() ?? '';
    final telefono =
        (body['cliente_telefono'] ?? body['telefono'])?.toString().trim() ?? '';
    final email =
        (body['cliente_email'] ?? body['email'])?.toString().trim() ?? '';
    final nota = body['nota']?.toString().trim() ?? '';

    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    if (nombre.isEmpty || telefono.isEmpty || !emailRegex.hasMatch(email)) {
      return _errorResponse(
          'Por favor ingrese un canal de contacto válido para enviar su comprobante');
    }

    // Soporta lista 'items' o un único 'repuestoId' enviado desde reserva_dialog.dart
    List<Map<String, dynamic>> items = [];
    if (body['items'] is List && (body['items'] as List).isNotEmpty) {
      items = (body['items'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } else if (body['repuestoId'] != null) {
      items = [
        {
          'producto_id': _numDe(body['repuestoId']).toInt(),
          'cantidad': _numDe(body['cantidad'], 1).toInt(),
          'vehiculo_referencia': nota,
        }
      ];
    }

    if (items.isEmpty) {
      return _errorResponse('Debe incluir al menos un repuesto en la reserva');
    }
    if (items.any((i) => i['producto_id'] == null && i['repuestoId'] == null)) {
      return _errorResponse('Formato de repuestos inválido');
    }
    if (items.length > 20 || nombre.length > 120 || telefono.length > 30 || nota.length > 500) {
      return _errorResponse('Los datos de la reserva exceden el tamaño permitido');
    }

    // Restricción Cap. 5.1.2 del Informe:
    // "Una reserva web no descuenta inventario físico de forma automática. Queda Pendiente de confirmación".
    final lineasNotificacion = <String>[];
    final result = await db.conn.runTx((tx) async {
      final resCabecera = await tx.execute(
        Sql.named('''
          INSERT INTO reservas 
          (cliente_nombre, cliente_telefono, cliente_email, cliente_rut_o_taller, nota, estado, notificado_whatsapp, notificado_email)
          VALUES (@nombre, @telefono, @email, @taller, @nota, 'pendiente', FALSE, FALSE)
          RETURNING id, folio, creado_en
        '''),
        parameters: {
          'nombre': nombre,
          'telefono': telefono,
          'email': email,
          'taller': body['cliente_rut_o_taller']?.toString(),
          'nota': nota,
        },
      );

      final reservaId = resCabecera.first[0] as int;
      final folio = resCabecera.first[1] as String;
      final fecha = resCabecera.first[2] as DateTime;

      String primerProductoNombre = 'Repuesto reservado';
      String primerSku = 'MR-000';
      int primeraCantidad = 1;
      int primerProdId = 1;

      for (final item in items) {
        final prodId =
            _numDe(item['producto_id'] ?? item['repuestoId']).toInt();
        final cant = _numDe(item['cantidad'], 1).toInt();
        if (cant < 1 || cant > 999) {
          throw const _ErrorNegocio('La cantidad debe ser entre 1 y 999');
        }

        final prodRow = await tx.execute(
          Sql.named(
              "SELECT codigo_interno, nombre, stock_actual FROM productos WHERE id = @id AND estado_catalogo = 'PUBLICADO'"),
          parameters: {'id': prodId},
        );
        if (prodRow.isEmpty) {
          throw const _ErrorNegocio('El producto seleccionado ya no está disponible');
        }
        final stockDisp = prodRow.first[2] as int;
        if (stockDisp <= 0) {
          throw _ErrorNegocio('"${prodRow.first[1]}" está agotado en este momento.');
        }
        if (cant > stockDisp) {
          throw _ErrorNegocio('Solo quedan $stockDisp unidades de "${prodRow.first[1]}".');
        }
        primerSku = prodRow.first[0].toString();
        primerProductoNombre = prodRow.first[1].toString();
        primeraCantidad = cant;
        primerProdId = prodId;
        lineasNotificacion.add('$primerProductoNombre ($primerSku) x$cant');

        await tx.execute(
          Sql.named('''
            INSERT INTO reserva_detalles (reserva_id, producto_id, cantidad, vehiculo_referencia)
            VALUES (@reservaId, @productoId, @cantidad, @vehiculo)
          '''),
          parameters: {
            'reservaId': reservaId,
            'productoId': prodId,
            'cantidad': cant,
            'vehiculo': item['vehiculo_referencia']?.toString() ?? nota,
          },
        );
      }

      return {
        'id': folio,
        'reserva_id_interno': reservaId,
        'folio': folio,
        'fecha': fecha.toIso8601String(),
        'repuestoId': primerProdId,
        'sku': primerSku,
        'producto': primerProductoNombre,
        'cantidad': primeraCantidad,
        'nombre': nombre,
        'telefono': telefono,
        'email': email,
        'nota': nota,
        'estado': 'pendiente',
      };
    });

    // Envío en segundo plano: no retrasa ni rompe la respuesta al cliente (RNF06).
    Notificador(db.env).notificarReserva(result, lineasNotificacion).then((n) {
      db.conn.execute(
        Sql.named(
            'UPDATE reservas SET notificado_whatsapp=@w, notificado_email=@e WHERE id=@id'),
        parameters: {
          'w': n.whatsapp,
          'e': n.email,
          'id': result['reserva_id_interno'],
        },
      );
    }).catchError((Object e) => print('⚠️ Notificación falló: $e'));

    return _jsonResponse(result, status: 201);
  });

  router.get('/api/admin/reservas', (Request req) async {
    // Una fila por reserva (antes una reserva con varios repuestos aparecía repetida).
    final rows = await db.conn.execute('''
      SELECT
        r.folio,
        r.creado_en,
        COALESCE(MIN(rd.producto_id), 0) AS repuesto_id,
        COALESCE(MIN(p.codigo_interno), 'S/C') AS sku,
        CASE WHEN COUNT(rd.id) > 1
             THEN MIN(p.nombre) || ' (+' || (COUNT(rd.id) - 1) || ' más)'
             ELSE COALESCE(MIN(p.nombre), 'Sin repuestos') END AS producto,
        COALESCE(SUM(rd.cantidad), 1) AS cantidad,
        r.cliente_nombre,
        r.cliente_telefono,
        r.cliente_email,
        COALESCE(r.nota, '') AS nota,
        LOWER(r.estado) AS estado,
        COALESCE(json_agg(json_build_object(
          'sku', p.codigo_interno, 'nombre', p.nombre, 'cantidad', rd.cantidad
        ) ORDER BY rd.id) FILTER (WHERE rd.id IS NOT NULL), '[]'::json) AS items
      FROM reservas r
      LEFT JOIN reserva_detalles rd ON r.id = rd.reserva_id
      LEFT JOIN productos p ON rd.producto_id = p.id
      GROUP BY r.id
      ORDER BY r.creado_en DESC
      LIMIT 1000
    ''');

    final lista = rows
        .map((r) => {
              'id': r[0].toString(),
              'folio': r[0].toString(),
              'fecha': (r[1] as DateTime).toIso8601String(),
              'repuestoId': r[2],
              'sku': r[3],
              'producto': r[4],
              'cantidad': r[5],
              'nombre': r[6],
              'telefono': r[7],
              'email': r[8],
              'nota': r[9],
              'estado': r[10],
              'items': r[11] is String ? jsonDecode(r[11] as String) : r[11],
            })
        .toList();

    return _jsonResponse(lista);
  });

  // Estados que retienen stock: confirmada (apartado) y entregada (vendido).
  // El descuento se hace una sola vez (reservas.stock_descontado) y se repone si
  // la reserva vuelve a pendiente o se rechaza.
  router.put('/api/admin/reservas/<id>', (Request req, String id) async {
    final body = await _leerJsonBody(req);
    final estado = body?['estado']?.toString().toLowerCase();
    const validos = ['pendiente', 'confirmada', 'entregada', 'rechazada'];
    if (estado == null || !validos.contains(estado)) {
      return _errorResponse('Estado inválido');
    }
    final retiene = estado == 'confirmada' || estado == 'entregada';

    final cambios = await db.conn.runTx((tx) async {
      final fila = await tx.execute(
        Sql.named('SELECT id, stock_descontado FROM reservas WHERE folio = @id OR id::text = @id FOR UPDATE'),
        parameters: {'id': id},
      );
      if (fila.isEmpty) throw const _ErrorNegocio('Reserva no encontrada', 404);
      final reservaId = fila.first[0] as int;
      final descontado = fila.first[1] as bool;
      final ajustes = <Map<String, Object?>>[];

      if (retiene != descontado) {
        final lineas = await tx.execute(
          Sql.named('''
            SELECT rd.producto_id, rd.cantidad, p.nombre, p.stock_actual
            FROM reserva_detalles rd JOIN productos p ON p.id = rd.producto_id
            WHERE rd.reserva_id = @rid ORDER BY rd.producto_id FOR UPDATE OF p
          '''),
          parameters: {'rid': reservaId},
        );
        for (final l in lineas) {
          final cant = l[1] as int;
          final stock = l[3] as int;
          if (retiene && stock < cant) {
            throw _ErrorNegocio(
                'Stock insuficiente de "${l[2]}": quedan $stock y la reserva pide $cant. '
                'Ajusta el stock o rechaza la reserva.',
                409);
          }
          final nuevo = retiene ? stock - cant : stock + cant;
          await tx.execute(
            Sql.named('UPDATE productos SET stock_actual = @s WHERE id = @pid'),
            parameters: {'s': nuevo, 'pid': l[0]},
          );
          ajustes.add({'producto': l[2], 'cantidad': retiene ? -cant : cant, 'stock': nuevo});
        }
      }

      await tx.execute(
        Sql.named('''
          UPDATE reservas
          SET estado = @estado, stock_descontado = @ret, actualizado_en = CURRENT_TIMESTAMP
          WHERE id = @rid
        '''),
        parameters: {'estado': estado, 'ret': retiene, 'rid': reservaId},
      );

      // Entregada = venta concretada: alimenta Analítica (ventas, monto, categorías, gráfico).
      // Si la reserva deja de estar entregada, esa venta se anula. Es idempotente.
      await tx.execute(
        Sql.named('DELETE FROM ventas WHERE reserva_id = @rid'),
        parameters: {'rid': reservaId},
      );
      if (estado == 'entregada') {
        final usuario = (req.context['adminSesion'] as Map<String, dynamic>?)?['usuario']?.toString();
        await tx.execute(
          Sql.named('''
            INSERT INTO ventas (producto_id, sku, producto_nombre, precio_unitario, cantidad, total,
                                cliente, metodo_pago, nota, usuario_registro, reserva_id)
            SELECT p.id, p.codigo_interno, p.nombre, COALESCE(p.precio_referencia, 0), rd.cantidad,
                   COALESCE(p.precio_referencia, 0) * rd.cantidad, r.cliente_nombre, 'Reserva web',
                   'Reserva ' || r.folio, @usuario, r.id
            FROM reserva_detalles rd
            JOIN productos p ON p.id = rd.producto_id
            JOIN reservas r ON r.id = rd.reserva_id
            WHERE rd.reserva_id = @rid
          '''),
          parameters: {'rid': reservaId, 'usuario': usuario},
        );
      }
      return ajustes;
    });

    return _jsonResponse({'id': id, 'estado': estado, 'ajustesStock': cambios});
  });

  // ==========================================================================
  // 6. BACKOFFICE: GESTIÓN DEL CATÁLOGO TÉCNICO EN POSTGRESQL (HU-07 / RF07)
  // ==========================================================================
  // Guardado masivo de precio/stock: solo se envían las filas modificadas y
  // todo se aplica en una única transacción (o se guarda todo, o nada).
  router.put('/api/admin/repuestos', (Request req) async {
    final body = await _leerJsonBody(req);
    final cambios = body?['cambios'];
    if (cambios is! List) return _errorResponse('Formato inválido');
    if (cambios.length > 500) {
      return _errorResponse('Máximo 500 cambios por solicitud');
    }

    await db.conn.runTx((tx) async {
      for (final cambioRaw in cambios.whereType<Map>()) {
        final cambio = Map<String, dynamic>.from(cambioRaw);
        final id = _numDe(cambio['id']).toInt();
        if (id <= 0) continue;
        if (cambio['precio'] != null) {
          final precio = _numDe(cambio['precio']).toInt();
          await tx.execute(
            Sql.named('UPDATE productos SET precio_referencia = @precio WHERE id = @id'),
            parameters: {'precio': precio < 0 ? 0 : precio, 'id': id},
          );
        }
        if (cambio['stock'] != null) {
          final stock = _numDe(cambio['stock']).toInt();
          await tx.execute(
            Sql.named('UPDATE productos SET stock_actual = @stock WHERE id = @id'),
            parameters: {'stock': stock < 0 ? 0 : stock, 'id': id},
          );
        }
      }
    });
    return _jsonResponse({'ok': true, 'actualizados': cambios.length});
  });

  // Edición completa de un producto (nombre, categoría, marca, modelo,
  // precio, stock y estado de publicación).
  router.put('/api/admin/repuestos/<id>', (Request req, String id) async {
    final idNum = int.tryParse(id);
    final body = await _leerJsonBody(req);
    if (idNum == null || body == null) return _errorResponse('Datos inválidos');

    final sets = <String>[];
    final params = <String, dynamic>{'id': idNum};

    final nombre = body['nombre']?.toString().trim();
    if (nombre != null) {
      if (nombre.isEmpty || nombre.length > 180) {
        return _errorResponse('El nombre debe tener entre 1 y 180 caracteres');
      }
      sets.add('nombre = @nombre');
      params['nombre'] = nombre;
    }
    for (final (clave, columna) in [('marca', 'marca_referencia'), ('modelo', 'modelo_referencia')]) {
      final v = body[clave]?.toString().trim();
      if (v != null) {
        if (v.length > 80) return _errorResponse('El campo $clave es demasiado largo');
        sets.add('$columna = @$clave');
        params[clave] = v.isEmpty ? 'General' : v;
      }
    }
    if (body['precio'] != null) {
      final precio = _numDe(body['precio']).toInt();
      if (precio < 0) return _errorResponse('El precio no puede ser negativo');
      sets.add('precio_referencia = @precio');
      params['precio'] = precio;
    }
    if (body['stock'] != null) {
      final stock = _numDe(body['stock']).toInt();
      if (stock < 0) return _errorResponse('El stock no puede ser negativo');
      sets.add('stock_actual = @stock');
      params['stock'] = stock;
    }
    final estado = body['estado_catalogo']?.toString().toUpperCase();
    if (estado != null) {
      if (!['PUBLICADO', 'OCULTO', 'PENDIENTE'].contains(estado)) {
        return _errorResponse('Estado de catálogo inválido');
      }
      sets.add('estado_catalogo = @estado');
      params['estado'] = estado;
    }
    final categoria = body['categoria']?.toString().trim();
    if (categoria != null && categoria.isNotEmpty) {
      final fila = await db.conn.execute(
        Sql.named('SELECT id FROM categorias WHERE nombre ILIKE @n LIMIT 1'),
        parameters: {'n': categoria},
      );
      final catId = fila.isNotEmpty
          ? fila.first[0] as int
          : (await db.conn.execute(
              Sql.named('INSERT INTO categorias (nombre) VALUES (@n) RETURNING id'),
              parameters: {'n': categoria},
            ))
              .first[0] as int;
      sets.add('categoria_id = @cat');
      params['cat'] = catId;
    }
    if (sets.isEmpty) return _jsonResponse({'ok': true});

    final res = await db.conn.execute(
      Sql.named('UPDATE productos SET ${sets.join(', ')} WHERE id = @id RETURNING id'),
      parameters: params,
    );
    if (res.isEmpty) return _errorResponse('Producto no encontrado', status: 404);
    return _jsonResponse({'ok': true});
  });

  router.post('/api/admin/repuestos', (Request req) async {
    final body = await _leerJsonBody(req);
    if (body == null) return _errorResponse('JSON inválido');

    final nombre = body['nombre']?.toString().trim() ?? '';
    if (nombre.isEmpty) {
      return _errorResponse('El nombre del producto es obligatorio');
    }

    String texto(String clave, String porDefecto) {
      final v = body[clave]?.toString().trim() ?? '';
      return v.isEmpty ? porDefecto : v;
    }

    final categoriaNombre = texto('categoria', 'General');
    final marcaNombre = texto('marca', 'General');
    final modeloNombre = texto('modelo', 'Compatible');
    final stock = _numDe(body['stock'], 0).toInt();
    final precio = _numDe(body['precio'], 0).toInt();
    final sku = texto('sku',
        'MR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');

    // Asegurar que exista la categoría en PostgreSQL
    int? categoriaId;
    final catRow = await db.conn.execute(
      Sql.named('SELECT id FROM categorias WHERE nombre ILIKE @nom LIMIT 1'),
      parameters: {'nom': categoriaNombre},
    );
    if (catRow.isNotEmpty) {
      categoriaId = catRow.first[0] as int;
    } else {
      final newCat = await db.conn.execute(
        Sql.named(
            'INSERT INTO categorias (nombre) VALUES (@nom) RETURNING id'),
        parameters: {'nom': categoriaNombre},
      );
      categoriaId = newCat.first[0] as int;
    }

    // Asegurar que exista la marca en PostgreSQL
    if (marcaNombre.isNotEmpty && marcaNombre != 'General') {
      await db.conn.execute(
        Sql.named(
            'INSERT INTO marcas (nombre) VALUES (@nom) ON CONFLICT (nombre) DO NOTHING'),
        parameters: {'nom': marcaNombre},
      );
    }

    final duplicado = await db.conn.execute(
      Sql.named('SELECT 1 FROM productos WHERE codigo_interno = @sku'),
      parameters: {'sku': sku},
    );
    if (duplicado.isNotEmpty) {
      return _errorResponse('Ya existe un producto con el SKU $sku', status: 409);
    }

    final inserted = await db.conn.execute(
      Sql.named('''
        INSERT INTO productos
        (codigo_interno, nombre, categoria_id, marca_referencia, modelo_referencia, stock_actual, precio_referencia, estado_catalogo)
        VALUES (@sku, @nombre, @catId, @marca, @modelo, @stock, @precio, 'PUBLICADO')
        RETURNING id
      '''),
      parameters: {
        'sku': sku,
        'nombre': nombre,
        'catId': categoriaId,
        'marca': marcaNombre,
        'modelo': modeloNombre,
        'stock': stock < 0 ? 0 : stock,
        'precio': precio < 0 ? 0 : precio,
      },
    );

    return _jsonResponse({
      'id': inserted.first[0],
      'sku': sku,
      'nombre': nombre,
      'categoria': categoriaNombre,
      'marca': marcaNombre,
      'modelo': modeloNombre,
      'precio': precio,
      'stock': stock,
      'es_ejemplo': false,
    }, status: 201);
  });

  // Listado interno para el panel: incluye precio de referencia (nunca se
  // expone en el catálogo público) y productos ocultos o pendientes.
  // Paginado en el servidor: ?q=&categoria=&estado=&stock=(agotado|bajo|disponible)&pagina=&limite=
  router.get('/api/admin/repuestos', (Request req) async {
    final qp = req.url.queryParameters;
    final condiciones = <String>[];
    final params = <String, dynamic>{};

    final q = (qp['q'] ?? '').trim();
    if (q.isNotEmpty) {
      condiciones.add('(p.nombre ILIKE @q OR p.codigo_interno ILIKE @q OR c.nombre ILIKE @q)');
      params['q'] = '%${_escaparLike(q.length > 80 ? q.substring(0, 80) : q)}%';
    }
    final categoria = (qp['categoria'] ?? '').trim();
    if (categoria.isNotEmpty) {
      condiciones.add('c.nombre = @cat');
      params['cat'] = categoria;
    }
    final estado = (qp['estado'] ?? '').toUpperCase();
    if (['PUBLICADO', 'OCULTO', 'PENDIENTE'].contains(estado)) {
      condiciones.add('p.estado_catalogo = @estado');
      params['estado'] = estado;
    }
    switch (qp['stock']) {
      case 'agotado':
        condiciones.add('p.stock_actual <= 0');
      case 'bajo':
        condiciones.add('p.stock_actual > 0 AND p.stock_actual <= 3');
      case 'disponible':
        condiciones.add('p.stock_actual > 3');
      case 'sinprecio':
        condiciones.add('COALESCE(p.precio_referencia, 0) <= 0');
      case 'sinfoto':
        condiciones.add("COALESCE(p.imagen_url, '') = ''");
    }
    final donde = condiciones.isEmpty ? '' : 'WHERE ${condiciones.join(' AND ')}';
    final limite = (int.tryParse(qp['limite'] ?? '') ?? 50).clamp(1, 200);
    final pagina = (int.tryParse(qp['pagina'] ?? '') ?? 1).clamp(1, 100000);

    final desde = 'FROM productos p LEFT JOIN categorias c ON p.categoria_id = c.id $donde';
    final total = (await db.conn.execute(
      Sql.named('SELECT COUNT(*) $desde'),
      parameters: params,
    ))
        .first[0] as int;
    final rows = await db.conn.execute(
      Sql.named('''
        SELECT p.id, p.codigo_interno, p.nombre, COALESCE(c.nombre, 'General'),
               p.marca_referencia, p.modelo_referencia, p.precio_referencia,
               p.stock_actual, p.estado_catalogo, p.imagen_url
        $desde
        ORDER BY p.nombre ASC, p.id ASC
        LIMIT $limite OFFSET ${(pagina - 1) * limite}
      '''),
      parameters: params,
    );
    return _jsonResponse({
      'total': total,
      'pagina': pagina,
      'limite': limite,
      'items': rows
          .map((r) => {
                'id': r[0],
                'sku': r[1],
                'nombre': r[2],
                'categoria': r[3],
                'marca': r[4] ?? 'General',
                'modelo': r[5] ?? 'Compatible',
                'precio': r[6] ?? 0,
                'stock': r[7],
                'estado_catalogo': r[8],
                'imagen_url': r[9],
                'es_ejemplo': false,
              })
          .toList(),
    });
  });

  // Sube la foto de un producto (cuerpo = bytes de la imagen; JPG, PNG o WebP, máx. 3 MB).
  router.post('/api/admin/repuestos/<id>/imagen', (Request req, String id) async {
    final idNum = int.tryParse(id);
    if (idNum == null) return _errorResponse('ID inválido');
    final tipo = (req.headers['content-type'] ?? '').split(';').first.trim().toLowerCase();
    final ext = _extensionesImagen[tipo];
    if (ext == null) return _errorResponse('Formato no permitido. Usa JPG, PNG o WebP.');

    final bytes = <int>[];
    await for (final trozo in req.read()) {
      bytes.addAll(trozo);
      if (bytes.length > _maxBytesImagen) {
        return _errorResponse('La imagen supera los 3 MB.', status: 413);
      }
    }
    if (bytes.isEmpty) return _errorResponse('Imagen vacía');
    if (!_firmaImagenValida(bytes, ext)) {
      return _errorResponse('El archivo no es una imagen $ext válida.');
    }

    final existe = await db.conn.execute(
      Sql.named('SELECT 1 FROM productos WHERE id = @id'),
      parameters: {'id': idNum},
    );
    if (existe.isEmpty) return _errorResponse('Producto no encontrado', status: 404);

    await Directory(_dirUploads).create(recursive: true);
    for (final e in _extensionesImagen.values) {
      final vieja = File(p.join(_dirUploads, '$idNum.$e'));
      if (await vieja.exists()) await vieja.delete();
    }
    await File(p.join(_dirUploads, '$idNum.$ext')).writeAsBytes(bytes);
    final url = '/media/productos/$idNum.$ext?v=${DateTime.now().millisecondsSinceEpoch}';
    await db.conn.execute(
      Sql.named('UPDATE productos SET imagen_url = @url WHERE id = @id'),
      parameters: {'url': url, 'id': idNum},
    );
    return _jsonResponse({'id': idNum, 'imagen_url': url}, status: 201);
  });

  router.delete('/api/admin/repuestos/<id>/imagen', (Request req, String id) async {
    final idNum = int.tryParse(id);
    if (idNum == null) return _errorResponse('ID inválido');
    for (final e in _extensionesImagen.values) {
      final f = File(p.join(_dirUploads, '$idNum.$e'));
      if (await f.exists()) await f.delete();
    }
    await db.conn.execute(
      Sql.named('UPDATE productos SET imagen_url = NULL WHERE id = @id'),
      parameters: {'id': idNum},
    );
    return _jsonResponse({'ok': true});
  });

  // Por defecto OCULTA el producto (reversible): el sync cada 30 min volvería a
  // crear un producto borrado. Con ?definitivo=1 se elimina de verdad, solo si
  // no tiene reservas asociadas.
  router.delete('/api/admin/repuestos/<id>', (Request req, String id) async {
    final idNum = int.tryParse(id);
    if (idNum == null) return _errorResponse('ID inválido');
    if (req.url.queryParameters['definitivo'] == '1') {
      final enUso = await db.conn.execute(
        Sql.named('SELECT 1 FROM reserva_detalles WHERE producto_id = @id LIMIT 1'),
        parameters: {'id': idNum},
      );
      if (enUso.isNotEmpty) {
        return _errorResponse(
            'El producto tiene reservas asociadas: no se puede eliminar, solo ocultar.',
            status: 409);
      }
      await db.conn.execute(
        Sql.named('DELETE FROM productos WHERE id = @id'),
        parameters: {'id': idNum},
      );
      return _jsonResponse({'ok': true, 'accion': 'eliminado'});
    }
    final res = await db.conn.execute(
      Sql.named("UPDATE productos SET estado_catalogo = 'OCULTO' WHERE id = @id RETURNING id"),
      parameters: {'id': idNum},
    );
    if (res.isEmpty) return _errorResponse('Producto no encontrado', status: 404);
    return _jsonResponse({'ok': true, 'accion': 'oculto'});
  });

  // ==========================================================================
  // 7. LOGIN, ROLES Y USUARIOS ADMINISTRATIVOS EN POSTGRESQL (RNF03)
  // ==========================================================================
  router.get('/api/admin/verificar', (Request req) {
    final sesion = req.context['adminSesion'] as Map<String, dynamic>?;
    return _jsonResponse({
      'ok': true,
      'usuario': sesion?['usuario'],
      'permisos': sesion?['permisos'],
      'esSuperAdmin': sesion?['esSuperAdmin'],
      'rolNombre': sesion?['rolNombre'],
    });
  });

  router.get('/api/admin/roles', (Request req) async {
    final rows = await db.conn
        .execute('SELECT id, nombre, permisos FROM roles ORDER BY id ASC');
    return _jsonResponse(rows.map((r) {
      final rawPermisos = r[2];
      final permisos = rawPermisos is String
          ? jsonDecode(rawPermisos)
          : (rawPermisos ?? []);
      return {'id': r[0], 'nombre': r[1], 'permisos': permisos};
    }).toList());
  });

  router.post('/api/admin/roles', (Request req) async {
    final body = await _leerJsonBody(req);
    final nombre = body?['nombre']?.toString().trim() ?? '';
    final permisos = body?['permisos'];
    if (nombre.isEmpty || nombre.length > 60 || permisos is! List) {
      return _errorResponse('Nombre y lista de permisos son obligatorios');
    }
    if (permisos.any((p) => !permisosDisponibles.contains(p))) {
      return _errorResponse('La lista contiene permisos que no existen');
    }
    final existe = await db.conn.execute(
      Sql.named('SELECT 1 FROM roles WHERE lower(nombre) = lower(@n)'),
      parameters: {'n': nombre},
    );
    if (existe.isNotEmpty) return _errorResponse('Ya existe un rol con ese nombre', status: 409);
    final res = await db.conn.execute(
      Sql.named(
          'INSERT INTO roles (nombre, permisos) VALUES (@nom, @perm::jsonb) RETURNING id'),
      parameters: {'nom': nombre, 'perm': jsonEncode(permisos)},
    );
    return _jsonResponse(
        {'id': res.first[0], 'nombre': nombre, 'permisos': permisos},
        status: 201);
  });

  router.put('/api/admin/roles/<id>', (Request req, String id) async {
    final idNum = int.tryParse(id);
    final body = await _leerJsonBody(req);
    final nombre = body?['nombre']?.toString().trim() ?? '';
    final permisos = body?['permisos'];
    if (idNum == null || nombre.isEmpty || nombre.length > 60 || permisos is! List) {
      return _errorResponse('Nombre y lista de permisos son obligatorios');
    }
    if (permisos.any((p) => !permisosDisponibles.contains(p))) {
      return _errorResponse('La lista contiene permisos que no existen');
    }
    if (idNum == 1) {
      return _errorResponse('El rol Superadministrador no se puede modificar');
    }
    final res = await db.conn.execute(
      Sql.named(
          'UPDATE roles SET nombre = @nom, permisos = @perm::jsonb WHERE id = @id RETURNING id'),
      parameters: {'id': idNum, 'nom': nombre, 'perm': jsonEncode(permisos)},
    );
    if (res.isEmpty) return _errorResponse('Rol no encontrado', status: 404);
    _cacheSesiones.clear();
    return _jsonResponse({'id': idNum, 'nombre': nombre, 'permisos': permisos});
  });

  router.delete('/api/admin/roles/<id>', (Request req, String id) async {
    final idNum = int.tryParse(id);
    if (idNum == null) return _errorResponse('ID inválido');
    if (idNum == 1) {
      return _errorResponse('El rol Superadministrador no se puede eliminar');
    }
    final enUso = await db.conn.execute(
      Sql.named('SELECT COUNT(*) FROM usuarios WHERE rol_id = @id'),
      parameters: {'id': idNum},
    );
    if (_numDe(enUso.first[0]) > 0) {
      return _errorResponse(
          'No se puede eliminar: hay usuarios con este rol. Cámbiales el rol primero.');
    }
    await db.conn.execute(
      Sql.named('DELETE FROM roles WHERE id = @id'),
      parameters: {'id': idNum},
    );
    return _jsonResponse({'ok': true});
  });

  router.get('/api/admin/usuarios', (Request req) async {
    final rows = await db.conn.execute(
        'SELECT id, usuario, nombre, rol_id, activo FROM usuarios ORDER BY id ASC');
    return _jsonResponse(rows
        .map((r) => {
              'id': r[0],
              'usuario': r[1],
              'nombre': r[2],
              'rolId': r[3] ?? 1,
              'activo': r[4],
            })
        .toList());
  });

  router.post('/api/admin/usuarios', (Request req) async {
    final body = await _leerJsonBody(req);
    final usuario = body?['usuario']?.toString().trim() ?? '';
    final password = body?['password']?.toString() ?? '';
    final nombre = body?['nombre']?.toString().trim() ?? usuario;
    final rolId = _numDe(body?['rolId'], 2).toInt();

    if (usuario.isEmpty || password.isEmpty) {
      return _errorResponse('Usuario y contraseña obligatorios');
    }
    if (!RegExp(r'^[A-Za-z0-9._-]{3,40}$').hasMatch(usuario)) {
      return _errorResponse('El usuario debe tener 3 a 40 caracteres (letras, números, punto, guion).');
    }
    final errorClave = _validarClaveNueva(password);
    if (errorClave != null) return _errorResponse(errorClave);
    if (!await _rolExiste(rolId)) return _errorResponse('El rol seleccionado no existe');

    final existe = await db.conn.execute(
      Sql.named('SELECT 1 FROM usuarios WHERE usuario = @usr'),
      parameters: {'usr': usuario},
    );
    if (existe.isNotEmpty) {
      return _errorResponse('Ya existe un usuario con ese nombre');
    }

    final res = await db.conn.execute(
      Sql.named('''
        INSERT INTO usuarios (usuario, nombre, email, password_hash, rol, rol_id, activo)
        VALUES (@usr, @nom, @email, @pwd, @rol, @rolId, TRUE)
        RETURNING id
      '''),
      parameters: {
        'usr': usuario,
        'nom': nombre,
        'email': '$usuario@maykelrepuestos.cl',
        'pwd': hashPassword(password),
        'rol': rolId == 1 ? 'SUPERADMIN' : 'VENDEDOR',
        'rolId': rolId,
      },
    );

    return _jsonResponse({
      'id': res.first[0],
      'usuario': usuario,
      'nombre': nombre,
      'rolId': rolId,
      'activo': true,
    }, status: 201);
  });

  router.put('/api/admin/usuarios/<id>', (Request req, String id) async {
    final idNum = int.tryParse(id);
    final body = await _leerJsonBody(req);
    if (idNum == null || body == null) return _errorResponse('Datos inválidos');

    final sesionActual = req.context['adminSesion'] as Map<String, dynamic>?;
    final fila = await db.conn.execute(
      Sql.named('SELECT usuario FROM usuarios WHERE id = @id'),
      parameters: {'id': idNum},
    );
    if (fila.isEmpty) return _errorResponse('Usuario no encontrado', status: 404);
    final esPropio = fila.first[0] == sesionActual?['usuario'];

    final sets = <String>[];
    final params = <String, dynamic>{'id': idNum};
    final nombre = body['nombre']?.toString().trim();
    if (nombre != null && nombre.isNotEmpty) {
      sets.add('nombre = @nombre');
      params['nombre'] = nombre;
    }
    if (body['rolId'] != null) {
      final rolId = _numDe(body['rolId']).toInt();
      if (!await _rolExiste(rolId)) return _errorResponse('El rol seleccionado no existe');
      if (esPropio && rolId != 1) {
        return _errorResponse('No puedes quitarte el rol de Superadministrador a ti mismo');
      }
      sets.add('rol_id = @rolId');
      sets.add('rol = @rol');
      params['rolId'] = rolId;
      params['rol'] = rolId == 1 ? 'SUPERADMIN' : 'VENDEDOR';
    }
    final password = body['password']?.toString() ?? '';
    if (password.isNotEmpty) {
      final errorClave = _validarClaveNueva(password);
      if (errorClave != null) return _errorResponse(errorClave);
      sets.add('password_hash = @pwd');
      params['pwd'] = hashPassword(password);
    }
    if (body['activo'] is bool) {
      if (esPropio && body['activo'] == false) {
        return _errorResponse('No puedes desactivar tu propio usuario');
      }
      sets.add('activo = @activo');
      params['activo'] = body['activo'];
    }
    if (sets.isEmpty) return _jsonResponse({'ok': true});

    final res = await db.conn.execute(
      Sql.named('UPDATE usuarios SET ${sets.join(', ')} WHERE id = @id RETURNING id'),
      parameters: params,
    );
    if (res.isEmpty) return _errorResponse('Usuario no encontrado', status: 404);
    _cacheSesiones.clear();
    return _jsonResponse({'ok': true});
  });

  router.delete('/api/admin/usuarios/<id>', (Request req, String id) async {
    final idNum = int.tryParse(id);
    if (idNum == null) return _errorResponse('ID inválido');
    final sesion = req.context['adminSesion'] as Map<String, dynamic>?;
    final fila = await db.conn.execute(
      Sql.named('SELECT usuario FROM usuarios WHERE id = @id'),
      parameters: {'id': idNum},
    );
    if (fila.isEmpty) return _errorResponse('Usuario no encontrado', status: 404);
    if (fila.first[0] == sesion?['usuario']) {
      return _errorResponse('No puedes eliminar tu propio usuario');
    }
    await db.conn.execute(
      Sql.named('DELETE FROM usuarios WHERE id = @id'),
      parameters: {'id': idNum},
    );
    _cacheSesiones.clear();
    return _jsonResponse({'ok': true});
  });

  // ==========================================================================
  // 8. PIPELINE ETL: SINCRONIZACIÓN UNIDIRECCIONAL DE STOCK (HU-05 / RNF05)
  // ==========================================================================
  router.post('/api/v1/sync/inventory', (Request req) async {
    final tokenHeader =
        req.headers['authorization']?.replaceFirst('Bearer ', '');
    final expectedToken = db.env['SYNC_API_TOKEN'] ?? '';
    if (expectedToken.isEmpty) {
      return _jsonResponse(
          {'error': 'Sincronización deshabilitada: falta SYNC_API_TOKEN en el servidor.'},
          status: 503);
    }

    if (tokenHeader == null || !tokensIguales(tokenHeader, expectedToken)) {
      await db.conn.execute(
        '''
          INSERT INTO logs_sincronizacion (estado, mensaje_detalle)
          VALUES ('RECHAZADO', 'Token de agente local inválido')
        ''',
      );
      return _jsonResponse({'error': 'No autorizado'}, status: 401);
    }

    final body = await _leerJsonBody(req);
    final lote = ((body?['productos'] as List<dynamic>?) ?? []).whereType<Map>().toList();
    if (lote.length > 1000) {
      return _errorResponse('Máximo 1000 productos por lote', status: 413);
    }

    // Con "publicar": true los productos nuevos salen directo al catálogo.
    final publicar = body?['publicar'] == true;
    int procesados = 0;
    int agotados = 0;
    int nuevosPendientes = 0;
    final categoriasCache = <String, int>{};

    Future<int?> categoriaIdDe(String? nombre) async {
      final nom = nombre?.trim() ?? '';
      if (nom.isEmpty) return null;
      final clave = nom.toLowerCase();
      final cacheado = categoriasCache[clave];
      if (cacheado != null) return cacheado;
      final fila = await db.conn.execute(
        Sql.named('SELECT id FROM categorias WHERE nombre ILIKE @n LIMIT 1'),
        parameters: {'n': nom},
      );
      final id = fila.isNotEmpty
          ? fila.first[0] as int
          : (await db.conn.execute(
              Sql.named('INSERT INTO categorias (nombre) VALUES (@n) RETURNING id'),
              parameters: {'n': nom},
            ))
              .first[0] as int;
      categoriasCache[clave] = id;
      return id;
    }

    for (final item in lote) {
      var sku = item['codigo_interno']?.toString().trim();
      final stock = int.tryParse('${item['stock'] ?? 0}') ?? 0;
      var nombre = item['nombre']?.toString().trim() ?? 'Producto sin catalogar';
      if (nombre.isEmpty) nombre = 'Producto sin catalogar';
      if (nombre.length > 180) nombre = nombre.substring(0, 180);
      final precio = item['precio'] == null ? null : _numDe(item['precio']).toInt();
      final categoriaId = await categoriaIdDe(item['categoria']?.toString());
      final vehiculo = inferirVehiculo(nombre);

      if (sku == null || sku.isEmpty) continue;
      if (sku.length > 60) sku = sku.substring(0, 60);

      final existing = await db.conn.execute(
        Sql.named('SELECT id FROM productos WHERE codigo_interno = @sku'),
        parameters: {'sku': sku},
      );

      if (existing.isNotEmpty) {
        await db.conn.execute(
          Sql.named('''
            UPDATE productos 
            SET stock_actual = GREATEST(0, @stock - COALESCE((
                  SELECT SUM(rd.cantidad) FROM reserva_detalles rd
                  JOIN reservas rs ON rs.id = rd.reserva_id
                  WHERE rd.producto_id = productos.id AND rs.estado = 'confirmada' AND rs.stock_descontado), 0)),
                ultima_sincronizacion = CURRENT_TIMESTAMP,
                precio_referencia = COALESCE(@precio, precio_referencia),
                categoria_id = COALESCE(categoria_id, @cat),
                nombre = CASE
                  WHEN right(nombre, length(codigo_interno) + 3) = ' - ' || codigo_interno
                   AND right(@nombre::text, length(codigo_interno) + 3) <> ' - ' || codigo_interno
                  THEN @nombre::text ELSE nombre END,
                marca_referencia = CASE WHEN @marca::text IS NOT NULL AND COALESCE(marca_referencia, 'General') = 'General'
                                        THEN @marca::text ELSE marca_referencia END,
                modelo_referencia = CASE WHEN @modelo::text IS NOT NULL AND COALESCE(modelo_referencia, 'General') = 'General'
                                         THEN @modelo::text ELSE modelo_referencia END
            WHERE codigo_interno = @sku
          '''),
          parameters: {
            'stock': stock < 0 ? 0 : stock,
            'sku': sku,
            'nombre': nombre,
            'precio': precio == null ? null : (precio < 0 ? 0 : precio),
            'cat': categoriaId,
            'marca': vehiculo?.marca,
            'modelo': vehiculo?.modelo,
          },
        );
      } else {
        await db.conn.execute(
          Sql.named('''
            INSERT INTO productos (codigo_interno, nombre, stock_actual, estado_catalogo, categoria_id, precio_referencia,
                                   marca_referencia, modelo_referencia)
            VALUES (@sku, @nombre, @stock, @estado, @cat, @precio,
                    COALESCE(@marca::text, 'General'), COALESCE(@modelo::text, 'General'))
          '''),
          parameters: {
            'estado': publicar ? 'PUBLICADO' : 'PENDIENTE',
            'sku': sku,
            'nombre': nombre,
            'stock': stock < 0 ? 0 : stock,
            'cat': categoriaId,
            'precio': precio == null || precio < 0 ? 0 : precio,
            'marca': vehiculo?.marca,
            'modelo': vehiculo?.modelo,
          },
        );
        nuevosPendientes++;
      }

      procesados++;
      if (stock <= 0) agotados++;
    }

    // Un sync completo llega en lotes: los intermedios envían "parcial": true y
    // no generan registro; el último trae en "resumen" lo acumulado de los
    // lotes anteriores y deja UNA sola fila con el total.
    // Sin esas marcas (agentes antiguos) se registra cada lote.
    if (body?['parcial'] != true) {
      final resumen = body?['resumen'] is Map ? body!['resumen'] as Map : const {};
      int previo(String k) => resumen[k] is num ? (resumen[k] as num).toInt() : 0;
      await db.conn.execute(
        Sql.named('''
          INSERT INTO logs_sincronizacion (total_procesados, total_agotados, nuevos_pendientes, estado, mensaje_detalle)
          VALUES (@proc, @agot, @nuevos, 'EXITOSO', 'Sincronización unidireccional completada')
        '''),
        parameters: {
          'proc': previo('procesados') + procesados,
          'agot': previo('agotados') + agotados,
          'nuevos': previo('nuevos') + nuevosPendientes,
        },
      );
    }

    return _jsonResponse({
      'status': 'sincronizado',
      'total_procesados': procesados,
      'total_agotados_marcados': agotados,
      'nuevos_pendientes_catalogacion': nuevosPendientes,
    });
  });

  // ==========================================================================
  // 9. DASHBOARD UNIFICADO + ANALÍTICA DE DEMANDA INSATISFECHA (HU-06 / RF06)
  // ==========================================================================
  Future<Map<String, dynamic>> construirDatosDashboard() async {
    final resTotales = await db.conn.execute('''
      SELECT 
        COUNT(*) AS total_reservas,
        COUNT(*) FILTER (WHERE LOWER(estado) = 'pendiente') AS pendientes,
        COUNT(*) FILTER (WHERE LOWER(estado) IN ('confirmada', 'entregada', 'concretada')) AS concretadas
      FROM reservas
    ''');

    final resVentas = await db.conn.execute(
        'SELECT COUNT(*), COALESCE(SUM(total), 0) FROM ventas');

    final totalReservas = _numDe(resTotales.first[0]).toInt();
    final reservasPendientes = _numDe(resTotales.first[1]).toInt();
    final reservasConcretadas = _numDe(resTotales.first[2]).toInt();

    final conteos = await db.conn.execute('''
      SELECT COUNT(*) FILTER (WHERE stock_actual > 0 AND stock_actual <= 3),
             COUNT(*) FILTER (WHERE stock_actual <= 0)
      FROM productos WHERE estado_catalogo = 'PUBLICADO'
    ''');
    final stockBajoCount = _numDe(conteos.first[0]).toInt();
    final agotadosCount = _numDe(conteos.first[1]).toInt();

    final calidad = await db.conn.execute('''
      SELECT COUNT(*) FILTER (WHERE estado_catalogo = 'PUBLICADO'),
             COUNT(*) FILTER (WHERE estado_catalogo = 'PUBLICADO' AND COALESCE(precio_referencia, 0) <= 0),
             COUNT(*) FILTER (WHERE estado_catalogo = 'PUBLICADO' AND COALESCE(imagen_url, '') = ''),
             COUNT(*) FILTER (WHERE estado_catalogo = 'OCULTO'),
             (SELECT to_char(MAX(fecha_inicio), 'YYYY-MM-DD"T"HH24:MI:SS"Z"') FROM logs_sincronizacion WHERE estado = 'EXITOSO'),
             (SELECT EXTRACT(EPOCH FROM (LOCALTIMESTAMP - MAX(fecha_inicio)))::int FROM logs_sincronizacion WHERE estado = 'EXITOSO')
      FROM productos
    ''');
    final cal = calidad.first;

    // Lo confirmado y aún no entregado: stock apartado para clientes que vienen a retirar.
    final retenido = await db.conn.execute('''
      SELECT COUNT(DISTINCT r.id), COALESCE(SUM(rd.cantidad), 0),
             COALESCE(SUM(rd.cantidad * COALESCE(p.precio_referencia, 0)), 0)
      FROM reservas r
      JOIN reserva_detalles rd ON rd.reserva_id = r.id
      JOIN productos p ON p.id = rd.producto_id
      WHERE LOWER(r.estado) = 'confirmada'
    ''');
    final ret = retenido.first;

    // Solo se envían los 50 más urgentes; el total real va en *Count.
    final stockBajoRows = await db.conn.execute('''
      SELECT p.id, p.nombre, p.stock_actual, COALESCE(c.nombre, 'General')
      FROM productos p LEFT JOIN categorias c ON c.id = p.categoria_id
      WHERE p.stock_actual > 0 AND p.stock_actual <= 3 AND p.estado_catalogo = 'PUBLICADO'
      ORDER BY p.stock_actual ASC, p.nombre ASC
      LIMIT 50
    ''');

    final agotadosRows = await db.conn.execute('''
      SELECT p.id, p.nombre, COALESCE(c.nombre, 'General')
      FROM productos p LEFT JOIN categorias c ON c.id = p.categoria_id
      WHERE p.es_agotado = TRUE AND p.estado_catalogo = 'PUBLICADO'
      ORDER BY p.nombre ASC
      LIMIT 50
    ''');

    final topAgotados = await db.conn.execute('''
      SELECT termino_buscado, COUNT(*) AS total
      FROM metricas_demanda
      WHERE tipo_evento = 'INTERACCION_AGOTADO'
      GROUP BY termino_buscado
      ORDER BY total DESC
      LIMIT 10
    ''');

    final busquedasFallidas = await db.conn.execute('''
      SELECT termino_buscado, COALESCE(marca_consultada, 'General') AS marca, COUNT(*) AS total
      FROM metricas_demanda
      WHERE tipo_evento = 'BUSQUEDA_SIN_RESULTADO'
      GROUP BY termino_buscado, marca_consultada
      ORDER BY total DESC
      LIMIT 10
    ''');

    return {
      // Campos esperados por admin_screen.dart de tu compañera:
      'totalVentas': _numDe(resVentas.first[0]).toInt(),
      'montoVentas': _numDe(resVentas.first[1]),
      'reservasConcretadas': reservasConcretadas,
      'totalReservas': totalReservas,
      'reservasPendientes': reservasPendientes,
      'stockBajoCount': stockBajoCount,
      'agotadosCount': agotadosCount,
      'productosPublicados': _numDe(cal[0]).toInt(),
      'reservasConfirmadas': _numDe(ret[0]).toInt(),
      'unidadesRetenidas': _numDe(ret[1]).toInt(),
      'montoRetenido': _numDe(ret[2]),
      'sinPrecioCount': _numDe(cal[1]).toInt(),
      'sinFotoCount': _numDe(cal[2]).toInt(),
      'ocultosCount': _numDe(cal[3]).toInt(),
      'ultimaSincronizacion': cal[4],
      'haceSegundos': cal[5],
      'stockBajo': stockBajoRows
          .map((r) => {'id': r[0], 'nombre': r[1], 'stock': r[2], 'categoria': r[3]})
          .toList(),
      'agotados': agotadosRows
          .map((r) => {'id': r[0], 'nombre': r[1], 'categoria': r[2]})
          .toList(),
      // Campos de Analítica BI del Informe (HU-06):
      'top_repuestos_agotados': topAgotados
          .map((r) => {'repuesto': r[0], 'consultas': _numDe(r[1]).toInt()})
          .toList(),
      'busquedas_sin_resultado': busquedasFallidas
          .map((r) => {
                'termino': r[0],
                'marca': r[1],
                'frecuencia': _numDe(r[2]).toInt()
              })
          .toList(),
    };
  }

  router.get('/api/admin/dashboard', (Request req) async {
    return _jsonResponse(await construirDatosDashboard());
  });

  router.get('/api/admin/analytics', (Request req) async {
    return _jsonResponse(await construirDatosDashboard());
  });

  // ==========================================================================
  // VENTAS EN SUCURSAL (registradas desde el panel, descuentan stock)
  // ==========================================================================
  Map<String, dynamic> ventaAJson(ResultRow r) => {
        'id': r[0],
        'fecha': (r[1] as DateTime).toIso8601String(),
        'repuestoId': r[2] ?? 0,
        'sku': r[3],
        'producto': r[4],
        'precio': r[5],
        'cantidad': r[6],
        'total': r[7],
        'cliente': r[8] ?? '',
        'metodoPago': r[9] ?? '',
        'nota': r[10] ?? '',
        'categoria': r[11] ?? '',
      };

  const columnasVenta =
      'folio, creado_en, producto_id, sku, producto_nombre, precio_unitario, cantidad, total, cliente, metodo_pago, nota, '
      '(SELECT c.nombre FROM productos pr JOIN categorias c ON c.id = pr.categoria_id WHERE pr.id = ventas.producto_id)';

  router.get('/api/admin/ventas', (Request req) async {
    final rows = await db.conn.execute(
        'SELECT $columnasVenta FROM ventas ORDER BY creado_en DESC LIMIT 1000');
    return _jsonResponse(rows.map(ventaAJson).toList());
  });

  router.post('/api/admin/ventas', (Request req) async {
    final body = await _leerJsonBody(req);
    if (body == null) return _errorResponse('JSON inválido');
    final productoId = _numDe(body['repuestoId']).toInt();
    final cantidad = _numDe(body['cantidad'], 0).toInt();
    if (cantidad <= 0) return _errorResponse('La cantidad debe ser mayor a 0');
    final sesion = req.context['adminSesion'] as Map<String, dynamic>?;

    try {
      final venta = await db.conn.runTx((tx) async {
        final prod = await tx.execute(
          Sql.named(
              'SELECT codigo_interno, nombre, precio_referencia, stock_actual FROM productos WHERE id = @id FOR UPDATE'),
          parameters: {'id': productoId},
        );
        if (prod.isEmpty) throw const _ErrorNegocio('El producto no existe');
        final stock = prod.first[3] as int;
        if (stock < cantidad) {
          throw _ErrorNegocio('Stock insuficiente: quedan $stock unidades');
        }
        final precio = (prod.first[2] as int?) ?? 0;
        await tx.execute(
          Sql.named(
              'UPDATE productos SET stock_actual = stock_actual - @cant, ultima_sincronizacion = CURRENT_TIMESTAMP WHERE id = @id'),
          parameters: {'cant': cantidad, 'id': productoId},
        );
        final ins = await tx.execute(
          Sql.named('''
            INSERT INTO ventas (producto_id, sku, producto_nombre, precio_unitario, cantidad, total, cliente, metodo_pago, nota, usuario_registro)
            VALUES (@pid, @sku, @nombre, @precio, @cant, @total, @cliente, @metodo, @nota, @usuario)
            RETURNING $columnasVenta
          '''),
          parameters: {
            'pid': productoId,
            'sku': prod.first[0],
            'nombre': prod.first[1],
            'precio': precio,
            'cant': cantidad,
            'total': precio * cantidad,
            'cliente': body['cliente']?.toString() ?? '',
            'metodo': body['metodoPago']?.toString() ?? '',
            'nota': body['nota']?.toString() ?? '',
            'usuario': sesion?['usuario']?.toString(),
          },
        );
        return ventaAJson(ins.first);
      });
      return _jsonResponse(venta, status: 201);
    } on _ErrorNegocio catch (e) {
      return _errorResponse(e.mensaje);
    }
  });

  // ==========================================================================
  // DOCUMENTACIÓN DE LA API (OpenAPI + Swagger UI)
  // ==========================================================================
  router.get('/api/docs/openapi.yaml', (Request req) async {
    final archivo = File(p.join(_dirBackend, 'docs', 'openapi.yaml'));
    if (!await archivo.exists()) {
      return _errorResponse('Especificación no encontrada', status: 404);
    }
    return Response.ok(
      await archivo.readAsString(),
      headers: {'content-type': 'application/yaml; charset=utf-8'},
    );
  });

  router.get('/api/docs', (Request req) {
    return Response.ok(
      _paginaSwagger,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  });

  // ==========================================================================
  // 10. SERVIDOR ESTÁTICO FLUTTER WEB + PIPELINE DE MIDDLEWARES
  // ==========================================================================
  Handler handler = router.call;

  Directory(_dirUploads).createSync(recursive: true);
  final mediaHandler = createStaticHandler(p.dirname(_dirUploads));
  handler = Cascade()
      .add(handler)
      .add((Request req) => req.url.path.startsWith('media/')
          ? mediaHandler(req.change(path: 'media'))
          : Response.notFound('Not Found'))
      .handler;

  final buildWebDir = Directory(rutaBuildWeb);
  if (buildWebDir.existsSync()) {
    final staticHandler = createStaticHandler(
      rutaBuildWeb,
      defaultDocument: 'index.html',
    );
    handler = Cascade().add(handler).add(staticHandler).handler;
  }

  final pipeline = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_cabecerasSeguras())
      .addMiddleware(_erroresComoJson())
      .addMiddleware(corsHeaders(headers: {ACCESS_CONTROL_ALLOW_ORIGIN: _origenCors}))
      .addMiddleware(_authSoloAdmin())
      .addHandler(handler);

  final port = int.tryParse(db.env['PORT'] ?? '8080') ?? 8080;
  final server = await io.serve(pipeline, InternetAddress.anyIPv4, port);
  print(
      '🚀 Servidor Backend Unificado Maykel Repuestos 2 (PostgreSQL) corriendo en http://${server.address.host}:${server.port}');
}
/// Swagger UI se carga desde un CDN, por lo que la página requiere internet.
const String _paginaSwagger = '''<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <title>Maykel Repuestos 2 - Documentación API</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script>
    window.ui = SwaggerUIBundle({
      url: '/api/docs/openapi.yaml',
      dom_id: '#swagger-ui',
      deepLinking: true
    });
  </script>
</body>
</html>''';

/// Error de validación de negocio que se devuelve al cliente (400 por defecto).
class _ErrorNegocio implements Exception {
  final String mensaje;
  final int status;
  const _ErrorNegocio(this.mensaje, [this.status = 400]);
}
