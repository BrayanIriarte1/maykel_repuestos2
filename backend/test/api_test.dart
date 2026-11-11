// Pruebas de integración contra un servidor ya en ejecución.
// Uso (desde backend/):  dart test
// Variables opcionales: TEST_BASE (default http://localhost:8080),
// TEST_ADMIN_USER / TEST_ADMIN_PASS, TEST_SYNC_TOKEN.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

final base = Platform.environment['TEST_BASE'] ?? 'http://localhost:8080';
final adminUser = Platform.environment['TEST_ADMIN_USER'] ?? 'admin';
final adminPass = Platform.environment['TEST_ADMIN_PASS'] ?? 'maykel2026';
final syncToken = Platform.environment['TEST_SYNC_TOKEN'] ?? _tokenDeEnv();

String _tokenDeEnv() {
  final f = File('.env');
  if (f.existsSync()) {
    for (final l in f.readAsLinesSync()) {
      if (l.startsWith('SYNC_API_TOKEN=')) {
        return l.substring('SYNC_API_TOKEN='.length).trim();
      }
    }
  }
  return '';
}

late Map<String, String> adminHeaders;
final _sku = 'TEST-RES-${DateTime.now().millisecondsSinceEpoch}';

Uri u(String path) => Uri.parse(base + path);

Map<String, String> conToken(String token) =>
    {'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'};

Future<http.Response> login(String usuario, String password) => http.post(
      u('/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'usuario': usuario, 'password': password}),
    );

void main() {
  setUpAll(() async {
    final r = await login(adminUser, adminPass);
    expect(r.statusCode, 200, reason: 'No se pudo iniciar sesión de prueba');
    adminHeaders = conToken(jsonDecode(r.body)['token'].toString());
  });

  group('Públicas', () {
    test('health responde 200', () async {
      expect((await http.get(u('/api/health'))).statusCode, 200);
    });

    test('catálogo devuelve lista y oculta precios (RF01)', () async {
      final r = await http.get(u('/api/repuestos'));
      expect(r.statusCode, 200);
      final data = jsonDecode(r.body);
      final lista = data is List ? data : (data['repuestos'] ?? data['data']);
      expect(lista, isA<List>());
      expect(lista, isNotEmpty);
      expect(lista.first['precio'], 0);
    });

    test('marcas y categorías', () async {
      expect((await http.get(u('/api/marcas'))).statusCode, 200);
      expect((await http.get(u('/api/categorias'))).statusCode, 200);
    });

    test('búsqueda en tiempo ≤ 1,8 s (RNF02)', () async {
      final sw = Stopwatch()..start();
      final r = await http.get(u('/api/repuestos?q=freno'));
      sw.stop();
      expect(r.statusCode, 200);
      expect(sw.elapsedMilliseconds, lessThanOrEqualTo(1800));
    });

    test('catálogo paginado devuelve total y respeta el límite', () async {
      final r = await http.get(u('/api/repuestos?limite=5&pagina=1'));
      expect(r.statusCode, 200);
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      expect((data['items'] as List).length, lessThanOrEqualTo(5));
      expect(data['total'], isA<int>());
    });

    test('filtro jerárquico marca → modelo es coherente con el catálogo', () async {
      final f = jsonDecode((await http.get(u('/api/catalogo/filtros'))).body);
      final marcas = f['marcas'] as List;
      if (marcas.isEmpty) return;
      final marca = marcas.first['nombre'] as String;
      final r = await http.get(u('/api/repuestos?limite=5&marca=${Uri.encodeQueryComponent(marca)}'));
      final data = jsonDecode(r.body);
      expect(data['total'], marcas.first['total']);
      expect((await http.get(u('/api/catalogo/filtros?marca=${Uri.encodeQueryComponent(marca)}'))).statusCode, 200);
    });

    test('documentación OpenAPI disponible', () async {
      expect((await http.get(u('/api/docs'))).statusCode, 200);
      expect((await http.get(u('/api/docs/openapi.yaml'))).statusCode, 200);
    });
  });

  group('Reservas (RF03)', () {
    test('reserva con varios repuestos devuelve folio, ítems y PDF válido', () async {
      final lista = jsonDecode((await http.get(u('/api/repuestos?limite=40'))).body);
      final ids = (lista['items'] as List)
          .where((e) => (e['stock'] as num) >= 1 && e['es_ejemplo'] != true)
          .take(2)
          .map((e) => e['id'])
          .toList();
      if (ids.length < 2) return;
      final r = await http.post(u('/api/reservas'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'nombre': 'Prueba PDF Ñandú',
            'telefono': '+56911111111',
            'email': 'prueba@ejemplo.cl',
            'items': [
              {'producto_id': ids[0], 'cantidad': 1},
              {'producto_id': ids[1], 'cantidad': 1},
            ],
          }));
      expect(r.statusCode, 201);
      final d = jsonDecode(r.body);
      expect(d['folio'], isNotEmpty);
      expect((d['items'] as List).length, 2);
      final pdf = base64Decode(d['pdf_base64'] as String);
      expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
    });

    test('búsqueda por palabras en cualquier orden y sin tildes', () async {
      Future<int> total(String q) async {
        final r = await http.get(u('/api/repuestos?limite=5&buscar=${Uri.encodeQueryComponent(q)}'));
        expect(r.statusCode, 200);
        return (jsonDecode(r.body)['total'] as num).toInt();
      }

      final base = await total('aceite');
      expect(base, greaterThan(0));
      // Mismo resultado sin importar el orden, las mayúsculas o las tildes.
      expect(await total('ACEITE'), base);
      final nombre = jsonDecode((await http.get(u('/api/repuestos?limite=1&buscar=aceite'))).body)['items'][0]['nombre'] as String;
      final palabras = nombre.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
      expect(palabras.length, greaterThanOrEqualTo(2));
      final invertida = palabras.reversed.take(2).join(' ');
      expect(await total(invertida), greaterThan(0), reason: 'No encontró "$invertida"');
      // Una palabra del medio sola también debe encontrarlo.
      expect(await total(palabras.last), greaterThan(0));
      // Algo inexistente da 0.
      expect(await total('zzqqxxnoexiste'), 0);
    });

    test('rechaza contacto inválido', () async {
      final r = await http.post(u('/api/reservas'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'cliente_nombre': 'Prueba',
            'cliente_telefono': '',
            'cliente_email': 'no-es-correo',
            'repuestoId': 1,
          }));
      expect(r.statusCode, 400);
    });

    test('rechaza reserva sin repuestos', () async {
      final r = await http.post(u('/api/reservas'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'cliente_nombre': 'Prueba',
            'cliente_telefono': '+56911111111',
            'cliente_email': 'prueba@correo.cl',
          }));
      expect(r.statusCode, 400);
    });

    test('JSON inválido devuelve 400', () async {
      final r = await http.post(u('/api/reservas'),
          headers: {'Content-Type': 'application/json'}, body: '{no-json');
      expect(r.statusCode, 400);
    });

    test('texto en otra codificación (Latin-1) no provoca 500', () async {
      final r = await http.post(u('/api/reservas'),
          headers: {'Content-Type': 'application/json'},
          body: [...'{"cliente_nombre":"P'.codeUnits, 0xE9, ...'rez"}'.codeUnits]);
      expect(r.statusCode, lessThan(500));
    });
  });

  group('Seguridad (RNF03)', () {
    for (final ruta in [
      '/api/admin/dashboard',
      '/api/admin/reservas',
      '/api/admin/repuestos',
      '/api/admin/usuarios',
      '/api/admin/ventas',
    ]) {
      test('$ruta sin credenciales → 401', () async {
        expect((await http.get(u(ruta))).statusCode, 401);
      });
    }

    test('login con clave incorrecta → 401', () async {
      expect((await login('admin', 'incorrecta')).statusCode, 401);
    });

    test('login devuelve JWT de 3 partes', () async {
      final r = await login(adminUser, adminPass);
      expect(r.statusCode, 200);
      final token = jsonDecode(r.body)['token'].toString();
      expect(token.split('.').length, 3);
    });

    test('token falso o manipulado → 401', () async {
      final falso = await http.get(u('/api/admin/dashboard'),
          headers: conToken('aaa.bbb.ccc'));
      expect(falso.statusCode, 401);
      final valido = adminHeaders['Authorization']!.substring(7);
      final alterado = await http.get(u('/api/admin/dashboard'),
          headers: conToken(valido + 'x'));
      expect(alterado.statusCode, 401);
    });

    test('Basic ya no es aceptado', () async {
      final r = await http.get(u('/api/admin/dashboard'), headers: {
        'Authorization':
            'Basic ' + base64Encode(utf8.encode('$adminUser:$adminPass'))
      });
      expect(r.statusCode, 401);
    });

    test('admin válido accede al dashboard', () async {
      final r = await http.get(u('/api/admin/dashboard'), headers: adminHeaders);
      expect(r.statusCode, 200);
    });

    test('vendedor no accede a usuarios (403)', () async {
      final l = await login('vendedor', 'ventas2026');
      if (l.statusCode != 200) return; // clave del vendedor ya cambiada
      final r = await http.get(u('/api/admin/usuarios'),
          headers: conToken(jsonDecode(l.body)['token'].toString()));
      expect(r.statusCode, 403);
    });

    test('vendedor no puede editar contenido (403)', () async {
      final l = await login('vendedor', 'ventas2026');
      if (l.statusCode != 200) return;
      final h = conToken(jsonDecode(l.body)['token'].toString());
      expect((await http.get(u('/api/admin/contenido'), headers: h)).statusCode, 403);
    });

    test('imagen: sin token 401, tipo inválido 400, producto inexistente 404', () async {
      expect((await http.post(u('/api/admin/repuestos/1/imagen'))).statusCode, 401);
      final tipo = await http.post(u('/api/admin/repuestos/1/imagen'),
          headers: {...adminHeaders, 'Content-Type': 'text/plain'}, body: 'x');
      expect(tipo.statusCode, anyOf(400, 415));
      final nada = await http.post(u('/api/admin/repuestos/999999999/imagen'),
          headers: {...adminHeaders, 'Content-Type': 'image/png'},
          body: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
      expect(nada.statusCode, 404);
    });

    test('reserva con cantidad inválida o sin producto → 400', () async {
      Future<http.Response> reservar(Map item) => http.post(u('/api/reservas'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'cliente_nombre': 'Prueba',
            'cliente_telefono': '+56911111111',
            'cliente_email': 'prueba@correo.cl',
            'items': [item],
          }));
      expect((await reservar({'cantidad': 1})).statusCode, 400);
      expect((await reservar({'producto_id': 1, 'cantidad': 5000})).statusCode, 400);
    });

    test('sync con token inválido → 401', () async {
      final r = await http.post(u('/api/v1/sync/inventory'),
          headers: conToken('token-falso'),
          body: jsonEncode({'productos': []}));
      expect(r.statusCode, 401);
    });
  });

  group('Notificaciones y sincronización (panel)', () {
    test('estado de notificaciones exige sesión y no filtra secretos', () async {
      expect((await http.get(u('/api/admin/notificaciones/estado'))).statusCode, 401);
      final r = await http.get(u('/api/admin/notificaciones/estado'), headers: adminHeaders);
      expect(r.statusCode, 200);
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      expect(d['correo'], isA<Map>());
      expect(d['whatsapp'], isA<Map>());
      expect(r.body.contains('SMTP_PASS='), isFalse);
    });

    test('probar correo sin configurar informa qué falta', () async {
      final r = await http.post(u('/api/admin/notificaciones/probar'),
          headers: adminHeaders, body: jsonEncode({'canal': 'correo'}));
      expect(r.statusCode, 200);
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      expect(d.containsKey('ok'), isTrue);
    });

    test('historial de sincronización protegido y con formato', () async {
      expect((await http.get(u('/api/admin/sync/historial'))).statusCode, 401);
      final r = await http.get(u('/api/admin/sync/historial'), headers: adminHeaders);
      expect(r.statusCode, 200);
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      expect(d['items'], isA<List>());
      expect(d['enCurso'], isA<bool>());
    });
  });

  group('Sincronización (RF05)', () {
    test('stock 0 y reposición se procesan y el SKU queda registrado',
        () async {
      const sku = 'TEST-SYNC-001';
      Future<http.Response> sync(int stock) => http.post(
            u('/api/v1/sync/inventory'),
            headers: conToken(syncToken),
            body: jsonEncode({
              'productos': [
                {
                  'codigo_interno': sku,
                  'nombre': 'Producto de prueba',
                  'stock': stock
                }
              ]
            }),
          );

      expect((await sync(0)).statusCode, 200);
      expect((await sync(5)).statusCode, 200);

      final lista = await http.get(u('/api/admin/repuestos?q=$sku'),
          headers: adminHeaders);
      expect(lista.statusCode, 200);
      expect(lista.body, contains(sku));
    });

    test('el sync de lotes parciales no deja registro y el final sí', () async {
      Future<http.Response> sync(Map extra) => http.post(
            u('/api/v1/sync/inventory'),
            headers: conToken(syncToken),
            body: jsonEncode({
              'productos': [
                {'codigo_interno': 'TEST-SYNC-001', 'nombre': 'Producto de prueba', 'stock': 2}
              ],
              ...extra,
            }),
          );
      Future<int> filas() async {
        final r = await http.get(u('/api/admin/dashboard'), headers: adminHeaders);
        return jsonDecode(r.body)['haceSegundos'] as int;
      }

      expect((await sync({'parcial': true})).statusCode, 200);
      final antes = await filas();
      expect((await sync({'resumen': {'procesados': 10}})).statusCode, 200);
      expect(await filas(), lessThanOrEqualTo(antes));
    });

    test('lote con elementos inválidos no rompe el servidor', () async {
      final r = await http.post(u('/api/v1/sync/inventory'),
          headers: conToken(syncToken),
          body: jsonEncode({
            'productos': [1, 'x', null, {'codigo_interno': 'TEST-SYNC-001', 'stock': 'abc'}],
            'parcial': true,
          }));
      expect(r.statusCode, 200);
    });
  });

  group('Reservas y stock', () {
    Future<int> stockDe(int id) async {
      final r = jsonDecode((await http.get(u('/api/admin/repuestos?q=${Uri.encodeQueryComponent(_sku)}'),
              headers: adminHeaders))
          .body);
      return (r['items'] as List).firstWhere((p) => p['id'] == id)['stock'] as int;
    }

    Future<Map<String, dynamic>> estado(String folio, String e) async {
      final r = await http.put(u('/api/admin/reservas/$folio'),
          headers: adminHeaders, body: jsonEncode({'estado': e}));
      return {'status': r.statusCode, 'body': jsonDecode(r.body)};
    }

    test('confirmar/entregar descuenta una vez; rechazar repone; sync respeta lo retenido',
        () async {
      Future<Map<String, dynamic>> dash() async => jsonDecode(
          (await http.get(u('/api/admin/dashboard'), headers: adminHeaders)).body);
      final base = await dash();

      final c = await http.post(u('/api/admin/repuestos'),
          headers: adminHeaders,
          body: jsonEncode({'nombre': 'Producto flujo reserva', 'sku': _sku, 'stock': 5, 'precio': 1000}));
      expect(c.statusCode, 201);
      final id = jsonDecode(c.body)['id'] as int;

      final rv = await http.post(u('/api/reservas'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'cliente_nombre': 'Prueba Stock',
            'cliente_telefono': '+56911111111',
            'cliente_email': 'stock@correo.cl',
            'items': [
              {'producto_id': id, 'cantidad': 2}
            ],
          }));
      expect(rv.statusCode, 201);
      final folio = jsonDecode(rv.body)['folio'] as String;
      expect(await stockDe(id), 5, reason: 'reservar no descuenta');

      expect((await estado(folio, 'confirmada'))['status'], 200);
      expect(await stockDe(id), 3, reason: 'confirmar descuenta');
      var d = await dash();
      expect(d['reservasConfirmadas'], base['reservasConfirmadas'] + 1);
      expect(d['unidadesRetenidas'], base['unidadesRetenidas'] + 2);
      expect(d['totalVentas'], base['totalVentas'], reason: 'confirmar aún no es venta');

      expect((await estado(folio, 'confirmada'))['status'], 200);
      expect(await stockDe(id), 3, reason: 'repetir el estado no descuenta de nuevo');

      // El sync trae 5 desde el sistema del cliente: se restan las 2 retenidas.
      final s = await http.post(u('/api/v1/sync/inventory'),
          headers: conToken(syncToken),
          body: jsonEncode({
            'productos': [
              {'codigo_interno': _sku, 'nombre': 'Producto flujo reserva', 'stock': 5}
            ],
            'parcial': true,
          }));
      expect(s.statusCode, 200);
      expect(await stockDe(id), 3, reason: 'el sync no devuelve el stock retenido');

      expect((await estado(folio, 'entregada'))['status'], 200);
      expect(await stockDe(id), 3, reason: 'entregar tras confirmar no descuenta otra vez');
      d = await dash();
      expect(d['totalVentas'], base['totalVentas'] + 1, reason: 'entregar registra una venta');
      expect(d['montoVentas'], base['montoVentas'] + 2000);
      expect(d['reservasConfirmadas'], base['reservasConfirmadas']);
      expect((await estado(folio, 'entregada'))['status'], 200);
      expect((await dash())['totalVentas'], base['totalVentas'] + 1, reason: 'sin ventas duplicadas');

      expect((await estado(folio, 'rechazada'))['status'], 200);
      expect(await stockDe(id), 5, reason: 'rechazar repone');
      d = await dash();
      expect(d['totalVentas'], base['totalVentas'], reason: 'rechazar anula la venta');
      expect(d['montoVentas'], base['montoVentas']);

      // Stock insuficiente al confirmar → 409 y sin cambios.
      await http.put(u('/api/admin/repuestos/$id'), headers: adminHeaders, body: jsonEncode({'stock': 1}));
      final malo = await estado(folio, 'confirmada');
      expect(malo['status'], 409);
      expect(await stockDe(id), 1);

      expect((await estado('RES-NO-EXISTE', 'confirmada'))['status'], 404);
    });
  });

  group('Panel de productos y sesión', () {
    test('refresh renueva el token y con token falso da 401', () async {
      final ok = await http.post(u('/api/auth/refresh'), headers: adminHeaders);
      expect(ok.statusCode, 200);
      expect(jsonDecode(ok.body)['token'].toString().split('.').length, 3);
      final mal = await http.post(u('/api/auth/refresh'), headers: conToken('x.y.z'));
      expect(mal.statusCode, 401);
    });

    test('/api/estado informa la última sincronización', () async {
      final r = jsonDecode((await http.get(u('/api/estado'))).body);
      expect(r['totalProductos'], isA<int>());
      expect(r['haceSegundos'], anyOf(isNull, isA<int>()));
    });

    test('la API no se cachea', () async {
      final r = await http.get(u('/api/estado'));
      expect(r.headers['cache-control'], contains('no-store'));
    });

    test('listado admin paginado con filtros', () async {
      final r = await http.get(u('/api/admin/repuestos?limite=5&pagina=2&stock=agotado'),
          headers: adminHeaders);
      expect(r.statusCode, 200);
      final d = jsonDecode(r.body);
      expect((d['items'] as List).length, lessThanOrEqualTo(5));
      expect(d['total'], isA<int>());
      expect((d['items'] as List).every((p) => p['stock'] == 0), isTrue);
    });

    test('crear, editar, ocultar y eliminar un producto', () async {
      const sku = 'TEST-PANEL-001';
      final c = await http.post(u('/api/admin/repuestos'),
          headers: adminHeaders,
          body: jsonEncode({'nombre': 'Producto panel', 'sku': sku, 'stock': 4, 'precio': 1000}));
      expect(c.statusCode, 201);
      final id = jsonDecode(c.body)['id'];

      final e = await http.put(u('/api/admin/repuestos/$id'),
          headers: adminHeaders,
          body: jsonEncode({'nombre': 'Producto editado', 'precio': 2500, 'stock': 9, 'marca': 'Chery'}));
      expect(e.statusCode, 200);
      final neg = await http.put(u('/api/admin/repuestos/$id'),
          headers: adminHeaders, body: jsonEncode({'stock': -1}));
      expect(neg.statusCode, 400);

      final h = await http.delete(u('/api/admin/repuestos/$id'), headers: adminHeaders);
      expect(jsonDecode(h.body)['accion'], 'oculto');
      final publico = await http.get(u('/api/repuestos?q=$sku'));
      expect(publico.body, isNot(contains(sku)));

      final d = await http.delete(u('/api/admin/repuestos/$id?definitivo=1'),
          headers: adminHeaders);
      expect(jsonDecode(d.body)['accion'], 'eliminado');
    });

    test('guardado masivo rechaza demasiados cambios', () async {
      final r = await http.put(u('/api/admin/repuestos'),
          headers: adminHeaders,
          body: jsonEncode({'cambios': List.generate(501, (i) => {'id': i + 1})}));
      expect(r.statusCode, 400);
    });

    test('una imagen falsa (firma inválida) se rechaza', () async {
      final r = await http.post(u('/api/admin/repuestos/2/imagen'),
          headers: {...adminHeaders, 'Content-Type': 'image/png'}, body: 'no soy un png');
      expect(r.statusCode, 400);
    });

    test('contraseña débil y rol inexistente al crear usuario → 400', () async {
      final debil = await http.post(u('/api/admin/usuarios'),
          headers: adminHeaders,
          body: jsonEncode({'usuario': 'prueba.debil', 'password': '1234', 'rolId': 2}));
      expect(debil.statusCode, 400);
      final rol = await http.post(u('/api/admin/usuarios'),
          headers: adminHeaders,
          body: jsonEncode({'usuario': 'prueba.rol', 'password': 'Clave1234', 'rolId': 9999}));
      expect(rol.statusCode, 400);
    });

    test('permisos de rol inexistentes se rechazan', () async {
      final r = await http.post(u('/api/admin/roles'),
          headers: adminHeaders,
          body: jsonEncode({'nombre': 'Rol falso', 'permisos': ['dashboard', 'volar']}));
      expect(r.statusCode, 400);
    });

    test('reservar un producto agotado → 400', () async {
      final ag = jsonDecode((await http.get(u('/api/admin/repuestos?limite=1&stock=agotado&estado=PUBLICADO'),
              headers: adminHeaders))
          .body);
      final items = ag['items'] as List;
      if (items.isEmpty) return;
      final r = await http.post(u('/api/reservas'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'cliente_nombre': 'Prueba',
            'cliente_telefono': '+56911111111',
            'cliente_email': 'prueba@correo.cl',
            'items': [
              {'producto_id': items.first['id'], 'cantidad': 1}
            ],
          }));
      expect(r.statusCode, 400);
      expect(r.body, contains('agotado'));
    });
  });
}
