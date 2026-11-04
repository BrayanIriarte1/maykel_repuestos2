// Agente local de sincronización de inventario (RF05, RNF05).
// Lee un CSV exportado desde el POS o Excel y lo envía a la plataforma con
// una llamada HTTPS SALIENTE; la sucursal no necesita puertos abiertos.
//
// CSV (UTF-8, separador "," o ";", con encabezado). Columnas aceptadas:
//   codigo_interno | codigo | sku        (obligatoria)
//   nombre | descripcion                 (opcional)
//   stock | saldo | cantidad             (obligatoria)
//
// Uso (desde backend/):
//   dart run tools/sync_agent.dart --archivo C:\inventario\stock.csv --url https://tu-dominio.cl --token TU_TOKEN [--cada 30] [--simular]
// También acepta las variables SYNC_URL, SYNC_API_TOKEN y SYNC_ARCHIVO.
//   --cada N   repite cada N minutos (por defecto una sola vez)
//   --simular  solo valida el archivo, no envía nada
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _tamLote = 200;

List<String> _partirLinea(String linea, String sep) {
  final out = <String>[];
  final sb = StringBuffer();
  var comillas = false;
  for (var i = 0; i < linea.length; i++) {
    final c = linea[i];
    if (c == '"') {
      if (comillas && i + 1 < linea.length && linea[i + 1] == '"') {
        sb.write('"');
        i++;
      } else {
        comillas = !comillas;
      }
    } else if (c == sep && !comillas) {
      out.add(sb.toString().trim());
      sb.clear();
    } else {
      sb.write(c);
    }
  }
  out.add(sb.toString().trim());
  return out;
}

class ResultadoLectura {
  final List<Map<String, dynamic>> productos;
  final List<String> errores;
  ResultadoLectura(this.productos, this.errores);
}

ResultadoLectura leerCsv(String contenido) {
  final lineas = contenido
      .replaceAll('\uFEFF', '')
      .split(RegExp(r'\r?\n'))
      .where((l) => l.trim().isNotEmpty)
      .toList();
  final errores = <String>[];
  if (lineas.isEmpty) return ResultadoLectura([], ['El archivo está vacío']);

  final sep = lineas.first.split(';').length > lineas.first.split(',').length ? ';' : ',';
  final cab = _partirLinea(lineas.first, sep).map((e) => e.toLowerCase()).toList();
  int idx(List<String> nombres) => cab.indexWhere(nombres.contains);
  final iSku = idx(['codigo_interno', 'codigo', 'código', 'sku']);
  final iNombre = idx(['nombre', 'descripcion', 'descripción']);
  final iStock = idx(['stock', 'saldo', 'cantidad']);
  if (iSku < 0 || iStock < 0) {
    return ResultadoLectura([],
        ['Faltan columnas obligatorias (codigo_interno y stock). Encabezado leído: ${cab.join(sep)}']);
  }

  final vistos = <String>{};
  final productos = <Map<String, dynamic>>[];
  for (var n = 1; n < lineas.length; n++) {
    final c = _partirLinea(lineas[n], sep);
    if (c.length <= iSku || c.length <= iStock) {
      errores.add('Línea ${n + 1}: columnas incompletas');
      continue;
    }
    final sku = c[iSku];
    final stock = int.tryParse(c[iStock].replaceAll('.', '').split(',').first);
    if (sku.isEmpty) {
      errores.add('Línea ${n + 1}: código vacío');
      continue;
    }
    if (stock == null || stock < 0) {
      errores.add('Línea ${n + 1} ($sku): stock inválido "${c[iStock]}"');
      continue;
    }
    if (!vistos.add(sku)) {
      errores.add('Línea ${n + 1} ($sku): código repetido, se ignora');
      continue;
    }
    productos.add({
      'codigo_interno': sku,
      if (iNombre >= 0 && c.length > iNombre && c[iNombre].isNotEmpty) 'nombre': c[iNombre],
      'stock': stock,
    });
  }
  return ResultadoLectura(productos, errores);
}

String? _arg(List<String> args, String nombre) {
  final i = args.indexOf('--$nombre');
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

Future<bool> sincronizarUnaVez(
    String archivo, String url, String token, bool simular) async {
  final marca = DateTime.now().toIso8601String();
  final f = File(archivo);
  if (!f.existsSync()) {
    stderr.writeln('[$marca] No existe el archivo: $archivo');
    return false;
  }
  final lectura = leerCsv(utf8.decode(f.readAsBytesSync(), allowMalformed: true));
  for (final e in lectura.errores) {
    stderr.writeln('[$marca] Aviso: $e');
  }
  if (lectura.productos.isEmpty) {
    stderr.writeln('[$marca] No hay productos válidos para enviar.');
    return false;
  }
  print('[$marca] ${lectura.productos.length} productos válidos en $archivo');
  if (simular) {
    print('Modo simulación: no se envió nada.');
    return true;
  }

  var ok = true;
  for (var i = 0; i < lectura.productos.length; i += _tamLote) {
    final fin = i + _tamLote > lectura.productos.length
        ? lectura.productos.length
        : i + _tamLote;
    final lote = lectura.productos.sublist(i, fin);
    var enviado = false;
    for (var intento = 1; intento <= 3 && !enviado; intento++) {
      try {
        final r = await http
            .post(
              Uri.parse('$url/api/v1/sync/inventory'),
              headers: {
                'Authorization': 'Bearer ' + token,
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'productos': lote}),
            )
            .timeout(const Duration(seconds: 30));
        if (r.statusCode == 200) {
          print('  Lote ${i ~/ _tamLote + 1}: ${r.body}');
          enviado = true;
        } else if (r.statusCode == 401 || r.statusCode == 503) {
          stderr.writeln('  Servidor rechazó el envío (${r.statusCode}): ${r.body}');
          return false;
        } else {
          stderr.writeln('  Intento $intento falló (${r.statusCode})');
        }
      } catch (e) {
        stderr.writeln('  Intento $intento sin conexión: $e');
      }
      if (!enviado) await Future<void>.delayed(Duration(seconds: 2 * intento));
    }
    if (!enviado) ok = false;
  }
  return ok;
}

Future<void> main(List<String> args) async {
  final archivo = _arg(args, 'archivo') ?? Platform.environment['SYNC_ARCHIVO'];
  final url = (_arg(args, 'url') ?? Platform.environment['SYNC_URL'] ?? 'http://localhost:8080')
      .replaceAll(RegExp(r'/+$'), '');
  final token = _arg(args, 'token') ?? Platform.environment['SYNC_API_TOKEN'];
  final cada = int.tryParse(_arg(args, 'cada') ?? '');
  final simular = args.contains('--simular');

  if (archivo == null || (token == null && !simular)) {
    stderr.writeln(
        'Uso: dart run tools/sync_agent.dart --archivo <csv> --url <https://...> --token <token> [--cada 30] [--simular]');
    exit(64);
  }

  if (cada == null) {
    exit(await sincronizarUnaVez(archivo, url, token ?? '', simular) ? 0 : 1);
  }
  print('Agente activo: sincroniza cada $cada min. Ctrl+C para detener.');
  while (true) {
    await sincronizarUnaVez(archivo, url, token ?? '', simular);
    await Future<void>.delayed(Duration(minutes: cada));
  }
}
