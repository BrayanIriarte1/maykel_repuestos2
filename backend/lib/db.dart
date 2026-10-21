import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Connection? _connection;
  late DotEnv env;

  Future<void> init() async {
    env = DotEnv(includePlatformEnvironment: true)..load();

    final host = env['DB_HOST'] ?? Platform.environment['DB_HOST'] ?? 'localhost';
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