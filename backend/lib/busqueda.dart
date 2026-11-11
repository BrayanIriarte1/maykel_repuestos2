// Búsqueda de productos por palabras: cada palabra debe aparecer (en cualquier orden y en
// cualquier parte) en nombre, códigos, marca, modelo, descripción o categoría. No distingue
// mayúsculas ni tildes y "0w20" encuentra "0W-20". Usa las columnas generadas
// `productos.busqueda` y `productos.busqueda_compacta` (ver database/migraciones.sql).

const _conTilde = 'áéíóúüñÁÉÍÓÚÜÑ';
const _sinTilde = 'aeiouunaeiouun';

/// Minúsculas y sin tildes, igual que la columna `busqueda` de la base de datos.
String normalizarBusqueda(String s) {
  final b = StringBuffer();
  for (final c in s.toLowerCase().runes) {
    final ch = String.fromCharCode(c);
    final i = _conTilde.indexOf(ch);
    b.write(i >= 0 ? _sinTilde[i] : ch);
  }
  return b.toString();
}

/// Solo letras y números (para comparar "0w-20" con "0w20").
String compactarBusqueda(String s) => normalizarBusqueda(s).replaceAll(RegExp(r'[^a-z0-9]'), '');

String _escaparLike(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

/// Palabras de la búsqueda (máximo 6, sin vacías ni duplicadas).
List<String> palabrasDeBusqueda(String q) {
  final vistas = <String>{};
  final out = <String>[];
  for (final w in normalizarBusqueda(q.trim()).split(RegExp(r'\s+'))) {
    if (w.isEmpty || !vistas.add(w)) continue;
    out.add(w);
    if (out.length == 6) break;
  }
  return out;
}

/// Devuelve las condiciones SQL (una por palabra, se unen con AND) y rellena [params].
/// [alias] es el alias de `productos` y [aliasCategoria] el de `categorias` (opcional).
List<String> condicionesBusqueda(
  String q,
  Map<String, dynamic> params, {
  String alias = 'p',
  String? aliasCategoria = 'c',
}) {
  final condiciones = <String>[];
  final palabras = palabrasDeBusqueda(q);
  for (var i = 0; i < palabras.length; i++) {
    final w = palabras[i];
    final compacta = compactarBusqueda(w);
    final partes = <String>["$alias.busqueda LIKE @bw$i"];
    params['bw$i'] = '%${_escaparLike(w)}%';
    if (compacta.isNotEmpty && compacta != w) {
      partes.add("$alias.busqueda_compacta LIKE @bc$i");
      params['bc$i'] = '%$compacta%';
    }
    if (aliasCategoria != null) {
      partes.add("$aliasCategoria.nombre ILIKE @bw$i");
    }
    condiciones.add('(${partes.join(' OR ')})');
  }
  return condiciones;
}
