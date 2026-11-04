// Seguridad (RNF03): JWT HS256, hash bcrypt y bloqueo por intentos fallidos.
import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:crypto/crypto.dart';

// ---------- Contraseñas ----------

/// Hash bcrypt con factor de costo 10 (RNF03: costo >= 10).
String hashBcrypt(String password) =>
    BCrypt.hashpw(password, BCrypt.gensalt(logRounds: 10));

bool esBcrypt(String guardado) => guardado.startsWith(r'$2');

/// Acepta bcrypt, el formato antiguo `sha256$<sal>$<hash>` y texto plano
/// (para no bloquear bases ya creadas). Quien llama debe migrar a bcrypt
/// cuando [esBcrypt] sea falso y la clave sea correcta.
bool verificarClave(String password, String guardado) {
  if (esBcrypt(guardado)) {
    try {
      return BCrypt.checkpw(password, guardado);
    } catch (_) {
      return false;
    }
  }
  final partes = guardado.split(r'$');
  if (partes.length == 3 && partes[0] == 'sha256') {
    final digest = sha256.convert(utf8.encode('${partes[1]}$password')).toString();
    return digest == partes[2];
  }
  return password == guardado;
}

// ---------- JWT HS256 ----------

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

List<int> _b64dec(String s) =>
    base64Url.decode(s.padRight(s.length + (4 - s.length % 4) % 4, '='));

class Jwt {
  final List<int> _clave;
  final Duration duracion;

  Jwt(String secreto, {this.duracion = const Duration(hours: 8)})
      : _clave = utf8.encode(secreto);

  /// Secreto aleatorio para cuando no se define JWT_SECRET (las sesiones se
  /// pierden al reiniciar el servidor).
  static String secretoAleatorio() {
    final r = Random.secure();
    return _b64(List.generate(32, (_) => r.nextInt(256)));
  }

  String _firmar(String data) => _b64(Hmac(sha256, _clave).convert(utf8.encode(data)).bytes);

  String emitir(Map<String, dynamic> datos) {
    final ahora = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final cabecera = _b64(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
    final cuerpo = _b64(utf8.encode(jsonEncode({
      ...datos,
      'iat': ahora,
      'exp': ahora + duracion.inSeconds,
    })));
    return '$cabecera.$cuerpo.${_firmar('$cabecera.$cuerpo')}';
  }

  /// Devuelve el contenido si la firma es válida y no expiró; si no, null.
  Map<String, dynamic>? verificar(String token) {
    final partes = token.split('.');
    if (partes.length != 3) return null;
    final esperada = _firmar('${partes[0]}.${partes[1]}');
    if (!_igualesConstante(esperada, partes[2])) return null;
    try {
      final cuerpo = jsonDecode(utf8.decode(_b64dec(partes[1]))) as Map<String, dynamic>;
      final exp = (cuerpo['exp'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch ~/ 1000 >= exp) return null;
      return cuerpo;
    } catch (_) {
      return null;
    }
  }
}

bool _igualesConstante(String a, String b) {
  if (a.length != b.length) return false;
  var r = 0;
  for (var i = 0; i < a.length; i++) {
    r |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return r == 0;
}

bool tokensIguales(String a, String b) => _igualesConstante(a, b);

// ---------- Bloqueo por intentos fallidos ----------

class LimitadorIntentos {
  final int maxIntentos;
  final Duration bloqueo;
  final Map<String, List<DateTime>> _fallos = {};

  LimitadorIntentos({this.maxIntentos = 5, this.bloqueo = const Duration(minutes: 15)});

  void _limpiar(String clave) {
    final limite = DateTime.now().subtract(bloqueo);
    _fallos[clave]?.removeWhere((t) => t.isBefore(limite));
  }

  bool bloqueado(String clave) {
    _limpiar(clave);
    return (_fallos[clave]?.length ?? 0) >= maxIntentos;
  }

  void registrarFallo(String clave) =>
      (_fallos[clave] ??= []).add(DateTime.now());

  void reiniciar(String clave) => _fallos.remove(clave);
}
