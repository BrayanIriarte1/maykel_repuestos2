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
  return 'maykel2_sync_token_secreto_2026';
}

final adminHeaders = {
  'Authorization': 'Basic ${base64Encode(utf8.encode('$adminUser:$adminPass'))}',
  'Content-Type': 'application/json',
};

Uri u(String path) => Uri.parse('$base$path');

void main() {
  group('Públicas', () {
    test('health responde 200', () async {
      final r = await http.get(u('/api/health'));
      expect(r.statusCode, 200);
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

    test('credenciales erróneas → 401', () async {
      final r = await http.get(u('/api/admin/dashboard'), headers: {
        'Authorization': 'Basic ${base64Encode(utf8.encode('admin:incorrecta'))}'
      });
      expect(r.statusCode, 401);
    });

    test('admin válido accede al dashboard', () async {
      final r = await http.get(u('/api/admin/dashboard'), headers: adminHeaders);
      expect(r.statusCode, 200);
    });

    test('sync con token inválido → 401', () async {
      final r = await http.post(u('/api/v1/sync/inventory'),
          headers: {
            'Authorization': 'Bearer token-falso',
            'Content-Type': 'application/json'
          },
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
            headers: {
              'Authorization': 'Bearer $syncToken',
              'Content-Type': 'application/json'
            },
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
