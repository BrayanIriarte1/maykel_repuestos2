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
          headers: {...adminHeaders, 'Content-Type': 'image/png'}, body: [1, 2, 3]);
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

      final lista =
          await http.get(u('/api/admin/repuestos'), headers: adminHeaders);
      expect(lista.statusCode, 200);
      expect(lista.body, contains(sku));
    });
  });
}
