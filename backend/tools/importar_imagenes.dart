// Importa fotos de productos en lote. El nombre de cada archivo debe ser el SKU
// (código del producto), por ejemplo `1011121.jpg`.
//
// Uso (desde backend/):
//   dart run tools\importar_imagenes.dart C:\fotos
//   dart run tools\importar_imagenes.dart C:\fotos --simular
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';

import '../lib/db.dart';

const _extensiones = {'.jpg': 'jpg', '.jpeg': 'jpg', '.png': 'png', '.webp': 'webp'};

Future<void> main(List<String> args) async {
  final simular = args.contains('--simular');
  final rutas = args.where((a) => !a.startsWith('--')).toList();
  if (rutas.isEmpty || !Directory(rutas.first).existsSync()) {
    stderr.writeln('Uso: dart run tools\\importar_imagenes.dart <carpeta> [--simular]');
    exit(64);
  }

  final db = DatabaseService();
  await db.init();
  final destino = Directory(p.join('uploads', 'productos'));
  if (!simular) destino.createSync(recursive: true);

  var ok = 0, sinProducto = 0, ignorados = 0;
  final noEncontrados = <String>[];

  for (final f in Directory(rutas.first).listSync().whereType<File>()) {
    final ext = _extensiones[p.extension(f.path).toLowerCase()];
    if (ext == null) {
      ignorados++;
      continue;
    }
    final sku = p.basenameWithoutExtension(f.path).trim();
    final r = await db.conn.execute(
      Sql.named('SELECT id FROM productos WHERE lower(codigo_interno) = lower(@sku)'),
      parameters: {'sku': sku},
    );
    if (r.isEmpty) {
      sinProducto++;
      noEncontrados.add(p.basename(f.path));
      continue;
    }
    final id = r.first[0] as int;
    if (!simular) {
      for (final e in _extensiones.values.toSet()) {
        final vieja = File(p.join(destino.path, '$id.$e'));
        if (vieja.existsSync()) vieja.deleteSync();
      }
      await f.copy(p.join(destino.path, '$id.$ext'));
      await db.conn.execute(
        Sql.named('UPDATE productos SET imagen_url = @url WHERE id = @id'),
        parameters: {
          'url': '/media/productos/$id.$ext?v=${DateTime.now().millisecondsSinceEpoch}',
          'id': id,
        },
      );
    }
    ok++;
  }

  print('${simular ? "[SIMULACIÓN] " : ""}Imágenes asignadas: $ok');
  print('Sin producto con ese SKU: $sinProducto');
  if (noEncontrados.isNotEmpty) {
    print('  ${noEncontrados.take(20).join(", ")}${noEncontrados.length > 20 ? ", ..." : ""}');
  }
  print('Archivos ignorados (no son imagen): $ignorados');
  await db.conn.close();
}
