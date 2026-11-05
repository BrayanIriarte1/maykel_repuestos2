// Agente local de sincronizaciÃ³n de inventario (RF05, RNF05).
// Lee un CSV exportado desde el POS o Excel y lo envÃ­a a la plataforma con
// una llamada HTTPS SALIENTE; la sucursal no necesita puertos abiertos.
//
// CSV (UTF-8, separador "," o ";", con encabezado). Columnas aceptadas:
//   codigo_interno | codigo | sku        (obligatoria)
//   nombre | descripcion                 (opcional)
//   stock | saldo | cantidad             (obligatoria)
//
// Uso (desde backend/):
//   dart run tools/sync_agent.dart --sistema [--cada 30] [--simular]
//       Lee el inventario del sistema de gestiÃ³n del cliente (SISTEMA_* en .env).
//   dart run tools/sync_agent.dart --archivo C:\inventario\stock.csv --url https://tu-dominio.cl --token TU_TOKEN [--cada 30] [--simular]
// TambiÃ©n acepta las variables SYNC_URL, SYNC_API_TOKEN y SYNC_ARCHIVO (o backend/.env).
//   --cada N   repite cada N minutos (por defecto una sola vez)
//   --simular  solo valida el archivo, no envÃ­a nada
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
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
  if (lineas.isEmpty) return ResultadoLectura([], ['El archivo estÃ¡ vacÃ­o']);

  final sep = lineas.first.split(';').length > lineas.first.split(',').length ? ';' : ',';
  final cab = _partirLinea(lineas.first, sep).map((e) => e.toLowerCase()).toList();
  int idx(List<String> nombres) => cab.indexWhere(nombres.contains);
  final iSku = idx(['codigo_interno', 'codigo', 'cÃ³digo', 'sku']);
  final iNombre = idx(['nombre', 'descripcion', 'descripciÃ³n']);
  final iStock = idx(['stock', 'saldo', 'cantidad']);
  if (iSku < 0 || iStock < 0) {
    return ResultadoLectura([],
        ['Faltan columnas obligatorias (codigo_interno y stock). Encabezado leÃ­do: ${cab.join(sep)}']);
  }

  final vistos = <String>{};
  final productos = <Map<String, dynamic>>[];
  for (var n = 1; n < lineas.length; n++) {
    final c = _partirLinea(lineas[n], sep);
    if (c.length <= iSku || c.length <= iStock) {
      errores.add('LÃ­nea ${n + 1}: columnas incompletas');
      continue;
    }
    final sku = c[iSku];
    final stock = int.tryParse(c[iStock].replaceAll('.', '').split(',').first);
    if (sku.isEmpty) {
      errores.add('LÃ­nea ${n + 1}: cÃ³digo vacÃ­o');
      continue;
    }
    if (stock == null || stock < 0) {
      errores.add('LÃ­nea ${n + 1} ($sku): stock invÃ¡lido "${c[iStock]}"');
      continue;
    }
    if (!vistos.add(sku)) {
      errores.add('LÃ­nea ${n + 1} ($sku): cÃ³digo repetido, se ignora');
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

String _limpiarHtml(String s) => s
    .replaceAll(RegExp(r'<form.*?</form>', dotAll: true), '')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#039;', "'")
    .replaceAll('&nbsp;', ' ')
    .trim();

/// El sistema del cliente a veces guarda el nombre como "0" o vacÃ­o.
String _nombreUtil(String nombre, String categoria, String codigo, int id) {
  if (nombre.isNotEmpty && nombre != '0') return nombre;
  final base = categoria.isEmpty ? 'Repuesto' : categoria;
  final ref = (codigo.isEmpty || codigo == '0') ? '#$id' : codigo;
  return '$base - $ref';
}

/// Lee el inventario desde el sistema de gestiÃ³n del cliente
/// (https://sistema.maykelrepuestos.cl, Laravel): inicia sesiÃ³n y consulta
/// SOLO LECTURA el JSON de cada bodega (`/materiales_data/<bodega>`).
/// Une las bodegas por id de material (suma stock) y genera un SKU estable.
Future<ResultadoLectura> leerSistemaCliente(
    String base, String email, String clave, List<int> bodegas) async {
  final errores = <String>[];
  final cliente = http.Client();
  final cookies = <String, String>{};

  void guardarCookies(http.BaseResponse r) {
    final sc = r.headers['set-cookie'];
    if (sc == null) return;
    for (final m in RegExp(r'(?:^|,\s*)([A-Za-z0-9_\-]+)=([^;,]*)').allMatches(sc)) {
      final k = m.group(1)!;
      if (const {'path', 'expires', 'domain', 'samesite', 'secure', 'httponly', 'max-age'}
          .contains(k.toLowerCase())) {
        continue;
      }
      cookies[k] = m.group(2)!;
    }
  }

  String cookieHeader() => cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  try {
    final login = await cliente.get(Uri.parse('$base/login'));
    guardarCookies(login);
    final token = RegExp(r'name="_token" value="([^"]+)"').firstMatch(login.body)?.group(1);
    if (token == null) {
      return ResultadoLectura([], ['No se encontrÃ³ el formulario de login en $base']);
    }
    final req = http.Request('POST', Uri.parse('$base/login'))
      ..followRedirects = false
      ..headers['Cookie'] = cookieHeader()
      ..bodyFields = {'_token': token, 'email': email, 'password': clave};
    final resp = await http.Response.fromStream(await cliente.send(req));
    guardarCookies(resp);
    final destino = resp.headers['location'] ?? '';
    if (resp.statusCode < 300 || resp.statusCode >= 400 || destino.contains('/login')) {
      return ResultadoLectura([], ['Login rechazado por el sistema del cliente (revisa usuario y clave)']);
    }

    final filas = <int, Map<String, dynamic>>{};
    for (final bodega in bodegas) {
      final r = await cliente.get(
        Uri.parse('$base/materiales_data/$bodega?draw=1&start=0&length=100000&filtro_estado=todos'),
        headers: {
          'Cookie': cookieHeader(),
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 120));
      if (r.statusCode != 200) {
        errores.add('Bodega $bodega: respuesta ${r.statusCode}');
        continue;
      }
      final data = (jsonDecode(r.body)['data'] as List<dynamic>);
      for (final fila in data) {
        final c = (fila as List<dynamic>).map((e) => e.toString()).toList();
        if (c.length < 9) continue;
        final id = int.tryParse(RegExp(r'data-id="(\d+)"').firstMatch(c[0])?.group(1) ?? '');
        if (id == null) continue;
        final stock = int.tryParse(_limpiarHtml(c[2])) ?? 0;
        final habilitado = c[8].contains('checked');
        final previo = filas[id];
        if (previo != null) {
          previo['stock'] = (previo['stock'] as int) + (habilitado ? stock : 0);
          continue;
        }
        filas[id] = {
          'id': id,
          'codigo': _limpiarHtml(c[4]),
          'nombre': _nombreUtil(_limpiarHtml(c[0]), _limpiarHtml(c[1]), _limpiarHtml(c[4]), id),
          'categoria': _limpiarHtml(c[1]),
          'precio': int.tryParse(_limpiarHtml(c[5]).replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
          'stock': habilitado ? (stock < 0 ? 0 : stock) : 0,
        };
      }
    }

    final porCodigo = <String, int>{};
    for (final f in filas.values) {
      porCodigo[f['codigo'] as String] = (porCodigo[f['codigo'] as String] ?? 0) + 1;
    }
    final productos = <Map<String, dynamic>>[];
    for (final f in filas.values) {
      final codigo = f['codigo'] as String;
      final sinCodigo = codigo.isEmpty || codigo == '0';
      final sku = sinCodigo
          ? 'SYS-${f['id']}'
          : (porCodigo[codigo]! > 1 ? '$codigo-${f['id']}' : codigo);
      productos.add({
        'codigo_interno': sku,
        'nombre': f['nombre'],
        'categoria': f['categoria'],
        'precio': f['precio'],
        'stock': f['stock'],
      });
    }
    return ResultadoLectura(productos, errores);
  } catch (e) {
    return ResultadoLectura([], ['No se pudo leer el sistema del cliente: $e']);
  } finally {
    cliente.close();
  }
}

class FuenteSistema {
  final String url, email, clave;
  final List<int> bodegas;
  FuenteSistema(this.url, this.email, this.clave, this.bodegas);
}

Future<bool> sincronizarUnaVez(
    String? archivo, FuenteSistema? sistema, String url, String token, bool simular) async {
  final marca = DateTime.now().toIso8601String();
  late final ResultadoLectura lectura;
  String origen;
  if (sistema != null) {
    origen = sistema.url;
    lectura = await leerSistemaCliente(
        sistema.url, sistema.email, sistema.clave, sistema.bodegas);
  } else {
    origen = archivo!;
    final f = File(archivo);
    if (!f.existsSync()) {
      stderr.writeln('[$marca] No existe el archivo: $archivo');
      return false;
    }
    lectura = leerCsv(utf8.decode(f.readAsBytesSync(), allowMalformed: true));
  }
  for (final e in lectura.errores) {
    stderr.writeln('[$marca] Aviso: $e');
  }
  if (lectura.productos.isEmpty) {
    stderr.writeln('[$marca] No hay productos vÃ¡lidos para enviar.');
    return false;
  }
  print('[$marca] ${lectura.productos.length} productos vÃ¡lidos desde $origen');
  if (simular) {
    print('Modo simulaciÃ³n: no se enviÃ³ nada.');
    return true;
  }

  var ok = true;
  var acumProcesados = 0, acumAgotados = 0, acumNuevos = 0;
  final totalLotes = (lectura.productos.length / _tamLote).ceil();
  for (var i = 0; i < lectura.productos.length; i += _tamLote) {
    final fin = i + _tamLote > lectura.productos.length
        ? lectura.productos.length
        : i + _tamLote;
    final lote = lectura.productos.sublist(i, fin);
    final esUltimo = fin >= lectura.productos.length;
    var enviado = false;
    for (var intento = 1; intento <= 3 && !enviado; intento++) {
      try {
        // Solo el último lote deja registro (con el resumen de todos); si algún
        // lote anterior falló no se registra, para que el panel avise que el
        // inventario puede estar desactualizado.
        final r = await http
            .post(
              Uri.parse('$url/api/v1/sync/inventory'),
              headers: {
                'Authorization': 'Bearer ' + token,
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'productos': lote,
                'publicar': sistema != null,
                'parcial': !(esUltimo && ok),
                if (esUltimo)
                  'resumen': {
                    'procesados': acumProcesados,
                    'agotados': acumAgotados,
                    'nuevos': acumNuevos,
                  },
              }),
            )
            .timeout(const Duration(seconds: 30));
        if (r.statusCode == 200) {
          final n = i ~/ _tamLote + 1;
          try {
            final d = jsonDecode(r.body) as Map<String, dynamic>;
            acumProcesados += (d['total_procesados'] as num?)?.toInt() ?? 0;
            acumAgotados += (d['total_agotados_marcados'] as num?)?.toInt() ?? 0;
            acumNuevos += (d['nuevos_pendientes_catalogacion'] as num?)?.toInt() ?? 0;
          } catch (_) {}
          if (n == 1 || esUltimo) print('  Lote $n/$totalLotes: ${r.body}');
          enviado = true;
        } else if (r.statusCode == 401 || r.statusCode == 503) {
          stderr.writeln('  Servidor rechazÃ³ el envÃ­o (${r.statusCode}): ${r.body}');
          return false;
        } else {
          stderr.writeln('  Intento $intento fallÃ³ (${r.statusCode})');
        }
      } catch (e) {
        stderr.writeln('  Intento $intento sin conexiÃ³n: $e');
      }
      if (!enviado) await Future<void>.delayed(Duration(seconds: 2 * intento));
    }
    if (!enviado) ok = false;
  }
  return ok;
}

Future<void> main(List<String> args) async {
  final envArchivo = File('.env');
  final env = envArchivo.existsSync()
      ? (DotEnv(includePlatformEnvironment: true)..load())
      : DotEnv(includePlatformEnvironment: true);
  String? cfg(String k) {
    final v = env[k];
    return (v == null || v.isEmpty) ? null : v;
  }

  final archivo = _arg(args, 'archivo') ?? cfg('SYNC_ARCHIVO');
  final url = (_arg(args, 'url') ?? cfg('SYNC_URL') ?? 'http://localhost:8080')
      .replaceAll(RegExp(r'/+$'), '');
  final token = _arg(args, 'token') ?? cfg('SYNC_API_TOKEN');
  final cada = int.tryParse(_arg(args, 'cada') ?? '');
  final simular = args.contains('--simular');
  final usarSistema = args.contains('--sistema');

  FuenteSistema? sistema;
  if (usarSistema) {
    final base = (cfg('SISTEMA_URL') ?? 'https://sistema.maykelrepuestos.cl')
        .replaceAll(RegExp(r'/+$'), '');
    final email = cfg('SISTEMA_EMAIL');
    final clave = cfg('SISTEMA_PASS');
    if (email == null || clave == null) {
      stderr.writeln('Faltan SISTEMA_EMAIL y SISTEMA_PASS en backend/.env');
      exit(64);
    }
    final bodegas = (cfg('SISTEMA_BODEGAS') ?? '1')
        .split(',')
        .map((e) => int.tryParse(e.trim()))
        .whereType<int>()
        .toList();
    sistema = FuenteSistema(base, email, clave, bodegas);
  }

  if ((archivo == null && sistema == null) || (token == null && !simular)) {
    stderr.writeln('Uso: dart run tools/sync_agent.dart (--sistema | --archivo <csv>) [--url <https://...>] [--token <token>] [--cada 30] [--simular]');
    exit(64);
  }

  if (cada == null) {
    exit(await sincronizarUnaVez(archivo, sistema, url, token ?? '', simular) ? 0 : 1);
  }
  print('Agente activo: sincroniza cada $cada min. Ctrl+C para detener.');
  while (true) {
    await sincronizarUnaVez(archivo, sistema, url, token ?? '', simular);
    await Future<void>.delayed(Duration(minutes: cada));
  }
}
