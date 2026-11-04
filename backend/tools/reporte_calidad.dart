// Genera un CSV para el cliente con los productos que necesitan corrección
// en su sistema: sin precio, con nombre genérico/"0" o sin marca.
//
// Uso (desde backend/):  dart run tools\reporte_calidad.dart
// Salida: backend\reportes\calidad_<fecha>.csv  (ábrelo con Excel)
import 'dart:io';

import '../lib/db.dart';

String _csv(Object? v) {
  final s = (v ?? '').toString().replaceAll('"', '""');
  return '"$s"';
}

Future<void> main() async {
  final db = DatabaseService();
  await db.init();
  final rows = await db.conn.execute(r'''
    SELECT codigo_interno, nombre, categoria, marca, precio, stock, problemas FROM (
      SELECT p.codigo_interno, p.nombre, COALESCE(c.nombre, '') AS categoria,
             COALESCE(p.marca_referencia, '') AS marca,
             p.precio_referencia AS precio, p.stock_actual AS stock,
             concat_ws(' | ',
               CASE WHEN p.precio_referencia <= 0 THEN 'Sin precio' END,
               CASE WHEN p.nombre ~ '^ *0? *$'
                      OR right(p.nombre, length(p.codigo_interno) + 3) = ' - ' || p.codigo_interno
                    THEN 'Nombre genérico o vacío' END,
               CASE WHEN COALESCE(p.marca_referencia, '') IN ('', 'General') THEN 'Sin marca' END
             ) AS problemas
      FROM productos p
      LEFT JOIN categorias c ON c.id = p.categoria_id
      WHERE p.codigo_interno NOT LIKE 'MR-%'
    ) t
    WHERE problemas <> ''
    ORDER BY problemas, codigo_interno
  ''');
  Directory('reportes').createSync();
  final fecha = DateTime.now().toIso8601String().substring(0, 10);
  final f = File('reportes/calidad_$fecha.csv');
  final sb = StringBuffer('\uFEFFCodigo;Nombre;Categoria;Marca;Precio;Stock;Problemas\n');
  for (final r in rows) {
    sb.writeln(List.generate(7, (i) => _csv(r[i])).join(';'));
  }
  f.writeAsStringSync(sb.toString());
  stdout.writeln('${rows.length} productos con observaciones -> ${f.path}');
  await db.conn.close();
  exit(0);
}
