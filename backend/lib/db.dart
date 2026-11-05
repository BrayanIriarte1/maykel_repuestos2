import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Pool? _pool;

  /// Variables de configuración: primero se leen del archivo `.env` (si
  /// existe) y luego las variables de entorno del sistema operativo, que
  /// tienen prioridad.
  final Map<String, String> env = {};

  Future<void> init() async {
    final archivoEnv = DotEnv(quiet: true);
    if (File('.env').existsSync()) archivoEnv.load(['.env']);
    for (final clave in [
      'PORT', 'DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASS', 'DB_POOL',
      'SYNC_API_TOKEN', 'ADMIN_USERS',
      'WHATSAPP_TOKEN', 'WHATSAPP_PHONE_ID', 'WHATSAPP_DESTINO',
      'WHATSAPP_API_VERSION', 'SMTP_HOST', 'SMTP_PORT', 'SMTP_USER',
      'SMTP_PASS', 'SMTP_SSL', 'SMTP_FROM', 'EMAIL_DESTINO',
      'JWT_SECRET', 'JWT_HORAS', 'CORS_ORIGIN', 'TRUST_PROXY',
    ]) {
      final valor = Platform.environment[clave] ?? archivoEnv[clave];
      if (valor != null && valor.isNotEmpty) env[clave] = valor;
    }

    final host = env['DB_HOST'] ?? 'localhost';
    final port = int.tryParse(env['DB_PORT'] ?? '5432') ?? 5432;
    final database = env['DB_NAME'] ?? 'maykel_repuestos_db';
    final username = env['DB_USER'] ?? 'postgres';
    final password = env['DB_PASS'] ?? 'postgres';
    final conexiones = (int.tryParse(env['DB_POOL'] ?? '') ?? 8).clamp(1, 50);

    try {
      // El pool abre conexiones bajo demanda y reemplaza las que se caigan
      // (reinicio de PostgreSQL, cortes de red) sin reiniciar el servidor.
      _pool = Pool.withEndpoints(
        [
          Endpoint(
            host: host,
            port: port,
            database: database,
            username: username,
            password: password,
          ),
        ],
        settings: PoolSettings(
          maxConnectionCount: conexiones,
          sslMode: SslMode.disable,
        ),
      );
      await _pool!.execute('SELECT 1');
      print('✅ Conectado exitosamente a PostgreSQL ($database en $host:$port, pool de $conexiones)');
    } catch (e) {
      print('⚠️ Error al conectar a PostgreSQL: $e');
      rethrow;
    }
  }

  /// Aplica `database/migraciones.sql` (idempotente: índices, restricciones y
  /// limpiezas que se pueden repetir sin riesgo). Cada sentencia se ejecuta
  /// por separado y un fallo no detiene el arranque.
  Future<void> migrar(String directorioBackend) async {
    final archivo = File(p.join(directorioBackend, 'database', 'migraciones.sql'));
    if (!archivo.existsSync()) return;
    final sentencias = archivo
        .readAsStringSync()
        .split(RegExp(r';\s*(\r?\n|$)'))
        .map((s) => s
            .split('\n')
            .where((l) => !l.trim().startsWith('--'))
            .join('\n')
            .trim())
        .where((s) => s.isNotEmpty);
    var fallos = 0;
    for (final s in sentencias) {
      try {
        await conn.execute(s);
      } catch (e) {
        fallos++;
        print('⚠️ Migración omitida: ${s.split('\n').first} -> $e');
      }
    }
    print(fallos == 0
        ? '✅ Migraciones de base de datos al día'
        : '⚠️ Migraciones aplicadas con $fallos avisos');
  }

  Pool get conn {
    final pool = _pool;
    if (pool == null) {
      throw Exception('La conexión a PostgreSQL no está inicializada.');
    }
    return pool;
  }
}
