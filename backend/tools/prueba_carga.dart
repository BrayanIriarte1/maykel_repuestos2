// Prueba de carga simple (RNF02): N usuarios simultáneos navegando el catálogo.
//
// Uso (con el servidor corriendo, desde backend/):
//   dart run tools\prueba_carga.dart [usuarios=50] [peticiones_por_usuario=20] [url=http://localhost:8080]
//
// Criterio de aceptación: 0 errores y p95 < 2000 ms.
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final usuarios = args.isNotEmpty ? int.parse(args[0]) : 50;
  final porUsuario = args.length > 1 ? int.parse(args[1]) : 20;
  final base = args.length > 2 ? args[2] : 'http://localhost:8080';

  final rutas = <String>[
    '/api/repuestos?limite=24&pagina=1',
    '/api/repuestos?limite=24&pagina=7',
    '/api/repuestos?limite=24&q=filtro',
    '/api/repuestos?limite=24&q=chery',
    '/api/catalogo/filtros',
    '/api/contenido',
    '/',
  ];

  final tiempos = <int>[];
  var errores = 0;
  final rnd = Random(1);
  final sw = Stopwatch()..start();

  await Future.wait(List.generate(usuarios, (_) async {
    final cliente = http.Client();
    for (var i = 0; i < porUsuario; i++) {
      final t = Stopwatch()..start();
      try {
        final r = await cliente.get(Uri.parse(base + rutas[rnd.nextInt(rutas.length)]));
        if (r.statusCode >= 400) errores++;
      } catch (_) {
        errores++;
      }
      tiempos.add(t.elapsedMilliseconds);
      await Future.delayed(Duration(milliseconds: 100 + rnd.nextInt(400)));
    }
    cliente.close();
  }));

  tiempos.sort();
  int p(double q) => tiempos[(tiempos.length * q).floor().clamp(0, tiempos.length - 1)];
  final total = tiempos.length;
  stdout.writeln('Usuarios simultáneos : $usuarios');
  stdout.writeln('Peticiones           : $total en ${sw.elapsed.inSeconds} s '
      '(${(total / max(1, sw.elapsed.inSeconds)).toStringAsFixed(1)} req/s)');
  stdout.writeln('Errores              : $errores');
  stdout.writeln('Tiempo medio / p95 / máx: '
      '${tiempos.reduce((a, b) => a + b) ~/ total} / ${p(0.95)} / ${tiempos.last} ms');
  final ok = errores == 0 && p(0.95) < 2000;
  stdout.writeln(ok ? 'RESULTADO: CUMPLE RNF02 ✅' : 'RESULTADO: NO CUMPLE ❌');
  exit(ok ? 0 : 1);
}
