// Deduce marca y modelo de un repuesto a partir de su nombre
// (ej. "CHERY TIGGO 2 1,5 17/23 LH" -> Chery / TIGGO 2).
// El inventario del cliente no trae esos datos por separado.

class Vehiculo {
  final String marca;
  final String? modelo;
  const Vehiculo(this.marca, this.modelo);
}

final _marcas = <(String, RegExp)>[
  ('Great Wall', RegExp(r'\b(GREAT\s*WALL|GW)\b')),
  ('Chery', RegExp(r'\bCHERY\b')),
  ('Changan', RegExp(r'\bCHANGAN\b')),
  ('JAC', RegExp(r'\bJAC\b')),
  ('Maxus', RegExp(r'\bMAXUS\b')),
  ('MG', RegExp(r'\bMG\b')),
  ('Geely', RegExp(r'\bGEELY\b')),
  ('Brilliance', RegExp(r'\bBRILLIANCE\b')),
  ('Lifan', RegExp(r'\bLIFAN\b')),
  ('BYD', RegExp(r'\bBYD\b')),
  ('BAIC', RegExp(r'\bBAIC\b')),
  ('DFSK', RegExp(r'\bDFSK\b')),
  ('Mahindra', RegExp(r'\bMAHINDRA\b')),
  ('JMC', RegExp(r'\bJMC\b')),
  ('Haval', RegExp(r'\bHAVAL\b')),
  ('Foton', RegExp(r'\bFOTON\b')),
  ('Haima', RegExp(r'\bHAIMA\b')),
  ('Zotye', RegExp(r'\bZOTYE\b')),
  ('Hyundai', RegExp(r'\bHYUNDAI\b')),
  ('FAW', RegExp(r'\bFAW\b')),
  ('Hafei', RegExp(r'\bHAFEI\b')),
  ('Chevrolet', RegExp(r'\bCHEVROLET\b')),
  ('ZNA', RegExp(r'\bZNA\b')),
  ('Dongfeng', RegExp(r'\bDONGFENG\b')),
  ('KYC', RegExp(r'\bKYC\b')),
  ('Nissan', RegExp(r'\bNISSAN\b')),
  ('Toyota', RegExp(r'\bTOYOTA\b')),
  ('SsangYong', RegExp(r'\bSSANG?YONG\b')),
  ('Jetour', RegExp(r'\bJETOUR\b')),
];

final _motorOAnio = RegExp(r'^\d+[.,]\d+|^\d{2}/\d{2,4}$|^\d{4}$');

const _noEsModelo = {
  'LH', 'RH', 'DELANTERO', 'DELANTERA', 'TRASERO', 'TRASERA', 'DEL', 'TRAS',
  'KIT', 'SENSOR', 'FILTRO', 'REJILLA', 'MANILLA', 'EMP', 'EMP.', 'BOMBA',
  'CORREA', 'TAPA', 'CABLE', 'MOTOR', 'ESPEJO', 'FARO', 'FAROL', 'PARACHOQUE',
  'NEBLINERO', 'PASTILLAS', 'DISCO', 'AMORTIGUADOR', 'RADIADOR', 'Y', 'CON',
  'PARA', 'DE', 'EXTERIOR', 'INTERIOR', 'HIDRAULICA', 'MECANICA', 'ELECTRICA',
};

Vehiculo? inferirVehiculo(String nombre) {
  final texto = nombre
      .toUpperCase()
      .replaceAllMapped(RegExp(r'\bMG(\d)'), (m) => 'MG ${m[1]}');

  Match? mejor;
  String? marca;
  for (final (nombreMarca, patron) in _marcas) {
    final m = patron.firstMatch(texto);
    if (m != null && (mejor == null || m.start < mejor.start)) {
      mejor = m;
      marca = nombreMarca;
    }
  }
  if (mejor == null || marca == null) return null;

  final tokens = texto
      .substring(mejor.end)
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  final modelo = <String>[];
  for (final t in tokens) {
    if (modelo.length >= 2) break;
    if (_motorOAnio.hasMatch(t) || _noEsModelo.contains(t)) break;
    if (!RegExp(r'[A-Z0-9]').hasMatch(t)) break;
    modelo.add(t.replaceAll(RegExp(r'^[\-/,()]+|[\-/,()]+$'), ''));
  }
  final m = modelo.where((e) => e.isNotEmpty).join(' ');
  return Vehiculo(marca, m.isEmpty ? null : m);
}
