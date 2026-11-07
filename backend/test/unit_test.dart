// Pruebas unitarias (no requieren servidor): desde backend/ ejecutar `dart test test/unit_test.dart`.
import 'dart:convert';

import 'package:test/test.dart';

import '../lib/pdf_reserva.dart';
import '../lib/seguridad.dart';
import '../lib/vehiculos.dart';

void main() {
  group('inferirVehiculo', () {
    test('marca y modelo desde el nombre', () {
      final v = inferirVehiculo('CHERY TIGGO 2 1,5 17/23 EMP. TAPA VALVULA')!;
      expect(v.marca, 'Chery');
      expect(v.modelo, 'TIGGO 2');
      expect(inferirVehiculo('MG 3 1,5 19/23 DELANTERO RH Q')!.modelo, '3');
      expect(inferirVehiculo('SENSOR VELOCIDAD MAXUS T60 2,8 17/21')!.marca, 'Maxus');
      expect(inferirVehiculo('GREAT WALL WINGLE 5 2.0')!.marca, 'Great Wall');
    });

    test('sin marca conocida devuelve null', () {
      expect(inferirVehiculo('HU612/2X MANN'), isNull);
      expect(inferirVehiculo('DUO PACK SILICONA + RENOVADOR'), isNull);
    });
  });

  group('bcrypt', () {
    test('hash nuevo es bcrypt y verifica', () {
      final h = hashBcrypt('clave-segura');
      expect(esBcrypt(h), isTrue);
      expect(verificarClave('clave-segura', h), isTrue);
      expect(verificarClave('otra', h), isFalse);
    });

    test('acepta sha256 antiguo y texto plano', () {
      const legacy =
          r'sha256$a1f3c9d2e8b7$ae62e2b693e64c0d8283b3d06e81b0ad5da71f506d3329a30d91d0eec24edf34';
      expect(verificarClave('maykel2026', legacy), isTrue);
      expect(verificarClave('mala', legacy), isFalse);
      expect(verificarClave('plana', 'plana'), isTrue);
    });
  });

  group('JWT', () {
    final jwt = Jwt('secreto-de-prueba-1234567890');

    test('emite y verifica', () {
      final t = jwt.emitir({'usuario': 'admin'});
      expect(jwt.verificar(t)?['usuario'], 'admin');
    });

    test('rechaza firma distinta', () {
      final t = Jwt('otro-secreto-1234567890').emitir({'usuario': 'admin'});
      expect(jwt.verificar(t), isNull);
    });

    test('rechaza payload alterado', () {
      final partes = jwt.emitir({'usuario': 'vendedor'}).split('.');
      final falso = base64Url
          .encode(utf8.encode(jsonEncode({'usuario': 'admin', 'exp': 9999999999})))
          .replaceAll('=', '');
      expect(jwt.verificar('${partes[0]}.$falso.${partes[2]}'), isNull);
    });

    test('rechaza token expirado', () {
      final corto = Jwt('secreto-de-prueba-1234567890', duracion: const Duration(seconds: -5));
      expect(corto.verificar(corto.emitir({'usuario': 'admin'})), isNull);
    });
  });

  group('Bloqueo de intentos', () {
    test('bloquea tras 5 fallos y se reinicia', () {
      final l = LimitadorIntentos();
      for (var i = 0; i < 5; i++) {
        expect(l.bloqueado('a'), isFalse);
        l.registrarFallo('a');
      }
      expect(l.bloqueado('a'), isTrue);
      expect(l.bloqueado('b'), isFalse);
      l.reiniciar('a');
      expect(l.bloqueado('a'), isFalse);
    });
  });

  test('PDF de reserva se genera en memoria con tildes y ñ', () async {
    final bytes = await generarPdfReserva({
      'folio': 'RES-9',
      'fecha': DateTime.now().toIso8601String(),
      'nombre': 'José Núñez',
      'telefono': '+56911111111',
      'email': 'a@b.cl',
      'nota': 'Camión Año 2022',
    }, ['Pastilla de freno señalización (MR-1) x2']);
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
    // La fuente Roboto debe ir incrustada (FontFile2); la Helvetica estándar no trae Unicode.
    expect(String.fromCharCodes(bytes).contains('/FontFile2'), isTrue);
  });
}
