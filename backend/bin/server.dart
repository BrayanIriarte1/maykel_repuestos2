// ============================================================================
// SERVER.DART UNIFICADO - MAYKEL REPUESTOS 2 (CALAMA)
// Arquitectura de 3 Capas: Flutter Web -> API REST Dart (Shelf) -> PostgreSQL
// Cumple IEEE 830 (RF01-RF07, RNF01-RNF06) y 100% compatible con Frontend app/
// ============================================================================

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
  final texto = await request.readAsString();
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
      'titulo': 'Más de una década sirviendo a Calama',
      'texto':
          'Maykel Repuestos Limitada provee repuestos, accesorios e insumos automotrices '
              'y mineros que garantizan la continuidad operativa de clientes particulares, '
              'talleres mecánicos y flotas en Calama y la Región de Antofagasta.',
      'fichas': [
        {'etiqueta': 'Ubicación', 'valor': 'Vargas #2275, Calama'},
        {'etiqueta': 'Especialidad', 'valor': 'Marcas Chinas e Insumos Mineros'},
        {'etiqueta': 'Stock', 'valor': 'Sincronización periódica con bodega'},
        {'etiqueta': 'Atención', 'valor': 'Presencial, WhatsApp y Reserva PDF'},
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
      'horario': 'Lunes a viernes, 9:30 – 19:00\nSábado, 9:30 – 14:00',
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

Future<Map<String, dynamic>?> _autenticar(Request request) async {
  final authHeader = request.headers['authorization'];
  if (authHeader == null || !authHeader.startsWith('Basic ')) return null;

  try {
    final credenciales =
        utf8.decode(base64.decode(authHeader.substring(6).trim()));
    final separador = credenciales.indexOf(':');
    if (separador < 0) return null;
    final usuarioInput = credenciales.substring(0, separador).trim();
    final passwordInput = credenciales.substring(separador + 1).trim();

    // 1. Acceso inmediato para SuperAdmin maestro (evita bloqueos si la tabla roles aún no se migra)
    final envAdmins = db.env['ADMIN_USERS'] ?? 'admin:maykel2026,francisca:maykel2026,daniel:maykel2026';
    for (final par in envAdmins.split(',')) {
      final partes = par.split(':');
      if (partes.length >= 2 &&
          partes[0].trim() == usuarioInput &&
          partes.sublist(1).join(':').trim() == passwordInput) {
        return {
          'usuario': usuarioInput,
          'permisos': permisosDisponibles,
          'esSuperAdmin': true,
          'rolNombre': 'Superadministrador',
        };
      }
    }

    // 2. Verificación en Base de Datos PostgreSQL (Tabla usuarios + roles)
    final rows = await db.conn.execute(
      Sql.named('''
        SELECT u.usuario, u.nombre, u.rol, u.activo, r.nombre AS rol_nombre, r.permisos
        FROM usuarios u
        LEFT JOIN roles r ON u.rol_id = r.id
        WHERE (u.usuario = @usr OR u.email = @usr) AND u.password_hash = @pwd AND u.activo = TRUE
        LIMIT 1
      '''),
      parameters: {'usr': usuarioInput, 'pwd': passwordInput},
    );

    if (rows.isNotEmpty) {
      final r = rows.first;
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
    return null;
  }
  return null;
}

Middleware _authSoloAdmin() {
  return (Handler innerHandler) {
    return (Request request) async {
      // CRÍTICO PARA CHROME (CORS PREFLIGHT):
      // Si el navegador envía una consulta OPTIONS para verificar permisos CORS,
      // debemos dejarla pasar sin exigir contraseña.
      if (request.method.toUpperCase() == 'OPTIONS') {
        return Response.ok('', headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization, Accept',
        });
      }

      if (request.url.path.startsWith('api/admin/')) {
        final sesion = await _autenticar(request);
        if (sesion != null) {
          final actualizado = request.change(context: {'adminSesion': sesion});
          return innerHandler(actualizado);
        }

        return Response(
          401,
          body: jsonEncode({
            'error': 'Credenciales inválidas. Usa admin / maykel2026'
          }),
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'Access-Control-Allow-Origin': '*',
          },
        );
      }
      return innerHandler(request);
    };
  };
}

void main(List<String> args) async {
  await db.init();

  final router = Router();

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
    final countRes = await db.conn.execute(
      "SELECT COUNT(*) FROM productos WHERE estado_catalogo = 'PUBLICADO'",
    );
    final total = _numDe(countRes.first[0]).toInt();
    return _jsonResponse({
      'esDatosDeEjemplo': false,
      'totalProductos': total,
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
    final queryText = (qp['q'] ?? qp['buscar'])?.trim();
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
      params['q'] = '%$queryText%';
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
          params['moNombre'] = '%$modeloParam%';
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
      FROM productos p
      LEFT JOIN categorias c ON p.categoria_id = c.id
      LEFT JOIN producto_compatibilidad pc ON p.id = pc.producto_id
      LEFT JOIN versiones_vehiculo vv ON pc.version_vehiculo_id = vv.id
      LEFT JOIN modelos mo ON vv.modelo_id = mo.id
      LEFT JOIN marcas m ON mo.marca_id = m.id
      WHERE $whereClause
      ORDER BY p.es_agotado ASC, p.nombre ASC
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

    return _jsonResponse(productos);
  }

  router.get('/api/productos', manejarConsultaCatalogo);
  router.get('/api/repuestos', manejarConsultaCatalogo);

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
      items = List<Map<String, dynamic>>.from(body['items'] as List);
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

    // Restricción Cap. 5.1.2 del Informe:
    // "Una reserva web no descuenta inventario físico de forma automática. Queda Pendiente de confirmación".
    final result = await db.conn.runTx((tx) async {
      final resCabecera = await tx.execute(
        Sql.named('''
          INSERT INTO reservas 
          (cliente_nombre, cliente_telefono, cliente_email, cliente_rut_o_taller, nota, estado, notificado_whatsapp, notificado_email)
          VALUES (@nombre, @telefono, @email, @taller, @nota, 'pendiente', TRUE, TRUE)
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

        final prodRow = await tx.execute(
          Sql.named(
              'SELECT codigo_interno, nombre, stock_actual FROM productos WHERE id = @id'),
          parameters: {'id': prodId},
        );
        if (prodRow.isEmpty) {
          throw Exception('El producto ID $prodId no existe');
        }
        primerSku = prodRow.first[0].toString();
        primerProductoNombre = prodRow.first[1].toString();
        primeraCantidad = cant;
        primerProdId = prodId;

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

    return _jsonResponse(result, status: 201);
  });

  router.get('/api/admin/reservas', (Request req) async {
    final rows = await db.conn.execute('''
      SELECT 
        r.folio,
        r.creado_en,
        COALESCE(p.id, 0) AS repuesto_id,
        COALESCE(p.codigo_interno, 'S/C') AS sku,
        COALESCE(p.nombre, 'Múltiples repuestos') AS producto,
        COALESCE(rd.cantidad, 1) AS cantidad,
        r.cliente_nombre,
        r.cliente_telefono,
        r.cliente_email,
        COALESCE(r.nota, '') AS nota,
        LOWER(r.estado) AS estado
      FROM reservas r
      LEFT JOIN reserva_detalles rd ON r.id = rd.reserva_id
      LEFT JOIN productos p ON rd.producto_id = p.id
      ORDER BY r.creado_en DESC
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
            })
        .toList();

    return _jsonResponse(lista);
  });

  router.put('/api/admin/reservas/<id>', (Request req, String id) async {
    final body = await _leerJsonBody(req);
    final estado = body?['estado']?.toString().toLowerCase();
    const validos = ['pendiente', 'confirmada', 'entregada', 'rechazada'];
    if (estado == null || !validos.contains(estado)) {
      return _errorResponse('Estado inválido');
    }

    await db.conn.execute(
      Sql.named('''
        UPDATE reservas 
        SET estado = @estado, actualizado_en = CURRENT_TIMESTAMP
        WHERE folio = @id OR id::text = @id
      '''),
      parameters: {'estado': estado, 'id': id},
    );

    return _jsonResponse({'id': id, 'estado': estado});
  });

  // ==========================================================================
  // 6. BACKOFFICE: GESTIÓN DEL CATÁLOGO TÉCNICO EN POSTGRESQL (HU-07 / RF07)
  // ==========================================================================
  router.put('/api/admin/repuestos', (Request req) async {
    final body = await _leerJsonBody(req);
    final cambios = body?['cambios'];
    if (cambios is! List) return _errorResponse('Formato inválido');

    for (final cambioRaw in cambios) {
      final cambio = cambioRaw as Map<String, dynamic>;
      final id = _numDe(cambio['id']).toInt();
      if (cambio['stock'] != null) {
        final stock = _numDe(cambio['stock']).toInt();
        await db.conn.execute(
          Sql.named(
              'UPDATE productos SET stock_actual = @stock, ultima_sincronizacion = CURRENT_TIMESTAMP WHERE id = @id'),
          parameters: {'stock': stock < 0 ? 0 : stock, 'id': id},
        );
      }
    }
    return _jsonResponse({'ok': true});
  });

  router.post('/api/admin/repuestos', (Request req) async {
    final body = await _leerJsonBody(req);
    if (body == null) return _errorResponse('JSON inválido');

    final nombre = body['nombre']?.toString().trim() ?? '';
    if (nombre.isEmpty) {
      return _errorResponse('El nombre del producto es obligatorio');
    }

    final categoriaNombre = body['categoria']?.toString().trim() ?? 'General';
    final marcaNombre = body['marca']?.toString().trim() ?? 'General';
    final modeloNombre = body['modelo']?.toString().trim() ?? 'Compatible';
    final stock = _numDe(body['stock'], 0).toInt();
    final sku = body['sku']?.toString().trim() ??
        'MR-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

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

    final inserted = await db.conn.execute(
      Sql.named('''
        INSERT INTO productos 
        (codigo_interno, nombre, categoria_id, marca_referencia, modelo_referencia, stock_actual, estado_catalogo)
        VALUES (@sku, @nombre, @catId, @marca, @modelo, @stock, 'PUBLICADO')
        RETURNING id
      '''),
      parameters: {
        'sku': sku,
        'nombre': nombre,
        'catId': categoriaId,
        'marca': marcaNombre,
        'modelo': modeloNombre,
        'stock': stock < 0 ? 0 : stock,
      },
    );

    return _jsonResponse({
      'id': inserted.first[0],
      'sku': sku,
      'nombre': nombre,
      'categoria': categoriaNombre,
      'marca': marcaNombre,
      'modelo': modeloNombre,
      'precio': 0,
      'stock': stock,
      'es_ejemplo': false,
    }, status: 201);
  });

  router.delete('/api/admin/repuestos/<id>', (Request req, String id) async {
    final idNum = int.tryParse(id);
    if (idNum == null) return _errorResponse('ID inválido');
    await db.conn.execute(
      Sql.named('DELETE FROM productos WHERE id = @id'),
      parameters: {'id': idNum},
    );
    return _jsonResponse({'ok': true});
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
    if (nombre.isEmpty || permisos is! List) {
      return _errorResponse('Nombre y lista de permisos son obligatorios');
    }
    final res = await db.conn.execute(
      Sql.named(
          'INSERT INTO roles (nombre, permisos) VALUES (@nom, @perm::jsonb) RETURNING id'),
      parameters: {'nom': nombre, 'perm': jsonEncode(permisos)},
    );
    return _jsonResponse(
        {'id': res.first[0], 'nombre': nombre, 'permisos': permisos},
        status: 201);
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
        'pwd': password,
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

  // ==========================================================================
  // 8. PIPELINE ETL: SINCRONIZACIÓN UNIDIRECCIONAL DE STOCK (HU-05 / RNF05)
  // ==========================================================================
  router.post('/api/v1/sync/inventory', (Request req) async {
    final tokenHeader =
        req.headers['authorization']?.replaceFirst('Bearer ', '');
    final expectedToken =
        db.env['SYNC_API_TOKEN'] ?? 'maykel2_sync_token_secreto_2026';

    if (tokenHeader != expectedToken) {
      await db.conn.execute(
        '''
          INSERT INTO logs_sincronizacion (estado, mensaje_detalle)
          VALUES ('RECHAZADO', 'Token de agente local inválido')
        ''',
      );
      return _jsonResponse({'error': 'No autorizado'}, status: 401);
    }

    final body = await _leerJsonBody(req);
    final lote = (body?['productos'] as List<dynamic>?) ?? [];

    int procesados = 0;
    int agotados = 0;
    int nuevosPendientes = 0;

    for (final item in lote) {
      final sku = item['codigo_interno']?.toString().trim();
      final stock = int.tryParse(item['stock'].toString()) ?? 0;
      final nombre =
          item['nombre']?.toString().trim() ?? 'Producto sin catalogar';

      if (sku == null || sku.isEmpty) continue;

      final existing = await db.conn.execute(
        Sql.named('SELECT id FROM productos WHERE codigo_interno = @sku'),
        parameters: {'sku': sku},
      );

      if (existing.isNotEmpty) {
        await db.conn.execute(
          Sql.named('''
            UPDATE productos 
            SET stock_actual = @stock, ultima_sincronizacion = CURRENT_TIMESTAMP
            WHERE codigo_interno = @sku
          '''),
          parameters: {'stock': stock < 0 ? 0 : stock, 'sku': sku},
        );
      } else {
        await db.conn.execute(
          Sql.named('''
            INSERT INTO productos (codigo_interno, nombre, stock_actual, estado_catalogo)
            VALUES (@sku, @nombre, @stock, 'PENDIENTE')
          '''),
          parameters: {
            'sku': sku,
            'nombre': nombre,
            'stock': stock < 0 ? 0 : stock
          },
        );
        nuevosPendientes++;
      }

      procesados++;
      if (stock <= 0) agotados++;
    }

    await db.conn.execute(
      Sql.named('''
        INSERT INTO logs_sincronizacion (total_procesados, total_agotados, nuevos_pendientes, estado, mensaje_detalle)
        VALUES (@proc, @agot, @nuevos, 'EXITOSO', 'Sincronización unidireccional completada')
      '''),
      parameters: {
        'proc': procesados,
        'agot': agotados,
        'nuevos': nuevosPendientes
      },
    );

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

    final totalReservas = _numDe(resTotales.first[0]).toInt();
    final reservasPendientes = _numDe(resTotales.first[1]).toInt();
    final reservasConcretadas = _numDe(resTotales.first[2]).toInt();

    final stockBajoRows = await db.conn.execute('''
      SELECT id, nombre, stock_actual 
      FROM productos 
      WHERE stock_actual > 0 AND stock_actual <= 3 AND estado_catalogo = 'PUBLICADO'
      ORDER BY stock_actual ASC
    ''');

    final agotadosRows = await db.conn.execute('''
      SELECT id, nombre 
      FROM productos 
      WHERE es_agotado = TRUE AND estado_catalogo = 'PUBLICADO'
      ORDER BY nombre ASC
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
      'totalVentas': reservasConcretadas,
      'montoVentas': 0, // Sin cobros en línea (política ROPO)
      'totalReservas': totalReservas,
      'reservasPendientes': reservasPendientes,
      'stockBajoCount': stockBajoRows.length,
      'agotadosCount': agotadosRows.length,
      'stockBajo': stockBajoRows
          .map((r) => {'id': r[0], 'nombre': r[1], 'stock': r[2]})
          .toList(),
      'agotados':
          agotadosRows.map((r) => {'id': r[0], 'nombre': r[1]}).toList(),
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

  // Endpoints de compatibilidad para pestaña historial de cierres en panel admin
  router.get('/api/admin/ventas', (Request req) async {
    return _jsonResponse([]);
  });

  // ==========================================================================
  // 10. SERVIDOR ESTÁTICO FLUTTER WEB + PIPELINE DE MIDDLEWARES
  // ==========================================================================
  Handler handler = router.call;

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
      .addMiddleware(corsHeaders())
      .addMiddleware(_authSoloAdmin())
      .addHandler(handler);

  final port = int.tryParse(db.env['PORT'] ?? '8080') ?? 8080;
  final server = await io.serve(pipeline, InternetAddress.anyIPv4, port);
  print(
      '🚀 Servidor Backend Unificado Maykel Repuestos 2 (PostgreSQL) corriendo en http://${server.address.host}:${server.port}');
}