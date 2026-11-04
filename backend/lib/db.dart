import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Connection? _connection;
  /// Variables de configuración: primero se leen del archivo `.env` (si
  /// existe) y luego las variables de entorno del sistema operativo, que
  /// tienen prioridad.
  final Map<String, String> env = {};

  Future<void> init() async {
    final archivoEnv = DotEnv(quiet: true);
    if (File('.env').existsSync()) archivoEnv.load(['.env']);
    for (final clave in [
      'PORT', 'DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASS',
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

    try {
      _connection = await Connection.open(
        Endpoint(
          host: host,
          port: port,
          database: database,
          username: username,
          password: password,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      print('✅ Conectado exitosamente a PostgreSQL ($database en $host:$port)');
    } catch (e) {
      print('⚠️ Error al conectar a PostgreSQL: $e');
      rethrow;
    }
  }

  Connection get conn {
    if (_connection == null || !_connection!.isOpen) {
      throw Exception('La conexión a PostgreSQL no está activa.');
    }
    return _connection!;
  }
}