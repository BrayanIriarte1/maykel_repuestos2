// Genera nuevos valores aleatorios para JWT_SECRET y SYNC_API_TOKEN y los
// escribe en backend/.env (los reemplaza si existen, los agrega si no).
//
// Uso (desde backend/):  dart run tools\rotar_secretos.dart
//
// Efectos: las sesiones abiertas se cierran (JWT_SECRET) y el agente de sync
// usa el token nuevo automáticamente porque lee el mismo .env.
// Reinicia el servidor después.
import 'dart:io';
import 'dart:math';

String _aleatorio(int bytes) {
  final r = Random.secure();
  return List.generate(bytes, (_) => r.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

void main() {
  final f = File('.env');
  if (!f.existsSync()) {
    stderr.writeln('No existe backend/.env (ejecuta el comando desde backend/).');
    exit(1);
  }
  final nuevos = {
    'JWT_SECRET': _aleatorio(32),
    'SYNC_API_TOKEN': _aleatorio(24),
  };
  final lineas = f.readAsLinesSync();
  final pendientes = {...nuevos};
  final salida = lineas.map((l) {
    for (final k in nuevos.keys) {
      if (l.startsWith('$k=')) {
        pendientes.remove(k);
        return '$k=${nuevos[k]}';
      }
    }
    return l;
  }).toList();
  pendientes.forEach((k, v) => salida.add('$k=$v'));
  f.writeAsStringSync('${salida.join('\n')}\n');
  stdout.writeln('Listo: ${nuevos.keys.join(' y ')} renovados en .env. Reinicia el servidor.');
}
