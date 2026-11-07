import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http_pkg;

import 'config.dart';
import 'models.dart';
import 'utils/almacen_sesion.dart';

class ApiException implements Exception {
  final String mensaje;
  ApiException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Cliente HTTP que detecta cuándo el servidor rechaza la sesión (401 en una
/// petición con credenciales) y avisa a la app para volver al inicio.
class _ClienteApi extends http_pkg.BaseClient {
  final http_pkg.Client _interno = http_pkg.Client();

  @override
  Future<http_pkg.StreamedResponse> send(http_pkg.BaseRequest request) async {
    final resp = await _interno.send(request);
    if (resp.statusCode == 401 &&
        request.headers.containsKey('Authorization') &&
        !request.url.path.endsWith('/api/auth/login')) {
      ApiService.instance._sesionExpirada();
    }
    return resp;
  }
}

final http = _ClienteApi();

/// Cliente HTTP para la API del backend. Guarda las credenciales del
/// administrador en memoria únicamente (se pierden al recargar la página,
/// igual que en la versión anterior en JavaScript).
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  String? _authHeader;
  SesionAdmin? _sesion;
  Timer? _renovador;

  /// Se incrementa cuando el servidor rechaza la sesión; la app escucha para
  /// volver al inicio y avisar al usuario.
  final ValueNotifier<int> sesionCerrada = ValueNotifier(0);

  static const _claveToken = 'mr_token';
  static const _claveSesion = 'mr_sesion';

  bool get sesionAdminActiva => _authHeader != null;
  SesionAdmin? get sesion => _sesion;

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$kApiBase$path').replace(queryParameters: query);
  }

  Map<String, String> _headers({bool admin = false, bool json = false}) {
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    if (admin && _authHeader != null) headers['Authorization'] = _authHeader!;
    return headers;
  }

  /// Sube la foto de un producto (bytes crudos). Devuelve la nueva imagen_url.
  Future<String> subirImagenRepuesto(int id, List<int> bytes, String contentType) async {
    final resp = await http.post(
      _uri('/api/admin/repuestos/$id/imagen'),
      headers: {..._headers(admin: true), 'Content-Type': contentType},
      body: bytes,
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw ApiException(_mensajeError(resp) ?? 'No se pudo subir la imagen');
    }
    return (jsonDecode(resp.body) as Map)['imagen_url'] as String;
  }

  String? _mensajeError(http_pkg.Response resp) {
    try {
      final data = jsonDecode(resp.body);
      if (data is Map && data['error'] != null) return data['error'].toString();
    } catch (_) {
      // ignorar, no era JSON
    }
    return null;
  }

  // ---------- Catálogo público ----------

  Future<List<String>> getCategorias() async {
    final resp = await http.get(_uri('/api/categorias'));
    if (resp.statusCode != 200) {
      throw ApiException('No se pudieron cargar las categorías.');
    }
    return List<String>.from(jsonDecode(resp.body) as List);
  }

  Future<List<String>> getMarcas() async {
    final resp = await http.get(_uri('/api/marcas'));
    if (resp.statusCode != 200) {
      throw ApiException('No se pudieron cargar las marcas.');
    }
    return List<String>.from(jsonDecode(resp.body) as List);
  }

  Future<List<Repuesto>> getRepuestos({
    String? buscar,
    String? categoria,
    String? marca,
    bool soloDisponibles = false,
  }) async {
    final query = <String, String>{};
    if (buscar != null && buscar.isNotEmpty) query['buscar'] = buscar;
    if (categoria != null && categoria.isNotEmpty) query['categoria'] = categoria;
    if (marca != null && marca.isNotEmpty) query['marca'] = marca;
    if (soloDisponibles) query['disponible'] = '1';

    final resp = await http.get(_uri('/api/repuestos', query));
    if (resp.statusCode != 200) {
      throw ApiException('No se pudieron cargar los repuestos.');
    }
    final lista = jsonDecode(resp.body) as List;
    return lista
        .map((e) => Repuesto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Catálogo paginado desde el servidor (miles de productos): devuelve una página y el total.
  Future<({List<Repuesto> items, int total})> getRepuestosPagina({
    String? buscar,
    String? categoria,
    String? marca,
    String? modelo,
    bool soloDisponibles = false,
    int pagina = 1,
    int limite = 24,
  }) async {
    final query = <String, String>{'limite': '$limite', 'pagina': '$pagina'};
    if (buscar != null && buscar.isNotEmpty) query['buscar'] = buscar;
    if (categoria != null && categoria.isNotEmpty) query['categoria'] = categoria;
    if (marca != null && marca.isNotEmpty) query['marca'] = marca;
    if (modelo != null && modelo.isNotEmpty) query['modelo'] = modelo;
    if (soloDisponibles) query['disponible'] = '1';

    final resp = await http.get(_uri('/api/repuestos', query));
    if (resp.statusCode != 200) {
      throw ApiException('No se pudieron cargar los repuestos.');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final items = (data['items'] as List)
        .map((e) => Repuesto.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items: items, total: (data['total'] as num).toInt());
  }

  /// Filtro jerárquico Marca -> Modelo y categorías más relevantes, con cantidad de productos.
  Future<({List<(String, int)> marcas, List<(String, int)> modelos, List<(String, int)> categorias})>
      getFiltrosCatalogo({String? marca}) async {
    final resp = await http.get(_uri(
        '/api/catalogo/filtros', marca == null || marca.isEmpty ? null : {'marca': marca}));
    if (resp.statusCode != 200) {
      throw ApiException('No se pudieron cargar los filtros.');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    List<(String, int)> leer(String k) => (data[k] as List? ?? [])
        .map((e) => ((e as Map)['nombre'].toString(), (e['total'] as num).toInt()))
        .toList();
    return (marcas: leer('marcas'), modelos: leer('modelos'), categorias: leer('categorias'));
  }

  /// Listado interno del panel admin (paginado en el servidor): incluye precio de
  /// referencia y productos ocultos o pendientes. El catálogo público nunca muestra precio.
  Future<({List<Repuesto> items, int total})> getRepuestosAdmin({
    String q = '',
    String categoria = '',
    String estado = '',
    String stock = '',
    int pagina = 1,
    int limite = 50,
  }) async {
    final query = <String, String>{'pagina': '$pagina', 'limite': '$limite'};
    if (q.trim().isNotEmpty) query['q'] = q.trim();
    if (categoria.isNotEmpty) query['categoria'] = categoria;
    if (estado.isNotEmpty) query['estado'] = estado;
    if (stock.isNotEmpty) query['stock'] = stock;
    final resp = await http.get(_uri('/api/admin/repuestos', query),
        headers: _headers(admin: true));
    if (resp.statusCode != 200) {
      throw ApiException(_mensajeError(resp) ?? 'No se pudieron cargar los repuestos.');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (
      items: (data['items'] as List)
          .map((e) => Repuesto.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (data['total'] as num).toInt(),
    );
  }

  // ---------- Reservas ----------

  /// Registra el interés por un producto agotado (alimenta la analítica de demanda).
  Future<void> registrarInteresAgotado(Repuesto p) async {
    try {
      await http.post(
        _uri('/api/metricas/agotado'),
        headers: _headers(json: true),
        body: jsonEncode({'producto_id': p.id, 'nombre_producto': p.nombre}),
      );
    } catch (_) {
      // El aviso al cliente no depende de que la métrica llegue.
    }
  }

  Future<Reserva> crearReserva({
    required List<({int id, int cantidad})> items,
    required String nombre,
    required String telefono,
    required String email,
    String nota = '',
  }) async {
    final resp = await http.post(
      _uri('/api/reservas'),
      headers: _headers(json: true),
      body: jsonEncode({
        'items': [
          for (final i in items) {'producto_id': i.id, 'cantidad': i.cantidad}
        ],
        'nombre': nombre,
        'telefono': telefono,
        'email': email,
        'nota': nota,
      }),
    );
    if (resp.statusCode != 201) {
      throw ApiException(
          _mensajeError(resp) ?? 'No se pudo confirmar la reserva.');
    }
    return Reserva.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ---------- Admin: sesión ----------

  Future<bool> loginAdmin(String usuario, String password) async {
    final resp = await http.post(
      _uri('/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'usuario': usuario, 'password': password}),
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      _authHeader = 'Bearer ${data['token']}';
      _guardarSesion(data);
      return true;
    }
    if (resp.statusCode == 429) {
      throw ApiException(_mensajeError(resp) ?? 'Demasiados intentos.');
    }
    return false;
  }

  void _guardarSesion(Map<String, dynamic> data) {
    _authHeader = 'Bearer ${data['token']}';
    _sesion = SesionAdmin.fromJson(data);
    guardarAlmacen(_claveToken, data['token'].toString());
    guardarAlmacen(_claveSesion, jsonEncode({
      'usuario': _sesion!.usuario,
      'permisos': _sesion!.permisos,
      'esSuperAdmin': _sesion!.esSuperAdmin,
      'rolNombre': _sesion!.rolNombre,
    }));
    // Mientras el panel esté abierto se renueva el token cada 30 min.
    _renovador?.cancel();
    _renovador = Timer.periodic(const Duration(minutes: 30), (_) => renovarSesion());
  }

  /// Recupera la sesión guardada (al recargar la página) y la valida con el
  /// servidor. Devuelve true si el administrador sigue con sesión activa.
  Future<bool> restaurarSesion() async {
    final token = leerAlmacen(_claveToken);
    final datos = leerAlmacen(_claveSesion);
    if (token == null || datos == null) return false;
    try {
      _authHeader = 'Bearer $token';
      _sesion = SesionAdmin.fromJson(jsonDecode(datos) as Map<String, dynamic>);
    } catch (_) {
      _borrarSesion();
      return false;
    }
    return renovarSesion();
  }

  /// Pide un token nuevo (y los permisos vigentes). Si el servidor dice que la
  /// sesión ya no vale, la cierra.
  Future<bool> renovarSesion() async {
    if (_authHeader == null) return false;
    try {
      final resp = await http.post(_uri('/api/auth/refresh'), headers: _headers(admin: true));
      if (resp.statusCode == 200) {
        _guardarSesion(jsonDecode(resp.body) as Map<String, dynamic>);
        return true;
      }
      if (resp.statusCode == 401) {
        _borrarSesion();
        return false;
      }
    } catch (_) {
      // Sin conexión con el servidor: se conserva la sesión y se reintenta luego.
    }
    return _authHeader != null;
  }

  void _borrarSesion() {
    _authHeader = null;
    _sesion = null;
    _renovador?.cancel();
    borrarAlmacen(_claveToken);
    borrarAlmacen(_claveSesion);
  }

  void _sesionExpirada() {
    if (_authHeader == null) return;
    _borrarSesion();
    sesionCerrada.value++;
  }

  void logoutAdmin() => _borrarSesion();

  // ---------- Admin: reservas ----------

  Future<List<Reserva>> getReservasAdmin() async {
    final resp =
        await http.get(_uri('/api/admin/reservas'), headers: _headers(admin: true));
    if (resp.statusCode != 200) {
      throw ApiException('No se pudieron cargar las reservas.');
    }
    final lista = jsonDecode(resp.body) as List;
    return lista.map((e) => Reserva.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Cambia el estado de una reserva. Devuelve los ajustes de stock que hizo el
  /// servidor (confirmar/entregar descuenta; rechazar o volver a pendiente repone).
  Future<List<Map<String, dynamic>>> actualizarEstadoReserva(String id, String estado) async {
    final resp = await http.put(
      _uri('/api/admin/reservas/$id'),
      headers: _headers(admin: true, json: true),
      body: jsonEncode({'estado': estado}),
    );
    if (resp.statusCode != 200) {
      throw ApiException(
          _mensajeError(resp) ?? 'No se pudo actualizar la reserva.');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return (data['ajustesStock'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  // ---------- Admin: ventas ----------

  Future<Venta> registrarVenta({
    required int repuestoId,
    required int cantidad,
    String cliente = '',
    String metodoPago = '',
    String nota = '',
  }) async {
    final resp = await http.post(
      _uri('/api/admin/ventas'),
      headers: _headers(admin: true, json: true),
      body: jsonEncode({
        'repuestoId': repuestoId,
        'cantidad': cantidad,
        'cliente': cliente,
        'metodoPago': metodoPago,
        'nota': nota,
      }),
    );
    if (resp.statusCode != 201) {
      throw ApiException(_mensajeError(resp) ?? 'No se pudo registrar la venta.');
    }
    return Venta.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<List<Venta>> getVentasAdmin() async {
    final resp =
        await http.get(_uri('/api/admin/ventas'), headers: _headers(admin: true));
    if (resp.statusCode != 200) {
      throw ApiException('No se pudieron cargar las ventas.');
    }
    final lista = jsonDecode(resp.body) as List;
    return lista.map((e) => Venta.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---------- Admin: stock/precio ----------

  Future<void> guardarCambiosStock(
      List<Map<String, num>> cambios) async {
    final resp = await http.put(
      _uri('/api/admin/repuestos'),
      headers: _headers(admin: true, json: true),
      body: jsonEncode({'cambios': cambios}),
    );
    if (resp.statusCode != 200) {
      throw ApiException(
          _mensajeError(resp) ?? 'No se pudo guardar stock/precio.');
    }
  }

  Future<Repuesto> crearProducto({
    required String nombre,
    String sku = '',
    String categoria = '',
    String marca = '',
    String modelo = '',
    num precio = 0,
    num stock = 0,
  }) async {
    final resp = await http.post(
      _uri('/api/admin/repuestos'),
      headers: _headers(admin: true, json: true),
      body: jsonEncode({
        'nombre': nombre,
        if (sku.isNotEmpty) 'sku': sku,
        'categoria': categoria,
        'marca': marca,
        'modelo': modelo,
        'precio': precio,
        'stock': stock,
      }),
    );
    if (resp.statusCode != 201) {
      throw ApiException(_mensajeError(resp) ?? 'No se pudo crear el producto.');
    }
    return Repuesto.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Oculta el producto del catálogo (reversible). Con [definitivo] lo borra de verdad.
  Future<void> eliminarProducto(int id, {bool definitivo = false}) async {
    final resp = await http.delete(
      _uri('/api/admin/repuestos/$id', definitivo ? {'definitivo': '1'} : null),
      headers: _headers(admin: true),
    );
    if (resp.statusCode != 200) {
      throw ApiException(_mensajeError(resp) ?? 'No se pudo eliminar el producto.');
    }
  }

  /// Edita campos de un producto (nombre, categoria, marca, modelo, precio, stock, estado_catalogo).
  Future<void> editarProducto(int id, Map<String, Object?> cambios) async {
    final resp = await http.put(
      _uri('/api/admin/repuestos/$id'),
      headers: _headers(admin: true, json: true),
      body: jsonEncode(cambios),
    );
    if (resp.statusCode != 200) {
      throw ApiException(_mensajeError(resp) ?? 'No se pudo guardar el producto.');
    }
  }

  /// Estado público del inventario: totales y cuándo fue la última sincronización.
  Future<EstadoInventario> getEstadoInventario() async {
    final resp = await http.get(_uri('/api/estado'));
    if (resp.statusCode != 200) {
      throw ApiException('No se pudo consultar el estado del inventario.');
    }
    return EstadoInventario.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ---------- Admin: dashboard ----------

  Future<DashboardData> getDashboard() async {
    final resp = await http.get(_uri('/api/admin/dashboard'),
        headers: _headers(admin: true));
    if (resp.statusCode != 200) {
      throw ApiException('No se pudo cargar el dashboard.');
    }
    return DashboardData.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ---------- Admin: roles ----------

  Future<List<Rol>> getRoles() async {
    final resp =
        await http.get(_uri('/api/admin/roles'), headers: _headers(admin: true));
    if (resp.statusCode != 200) {
      throw ApiException('No se pudieron cargar los roles.');
    }
    final lista = jsonDecode(resp.body) as List;
    return lista.map((e) => Rol.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Rol> crearRol(String nombre, List<String> permisos) async {
    final resp = await http.post(
      _uri('/api/admin/roles'),
      headers: _headers(admin: true, json: true),
      body: jsonEncode({'nombre': nombre, 'permisos': permisos}),
    );
    if (resp.statusCode != 201) {
      throw ApiException(_mensajeError(resp) ?? 'No se pudo crear el rol.');
    }
    return Rol.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<Rol> actualizarRol(int id, String nombre, List<String> permisos) async {
    final resp = await http.put(
      _uri('/api/admin/roles/$id'),
      headers: _headers(admin: true, json: true),
      body: jsonEncode({'nombre': nombre, 'permisos': permisos}),
    );
    if (resp.statusCode != 200) {
      throw ApiException(_mensajeError(resp) ?? 'No se pudo actualizar el rol.');
    }
    return Rol.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> eliminarRol(int id) async {
    final resp = await http.delete(
      _uri('/api/admin/roles/$id'),
      headers: _headers(admin: true),
    );
    if (resp.statusCode != 200) {
      throw ApiException(_mensajeError(resp) ?? 'No se pudo eliminar el rol.');
    }
  }

  // ---------- Admin: usuarios administradores ----------

  // ---------- Admin: notificaciones y sincronización ----------

  Future<Map<String, dynamic>> getEstadoNotificaciones() async {
    final resp = await http.get(_uri('/api/admin/notificaciones/estado'),
        headers: _headers(admin: true));
    if (resp.statusCode != 200) throw ApiException('No se pudo consultar el estado de las notificaciones.');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// [canal]: 'correo' o 'whatsapp'. Devuelve {ok, error?, ms?}.
  Future<Map<String, dynamic>> probarNotificacion(String canal, {String? destino}) async {
    final resp = await http.post(_uri('/api/admin/notificaciones/probar'),
        headers: _headers(admin: true, json: true),
        body: jsonEncode({'canal': canal, if (destino != null && destino.isNotEmpty) 'destino': destino}));
    if (resp.statusCode != 200) throw ApiException(_mensajeError(resp) ?? 'No se pudo hacer la prueba.');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<({bool enCurso, List<Map<String, dynamic>> items})> getHistorialSync() async {
    final resp = await http.get(_uri('/api/admin/sync/historial'), headers: _headers(admin: true));
    if (resp.statusCode != 200) throw ApiException('No se pudo cargar el historial de sincronización.');
    final d = jsonDecode(resp.body) as Map<String, dynamic>;
    return (
      enCurso: d['enCurso'] == true,
      items: (d['items'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
    );
  }

  Future<String> ejecutarSincronizacion() async {
    final resp = await http.post(_uri('/api/admin/sync/ejecutar'), headers: _headers(admin: true));
    if (resp.statusCode != 202) throw ApiException(_mensajeError(resp) ?? 'No se pudo iniciar la sincronización.');
    return (jsonDecode(resp.body) as Map<String, dynamic>)['mensaje']?.toString() ?? 'Sincronización iniciada.';
  }

  Future<List<UsuarioAdmin>> getUsuariosAdmin() async {
    final resp = await http.get(_uri('/api/admin/usuarios'),
        headers: _headers(admin: true));
    if (resp.statusCode != 200) {
      throw ApiException('No se pudieron cargar los usuarios.');
    }
    final lista = jsonDecode(resp.body) as List;
    return lista.map((e) => UsuarioAdmin.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<UsuarioAdmin> crearUsuarioAdmin({
    required String usuario,
    required String password,
    required int rolId,
    String nombre = '',
  }) async {
    final resp = await http.post(
      _uri('/api/admin/usuarios'),
      headers: _headers(admin: true, json: true),
      body: jsonEncode({
        'usuario': usuario,
        'password': password,
        'rolId': rolId,
        'nombre': nombre,
      }),
    );
    if (resp.statusCode != 201) {
      throw ApiException(_mensajeError(resp) ?? 'No se pudo crear el usuario.');
    }
    return UsuarioAdmin.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> actualizarUsuarioAdmin(
    int id, {
    String? nombre,
    int? rolId,
    String? password,
    bool? activo,
  }) async {
    final body = <String, dynamic>{};
    if (nombre != null) body['nombre'] = nombre;
    if (rolId != null) body['rolId'] = rolId;
    if (password != null && password.isNotEmpty) body['password'] = password;
    if (activo != null) body['activo'] = activo;

    final resp = await http.put(
      _uri('/api/admin/usuarios/$id'),
      headers: _headers(admin: true, json: true),
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw ApiException(_mensajeError(resp) ?? 'No se pudo actualizar el usuario.');
    }
  }

  Future<void> eliminarUsuarioAdmin(int id) async {
    final resp = await http.delete(
      _uri('/api/admin/usuarios/$id'),
      headers: _headers(admin: true),
    );
    if (resp.statusCode != 200) {
      throw ApiException(_mensajeError(resp) ?? 'No se pudo eliminar el usuario.');
    }
  }

  // ---------- Contenido editable del sitio ----------
  // Público (sin login): lo usa el sitio para mostrar historia, servicios,
  // contacto y aviso legal. Guardar sí requiere estar autenticado.

  Future<ContenidoSitio> getContenido() async {
    final resp = await http.get(_uri('/api/contenido'));
    if (resp.statusCode != 200) {
      throw ApiException('No se pudo cargar el contenido del sitio.');
    }
    return ContenidoSitio.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<ContenidoSitio> guardarContenido(ContenidoSitio contenido) async {
    final resp = await http.put(
      _uri('/api/admin/contenido'),
      headers: _headers(admin: true, json: true),
      body: jsonEncode(contenido.toJson()),
    );
    if (resp.statusCode != 200) {
      throw ApiException(_mensajeError(resp) ?? 'No se pudo guardar el contenido.');
    }
    return ContenidoSitio.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }
}
