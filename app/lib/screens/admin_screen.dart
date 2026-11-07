import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../api_service.dart';
import '../config.dart';
import '../models.dart';
import '../utils/format.dart';
import '../utils/pdf_report.dart';
import '../widgets/admin_inventario.dart';
import '../widgets/admin_reservas.dart';
import '../widgets/efectos.dart';

/// Panel de administración con navegación lateral (sidebar), igual que el
/// diseño de referencia: Inicio, Analítica, Catálogo, Reservas, Stock,
/// Usuarios (roles y accesos) y Configuración.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _Seccion {
  final String clave;
  final String etiqueta;
  final IconData icono;
  final String? permiso; // null = siempre visible
  const _Seccion(this.clave, this.etiqueta, this.icono, this.permiso);
}

const _secciones = [
  _Seccion('inicio', 'Inicio', Icons.home_outlined, null),
  _Seccion('analitica', 'Analítica', Icons.insights_outlined, 'dashboard'),
  _Seccion('catalogo', 'Catálogo', Icons.grid_view_outlined, 'catalogo'),
  _Seccion('reservas', 'Reservas', Icons.event_note_outlined, 'reservas'),
  _Seccion('stock', 'Stock', Icons.inventory_2_outlined, 'stock'),
  _Seccion('usuarios', 'Usuarios', Icons.people_outline, 'usuarios'),
  _Seccion('configuracion', 'Configuración', Icons.settings_outlined, 'configuracion'),
];

class _AdminScreenState extends State<AdminScreen> {
  String _seccionActiva = 'inicio';

  bool _cargando = true;
  String? _error;
  Timer? _auto;
  DateTime? _ultimaActualizacion;

  List<Reserva> _reservas = [];
  List<Venta> _ventas = [];
  DashboardData? _dashboard;
  List<Rol> _roles = [];
  List<UsuarioAdmin> _usuariosAdmin = [];

  // Selector de producto para registrar una venta (búsqueda en el servidor).
  Repuesto? _ventaProducto;
  int _ventaBusquedaMarca = 0;
  int _inventarioVersion = 0;
  final _ventaBusquedaCtrl = TextEditingController();
  Timer? _ventaDebounce;
  final _ventaCantidadCtrl = TextEditingController(text: '1');
  final _ventaClienteCtrl = TextEditingController();
  final _ventaMetodoPagoCtrl = TextEditingController();
  bool _registrandoVenta = false;
  String? _resultadoVenta;
  bool _resultadoVentaEsError = false;
  // Contenido editable del sitio (Configuración): copia local que se edita
  // y solo se manda al backend cuando el usuario presiona "Guardar".
  ContenidoSitio _contenidoEdit = ContenidoSitio.porDefecto();
  final _nombreNegocioCtrl = TextEditingController();
  final _heroTituloCtrl = TextEditingController();
  final _heroSubtituloCtrl = TextEditingController();
  final _heroBotonCatalogoCtrl = TextEditingController();
  final _heroBotonContactoCtrl = TextEditingController();
  final _heroEstadisticaProductosEtiquetaCtrl = TextEditingController();
  final _heroEstadisticaMarcasValorCtrl = TextEditingController();
  final _heroEstadisticaMarcasEtiquetaCtrl = TextEditingController();
  final _heroEstadisticaCategoriasValorCtrl = TextEditingController();
  final _heroEstadisticaCategoriasEtiquetaCtrl = TextEditingController();
  final _historiaKickerCtrl = TextEditingController();
  final _serviciosKickerCtrl = TextEditingController();
  final _serviciosTituloCtrl = TextEditingController();
  final _catalogoKickerCtrl = TextEditingController();
  final _catalogoTituloCtrl = TextEditingController();
  final _marcasTituloCtrl = TextEditingController();
  final _marcasSubtituloCtrl = TextEditingController();
  final _catalogoBusquedaHintCtrl = TextEditingController();
  final _contactoKickerCtrl = TextEditingController();
  final _contactoTituloCtrl = TextEditingController();
  final _footerDerechosCtrl = TextEditingController();
  final _historiaTituloCtrl = TextEditingController();
  final _historiaTextoCtrl = TextEditingController();
  final _contactoWhatsappCtrl = TextEditingController();
  final _contactoEmailCtrl = TextEditingController();
  final _contactoDireccionCtrl = TextEditingController();
  final _contactoMapsUrlCtrl = TextEditingController();
  final _contactoHorarioCtrl = TextEditingController();
  final _avisoLegalActualizadoCtrl = TextEditingController();
  bool _guardandoContenido = false;
  String? _resultadoContenido;
  bool _resultadoContenidoEsError = false;

  SesionAdmin get _sesion =>
      ApiService.instance.sesion ??
      SesionAdmin(usuario: '', permisos: const [], esSuperAdmin: false);

  @override
  void initState() {
    super.initState();
    _cargarTodo();
    // El resumen, las reservas y las ventas se actualizan solos cada minuto
    // (llegan reservas nuevas y la sincronización cambia el stock).
    _auto = Timer.periodic(const Duration(seconds: 30), (_) => _cargarResumen());
  }

  @override
  void dispose() {
    _auto?.cancel();
    _ventaDebounce?.cancel();
    _ventaBusquedaCtrl.dispose();
    _ventaCantidadCtrl.dispose();
    _ventaClienteCtrl.dispose();
    _ventaMetodoPagoCtrl.dispose();
    _nombreNegocioCtrl.dispose();
    _heroTituloCtrl.dispose();
    _heroSubtituloCtrl.dispose();
    _heroBotonCatalogoCtrl.dispose();
    _heroBotonContactoCtrl.dispose();
    _heroEstadisticaProductosEtiquetaCtrl.dispose();
    _heroEstadisticaMarcasValorCtrl.dispose();
    _heroEstadisticaMarcasEtiquetaCtrl.dispose();
    _heroEstadisticaCategoriasValorCtrl.dispose();
    _heroEstadisticaCategoriasEtiquetaCtrl.dispose();
    _historiaKickerCtrl.dispose();
    _serviciosKickerCtrl.dispose();
    _serviciosTituloCtrl.dispose();
    _catalogoKickerCtrl.dispose();
    _catalogoTituloCtrl.dispose();
    _marcasTituloCtrl.dispose();
    _marcasSubtituloCtrl.dispose();
    _catalogoBusquedaHintCtrl.dispose();
    _contactoKickerCtrl.dispose();
    _contactoTituloCtrl.dispose();
    _footerDerechosCtrl.dispose();
    _historiaTituloCtrl.dispose();
    _historiaTextoCtrl.dispose();
    _contactoWhatsappCtrl.dispose();
    _contactoEmailCtrl.dispose();
    _contactoDireccionCtrl.dispose();
    _contactoMapsUrlCtrl.dispose();
    _contactoHorarioCtrl.dispose();
    _avisoLegalActualizadoCtrl.dispose();
    super.dispose();
  }

  /// Pide solo lo que el rol del usuario puede ver, para que un rol limitado
  /// no rompa todo el panel con un 403.
  Future<List<Object?>> _pedirDatos() {
    final s = _sesion;
    return Future.wait<Object?>([
      s.puede('reservas') ? ApiService.instance.getReservasAdmin() : Future.value(<Reserva>[]),
      s.puede('stock') ? ApiService.instance.getVentasAdmin() : Future.value(<Venta>[]),
      s.puede('dashboard') ? ApiService.instance.getDashboard() : Future.value(null),
    ]);
  }

  /// Reservas pendientes (por atender): alimenta insignias, campana y avisos.
  int get _pendientes => _reservas.where((r) => r.estado == 'pendiente').length;
  int _pendientesPrevios = -1;

  /// Refresco silencioso (sin spinner) de reservas, ventas y KPIs.
  Future<void> _cargarResumen() async {
    if (!mounted || _cargando) return;
    try {
      final r = await _pedirDatos();
      if (!mounted) return;
      final nuevas = r[0] as List<Reserva>;
      final antes = _pendientesPrevios;
      setState(() {
        _reservas = nuevas;
        _ventas = r[1] as List<Venta>;
        _dashboard = r[2] as DashboardData?;
        _ultimaActualizacion = DateTime.now();
      });
      final ahora = _pendientes;
      _pendientesPrevios = ahora;
      if (antes >= 0 && ahora > antes && _sesion.puede('reservas')) {
        final ultima = _reservas.firstWhere((x) => x.estado == 'pendiente');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('🔔 Nueva reserva ${ultima.id} de ${ultima.nombre}'),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
              label: 'VER', onPressed: () => setState(() => _seccionActiva = 'reservas')),
        ));
      }
    } catch (_) {
      // Un fallo puntual de red no debe molestar: se reintenta en el siguiente ciclo.
    }
  }

  Future<void> _cargarTodo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resultados = await Future.wait<Object?>([
        _pedirDatos(),
        if (_sesion.puede('usuarios')) ApiService.instance.getRoles() else Future.value(<Rol>[]),
        if (_sesion.puede('usuarios'))
          ApiService.instance.getUsuariosAdmin()
        else
          Future.value(<UsuarioAdmin>[]),
        ApiService.instance.getContenido(),
      ]);

      final datos = resultados[0] as List<Object?>;
      final contenido = resultados[3] as ContenidoSitio;

      setState(() {
        _reservas = datos[0] as List<Reserva>;
        _ventas = datos[1] as List<Venta>;
        _dashboard = datos[2] as DashboardData?;
        _roles = resultados[1] as List<Rol>;
        _usuariosAdmin = resultados[2] as List<UsuarioAdmin>;
        SiteContent.actual = contenido;
        _contenidoEdit = contenido.copiaProfunda();
        _sincronizarControladoresContenido();
        _cargando = false;
        _ultimaActualizacion = DateTime.now();
        _pendientesPrevios = _pendientes;
        // Si la sección activa no está permitida para este usuario, cae a Inicio.
        final seccion = _secciones.firstWhere((s) => s.clave == _seccionActiva);
        if (seccion.permiso != null && !_sesion.puede(seccion.permiso!)) {
          _seccionActiva = 'inicio';
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  void _sincronizarControladoresContenido() {
    _nombreNegocioCtrl.text = _contenidoEdit.nombreNegocio;
    _heroTituloCtrl.text = _contenidoEdit.heroTitulo;
    _heroSubtituloCtrl.text = _contenidoEdit.heroSubtitulo;
    _heroBotonCatalogoCtrl.text = _contenidoEdit.heroBotonCatalogo;
    _heroBotonContactoCtrl.text = _contenidoEdit.heroBotonContacto;
    _heroEstadisticaProductosEtiquetaCtrl.text = _contenidoEdit.heroEstadisticaProductosEtiqueta;
    _heroEstadisticaMarcasValorCtrl.text = _contenidoEdit.heroEstadisticaMarcasValor;
    _heroEstadisticaMarcasEtiquetaCtrl.text = _contenidoEdit.heroEstadisticaMarcasEtiqueta;
    _heroEstadisticaCategoriasValorCtrl.text = _contenidoEdit.heroEstadisticaCategoriasValor;
    _heroEstadisticaCategoriasEtiquetaCtrl.text = _contenidoEdit.heroEstadisticaCategoriasEtiqueta;
    _historiaKickerCtrl.text = _contenidoEdit.historiaKicker;
    _serviciosKickerCtrl.text = _contenidoEdit.serviciosKicker;
    _serviciosTituloCtrl.text = _contenidoEdit.serviciosTitulo;
    _catalogoKickerCtrl.text = _contenidoEdit.catalogoKicker;
    _catalogoTituloCtrl.text = _contenidoEdit.catalogoTitulo;
    _marcasTituloCtrl.text = _contenidoEdit.marcasTitulo;
    _marcasSubtituloCtrl.text = _contenidoEdit.marcasSubtitulo;
    _catalogoBusquedaHintCtrl.text = _contenidoEdit.catalogoBusquedaHint;
    _contactoKickerCtrl.text = _contenidoEdit.contactoKicker;
    _contactoTituloCtrl.text = _contenidoEdit.contactoTitulo;
    _footerDerechosCtrl.text = _contenidoEdit.footerDerechos;
    _historiaTituloCtrl.text = _contenidoEdit.historiaTitulo;
    _historiaTextoCtrl.text = _contenidoEdit.historiaTexto;
    _contactoWhatsappCtrl.text = _contenidoEdit.contactoWhatsapp;
    _contactoEmailCtrl.text = _contenidoEdit.contactoEmail;
    _contactoDireccionCtrl.text = _contenidoEdit.contactoDireccion;
    _contactoMapsUrlCtrl.text = _contenidoEdit.contactoMapsUrl;
    _contactoHorarioCtrl.text = _contenidoEdit.contactoHorario;
    _avisoLegalActualizadoCtrl.text = _contenidoEdit.avisoLegalActualizado;
  }

  Future<void> _guardarContenido() async {
    _contenidoEdit.nombreNegocio = _nombreNegocioCtrl.text.trim();
    _contenidoEdit.heroTitulo = _heroTituloCtrl.text.trim();
    _contenidoEdit.heroSubtitulo = _heroSubtituloCtrl.text.trim();
    _contenidoEdit.heroBotonCatalogo = _heroBotonCatalogoCtrl.text.trim();
    _contenidoEdit.heroBotonContacto = _heroBotonContactoCtrl.text.trim();
    _contenidoEdit.heroEstadisticaProductosEtiqueta =
        _heroEstadisticaProductosEtiquetaCtrl.text.trim();
    _contenidoEdit.heroEstadisticaMarcasValor = _heroEstadisticaMarcasValorCtrl.text.trim();
    _contenidoEdit.heroEstadisticaMarcasEtiqueta =
        _heroEstadisticaMarcasEtiquetaCtrl.text.trim();
    _contenidoEdit.heroEstadisticaCategoriasValor =
        _heroEstadisticaCategoriasValorCtrl.text.trim();
    _contenidoEdit.heroEstadisticaCategoriasEtiqueta =
        _heroEstadisticaCategoriasEtiquetaCtrl.text.trim();
    _contenidoEdit.historiaKicker = _historiaKickerCtrl.text.trim();
    _contenidoEdit.serviciosKicker = _serviciosKickerCtrl.text.trim();
    _contenidoEdit.serviciosTitulo = _serviciosTituloCtrl.text.trim();
    _contenidoEdit.catalogoKicker = _catalogoKickerCtrl.text.trim();
    _contenidoEdit.catalogoTitulo = _catalogoTituloCtrl.text.trim();
    _contenidoEdit.marcasTitulo = _marcasTituloCtrl.text.trim();
    _contenidoEdit.marcasSubtitulo = _marcasSubtituloCtrl.text.trim();
    _contenidoEdit.catalogoBusquedaHint = _catalogoBusquedaHintCtrl.text.trim();
    _contenidoEdit.contactoKicker = _contactoKickerCtrl.text.trim();
    _contenidoEdit.contactoTitulo = _contactoTituloCtrl.text.trim();
    _contenidoEdit.footerDerechos = _footerDerechosCtrl.text.trim();
    _contenidoEdit.historiaTitulo = _historiaTituloCtrl.text.trim();
    _contenidoEdit.historiaTexto = _historiaTextoCtrl.text.trim();
    _contenidoEdit.contactoWhatsapp = _contactoWhatsappCtrl.text.trim();
    _contenidoEdit.contactoEmail = _contactoEmailCtrl.text.trim();
    _contenidoEdit.contactoDireccion = _contactoDireccionCtrl.text.trim();
    _contenidoEdit.contactoMapsUrl = _contactoMapsUrlCtrl.text.trim();
    _contenidoEdit.contactoHorario = _contactoHorarioCtrl.text.trim();
    _contenidoEdit.avisoLegalActualizado = _avisoLegalActualizadoCtrl.text.trim();

    setState(() {
      _guardandoContenido = true;
      _resultadoContenido = null;
    });
    try {
      final guardado = await ApiService.instance.guardarContenido(_contenidoEdit);
      setState(() {
        SiteContent.actual = guardado;
        _contenidoEdit = guardado.copiaProfunda();
        _sincronizarControladoresContenido();
        _resultadoContenido = 'Cambios guardados. El sitio público ya los muestra.';
        _resultadoContenidoEsError = false;
      });
    } catch (e) {
      setState(() {
        _resultadoContenido = 'No se pudo guardar: $e';
        _resultadoContenidoEsError = true;
      });
    } finally {
      if (mounted) setState(() => _guardandoContenido = false);
    }
  }

  void _cerrarSesion() {
    ApiService.instance.logoutAdmin();
    Navigator.of(context).pop();
  }

  String _fmtFecha(String iso) {
    final fecha = DateTime.tryParse(iso)?.toLocal();
    if (fecha == null) return iso;
    final hora = '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
    return '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year} $hora';
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final esAngosto = ancho < 900;

    return Scaffold(
      backgroundColor: AppColors.paper,
      drawer: esAngosto ? Drawer(child: _buildSidebar()) : null,
      appBar: esAngosto
          ? AppBar(
              backgroundColor: AppColors.char,
              foregroundColor: Colors.white,
              title: const Text('Maykel Repuestos — Admin'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('No se pudo cargar el panel: $_error',
                            style: TextStyle(color: AppColors.bad)),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _cargarTodo, child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              : Row(
                  children: [
                    if (!esAngosto) SizedBox(width: 240, child: _buildSidebar()),
                    Expanded(
                      child: Column(
                        children: [
                          if (!esAngosto) _buildTopbar(),
                          Expanded(child: _buildContenido()),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  // ---------------------------------------------------------------
  // Sidebar
  // ---------------------------------------------------------------

  Widget _buildSidebar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A1C), Color(0xFF2B1013)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('assets/images/logo_maykel.jpg', fit: BoxFit.contain),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: _secciones
                  .where((s) => s.permiso == null || _sesion.puede(s.permiso!))
                  .map((s) => _itemSidebar(s))
                  .toList(),
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.red,
                child: Text(
                  _sesion.usuario.isNotEmpty ? _sesion.usuario[0].toUpperCase() : 'A',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ),
              title: Text(_sesion.usuario.isEmpty ? 'Admin' : _sesion.usuario,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
              subtitle: Text(_sesion.esSuperAdmin ? 'Propietario' : (_sesion.rolNombre ?? ''),
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
              trailing: IconButton(
                icon: const Icon(Icons.logout, color: Colors.white54, size: 18),
                onPressed: _cerrarSesion,
                tooltip: 'Cerrar sesión',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemSidebar(_Seccion s) {
    final activo = s.clave == _seccionActiva;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: activo ? AppColors.red : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _seccionActiva = s.clave);
            if (MediaQuery.of(context).size.width < 900) {
              Navigator.of(context).maybePop();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(s.icono, size: 18, color: activo ? Colors.white : Colors.white60),
                const SizedBox(width: 12),
                Text(s.etiqueta,
                    style: TextStyle(
                        color: activo ? Colors.white : Colors.white60,
                        fontSize: 13.5,
                        fontWeight: activo ? FontWeight.w700 : FontWeight.w400)),
                if (s.clave == 'reservas' && _pendientes > 0) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: activo ? Colors.white : AppColors.red,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('$_pendientes',
                        style: TextStyle(
                            color: activo ? AppColors.red : Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Topbar
  // ---------------------------------------------------------------

  Widget _buildTopbar() {
    final seccion = _secciones.firstWhere((s) => s.clave == _seccionActiva);
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black12,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          Text(seccion.etiqueta,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.char)),
          const Spacer(),
          if (_ultimaActualizacion != null)
            Text(
              'Actualizado ${_ultimaActualizacion!.hour.toString().padLeft(2, '0')}:'
              '${_ultimaActualizacion!.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: AppColors.steel, fontSize: 12),
            ),
          if (_dashboard != null) ...[
            const SizedBox(width: 12),
            Tooltip(
              message: 'Última sincronización con el sistema del cliente',
              child: Chip(
                avatar: Icon(Icons.sync,
                    size: 16,
                    color: (_dashboard!.haceSegundos == null || _dashboard!.haceSegundos! > 7200)
                        ? AppColors.warn
                        : AppColors.ok),
                label: Text('Sync ${EstadoInventario.textoHace(_dashboard!.haceSegundos)}',
                    style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.paper2),
              ),
            ),
          ],
          IconButton(
            onPressed: _cargarResumen,
            icon: const Icon(Icons.refresh, color: AppColors.steel),
            tooltip: 'Actualizar datos',
          ),
          const SizedBox(width: 4),
          _campana(),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 15,
            backgroundColor: AppColors.paper2,
            child: Text(
              _sesion.usuario.isNotEmpty ? _sesion.usuario[0].toUpperCase() : 'A',
              style: const TextStyle(color: AppColors.char, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// Campana: reservas pendientes y alertas de inventario, con acceso directo.
  Widget _campana() {
    final pend = _reservas.where((r) => r.estado == 'pendiente').take(5).toList();
    final d = _dashboard;
    final alertas = <(IconData, String, String)>[
      if (d != null && d.sinPrecioCount > 0)
        (Icons.money_off, '${d.sinPrecioCount} productos publicados sin precio', 'stock'),
      if (d != null && (d.haceSegundos == null || d.haceSegundos! > 7200))
        (Icons.sync_problem, 'El inventario no se sincroniza hace más de 2 h', 'stock'),
    ];
    final total = _pendientes + alertas.length;
    return PopupMenuButton<String>(
      tooltip: 'Notificaciones',
      offset: const Offset(0, 44),
      onSelected: (s) => setState(() => _seccionActiva = s),
      itemBuilder: (_) => [
        if (_sesion.puede('reservas'))
          for (final r in pend)
            PopupMenuItem(
              value: 'reservas',
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hourglass_top_rounded, color: AppColors.warn),
                title: Text('${r.id} · ${r.nombre}', overflow: TextOverflow.ellipsis),
                subtitle: Text('${r.producto} · ${tiempoRelativo(r.fecha)}',
                    overflow: TextOverflow.ellipsis),
              ),
            ),
        for (final a in alertas)
          PopupMenuItem(
            value: a.$3,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(a.$1, color: AppColors.warn),
              title: Text(a.$2),
            ),
          ),
        if (total == 0)
          const PopupMenuItem(enabled: false, child: Text('Sin novedades 🎉')),
      ],
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.notifications_none, color: AppColors.steel),
          ),
          if (total > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration:
                    BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(10)),
                child: Text('$total',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900)),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Contenido según sección
  // ---------------------------------------------------------------

  Widget _buildContenido() {
    switch (_seccionActiva) {
      case 'analitica':
        return _buildAnaliticaTab();
      case 'catalogo':
        return _buildCatalogoTab();
      case 'reservas':
        return _buildReservasTab();
      case 'stock':
        return _buildStockTab();
      case 'usuarios':
        return _buildUsuariosTab();
      case 'configuracion':
        return _buildConfiguracionTab();
      case 'inicio':
      default:
        return _buildInicioTab();
    }
  }

  // ---------------------------------------------------------------
  // Inicio
  // ---------------------------------------------------------------

  Widget _buildInicioTab() {
    final d = _dashboard;
    return RefreshIndicator(
      onRefresh: _cargarTodo,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF1A1A1C), Color(0xFF4A0F14)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hola, ${_sesion.usuario.isEmpty ? "administrador" : _sesion.usuario} 👋',
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                      const SizedBox(height: 6),
                      Text(
                        '${_saludoDia()} · ${_sesion.esSuperAdmin ? 'Propietario' : (_sesion.rolNombre ?? 'Equipo')}'
                        '${_pendientes > 0 && _sesion.puede('reservas') ? ' · Tienes $_pendientes reserva${_pendientes == 1 ? '' : 's'} por atender' : ''}',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.dashboard_customize_outlined, color: Colors.white24, size: 56),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (d != null)
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                if (_sesion.puede('reservas'))
                  _kpiCard('$_pendientes', 'Reservas por atender', Icons.hourglass_top_rounded),
                if (_sesion.puede('reservas'))
                  _kpiCard('${d.reservasConfirmadas}',
                      'Por retirar (${d.unidadesRetenidas} u.)', Icons.inventory_outlined),
                _kpiCard('${d.productosPublicados}', 'Productos publicados', Icons.inventory_2_outlined),
                _kpiCard('${d.agotadosCount}', 'Productos agotados', Icons.report_outlined),
                if (_sesion.puede('stock'))
                  _kpiCard('${d.totalVentas}', 'Ventas registradas', Icons.point_of_sale_outlined),
                if (_sesion.puede('stock'))
                  _kpiCard(formatCLP(d.montoVentas), 'Monto vendido', Icons.payments_outlined),
              ],
            ),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (context, c) {
            final dos = c.maxWidth > 900;
            final porAtender = _panelPorAtender();
            final porReponer = _panelPorReponer();
            if (!dos) {
              return Column(children: [
                if (porAtender != null) porAtender,
                if (porAtender != null) const SizedBox(height: 16),
                if (porReponer != null) porReponer,
              ]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (porAtender != null) Expanded(flex: 6, child: porAtender),
                if (porAtender != null && porReponer != null) const SizedBox(width: 16),
                if (porReponer != null) Expanded(flex: 5, child: porReponer),
              ],
            );
          }),
          const SizedBox(height: 28),
          Text('Accesos rápidos',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: _secciones
                .where((s) => s.clave != 'inicio' && (s.permiso == null || _sesion.puede(s.permiso!)))
                .map((s) => _accesoRapido(s))
                .toList(),
          ),
        ],
      ),
    );
  }

  String _saludoDia() {
    final h = DateTime.now().hour;
    final saludo = h < 12 ? 'Buenos días' : (h < 20 ? 'Buenas tardes' : 'Buenas noches');
    const dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    final n = DateTime.now();
    return '$saludo, hoy es ${dias[n.weekday - 1]} ${n.day}/${n.month}';
  }

  Widget _tarjetaPanel({
    required String titulo,
    required IconData icono,
    required Widget child,
    String? accion,
    VoidCallback? onAccion,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.paper2),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icono, size: 20, color: AppColors.red),
            const SizedBox(width: 8),
            Expanded(
                child: Text(titulo,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            if (accion != null) TextButton(onPressed: onAccion, child: Text(accion)),
          ]),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  /// Reservas pendientes con botones para confirmar o rechazar sin salir del Inicio.
  Widget? _panelPorAtender() {
    if (!_sesion.puede('reservas')) return null;
    final pend = _reservas.where((r) => r.estado == 'pendiente').take(5).toList();
    return _tarjetaPanel(
      titulo: 'Reservas por atender',
      icono: Icons.hourglass_top_rounded,
      accion: 'Ver todas',
      onAccion: () => setState(() => _seccionActiva = 'reservas'),
      child: pend.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: Text('¡Todo al día! No hay reservas pendientes. 🎉',
                      style: TextStyle(color: AppColors.steel))),
            )
          : Column(children: [
              for (final r in pend)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${r.id} · ${r.nombre}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                          Text(
                              '${r.producto}${r.items.length > 1 ? '' : ' ×${r.cantidad}'} · ${tiempoRelativo(r.fecha)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.steel, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Rechazar',
                      onPressed: () => _cambiarEstadoReserva(r, 'rechazada'),
                      icon: const Icon(Icons.close, color: AppColors.bad, size: 20),
                    ),
                    FilledButton(
                      onPressed: () => _cambiarEstadoReserva(r, 'confirmada'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.red, visualDensity: VisualDensity.compact),
                      child: const Text('Confirmar'),
                    ),
                  ]),
                ),
            ]),
    );
  }

  /// Productos con stock bajo (los más urgentes) con acceso directo a Stock.
  Widget? _panelPorReponer() {
    final d = _dashboard;
    if (d == null || !_sesion.puede('dashboard')) return null;
    final lista = d.stockBajo.take(6).toList();
    return _tarjetaPanel(
      titulo: 'Por reponer (stock ≤ 3)',
      icono: Icons.warning_amber_rounded,
      accion: _sesion.puede('catalogo') || _sesion.puede('stock') ? 'Ir a Stock' : null,
      onAccion: () => setState(() => _seccionActiva = _sesion.puede('stock') ? 'stock' : 'catalogo'),
      child: lista.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: Text('Sin productos con stock bajo.', style: TextStyle(color: AppColors.steel))),
            )
          : Column(children: [
              for (final p in lista)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Expanded(
                      child: Text(p.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.warn.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('${p.stock} u.',
                          style: const TextStyle(
                              color: AppColors.warn, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${d.stockBajoCount} productos con stock bajo en total · ${d.agotadosCount} agotados',
                    style: const TextStyle(color: AppColors.steel, fontSize: 11.5)),
              ),
            ]),
    );
  }

  Widget _accesoRapido(_Seccion s) {
    return HoverLift(
      onTap: () => setState(() => _seccionActiva = s.clave),
      builder: (context, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 180,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: hover ? AppColors.char : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hover ? AppColors.char : AppColors.paper2),
          boxShadow: const [
            BoxShadow(color: Color(0x10000000), blurRadius: 12, offset: Offset(0, 5)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(s.icono, color: AppColors.red, size: 26),
            const SizedBox(height: 12),
            Text(s.etiqueta,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: hover ? Colors.white : AppColors.char)),
          ],
        ),
      ),
    );
  }

  Widget _kpiCard(String valor, String etiqueta, IconData icono) {
    return Container(
      width: 230,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.paper2),
        boxShadow: const [
          BoxShadow(color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.red, AppColors.redDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icono, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(valor,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.char)),
                Text(etiqueta,
                    style: TextStyle(fontSize: 11.5, color: AppColors.steel), maxLines: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Analítica (dashboard con gráficos)
  // ---------------------------------------------------------------

  List<MapEntry<DateTime, num>> _ventasPorDia() {
    final hoy = DateTime.now();
    final dias = List.generate(
        14, (i) => DateTime(hoy.year, hoy.month, hoy.day).subtract(Duration(days: 13 - i)));
    final totalesPorDia = {for (final d in dias) d: 0.0};
    for (final v in _ventas) {
      final fecha = DateTime.tryParse(v.fecha)?.toLocal();
      if (fecha == null) continue;
      final clave = DateTime(fecha.year, fecha.month, fecha.day);
      if (totalesPorDia.containsKey(clave)) {
        totalesPorDia[clave] = (totalesPorDia[clave] ?? 0) + v.total;
      }
    }
    return totalesPorDia.entries.toList();
  }

  Map<String, num> _montoPorCategoria() {
    final mapa = <String, num>{};
    for (final v in _ventas) {
      final cat = v.categoria.isEmpty ? 'Otros' : v.categoria;
      mapa[cat] = (mapa[cat] ?? 0) + v.total;
    }
    return mapa;
  }

  List<({String nombre, String sku, num cantidad})> _topDemanda() {
    final mapa = <String, ({String nombre, String sku, num cantidad})>{};
    void agregar(String sku, String nombre, num cantidad) {
      final actual = mapa[sku];
      mapa[sku] = (nombre: nombre, sku: sku, cantidad: (actual?.cantidad ?? 0) + cantidad);
    }

    // Las reservas entregadas ya figuran como venta; las rechazadas no cuentan.
    for (final r in _reservas.where((r) => r.estado == 'pendiente' || r.estado == 'confirmada')) {
      if (r.items.isNotEmpty) {
        for (final i in r.items) {
          agregar(i.sku, i.nombre, i.cantidad);
        }
      } else {
        agregar(r.sku, r.producto, r.cantidad);
      }
    }
    for (final v in _ventas) {
      agregar(v.sku, v.producto, v.cantidad);
    }
    final lista = mapa.values.toList()..sort((a, b) => b.cantidad.compareTo(a.cantidad));
    return lista.take(5).toList();
  }

  List<String> _insights() {
    final d = _dashboard;
    if (d == null) return [];
    final insights = <String>[];
    if (d.productosPublicados > 0 && d.agotadosCount > 0) {
      final pctAgotado = (d.agotadosCount / d.productosPublicados * 100).round();
      insights.add('El $pctAgotado% de tu catálogo está agotado (${d.agotadosCount} productos). '
          'Revisa la pestaña Stock para reponerlos.');
    }
    if (d.sinPrecioCount > 0) {
      insights.add('${d.sinPrecioCount} producto(s) publicados no tienen precio: pide los valores al cliente.');
    }
    if (d.sinFotoCount > 0) {
      insights.add('${d.sinFotoCount} producto(s) aún no tienen foto. Súbelas desde Stock o con el importador por SKU.');
    }
    final porCategoria = _montoPorCategoria();
    if (porCategoria.isNotEmpty) {
      final top = porCategoria.entries.reduce((a, b) => a.value > b.value ? a : b);
      insights.add('La categoría con más ventas es "${top.key}" (${formatCLP(top.value)}).');
    }
    if (d.reservasPendientes > 0) {
      insights.add('Tienes ${d.reservasPendientes} reserva(s) pendiente(s) de confirmar.');
    }
    if (d.reservasConfirmadas > 0) {
      insights.add('${d.reservasConfirmadas} reserva(s) confirmada(s) esperan retiro: '
          '${d.unidadesRetenidas} unidad(es) apartadas por ${formatCLP(d.montoRetenido)}. '
          'Al marcarlas como entregadas pasan a ventas.');
    }
    if (d.stockBajoCount > 0) {
      insights.add('${d.stockBajoCount} producto(s) tienen stock bajo (3 unidades o menos).');
    }
    if (insights.isEmpty) {
      insights.add('Aún no hay suficientes datos para generar recomendaciones. '
          'Registra ventas y reservas para ver aquí análisis automáticos.');
    }
    return insights;
  }

  Widget _buildAnaliticaTab() {
    final d = _dashboard;
    if (d == null) return const SizedBox.shrink();

    final serieVentas = _ventasPorDia();
    final porCategoria = _montoPorCategoria();
    final top = _topDemanda();
    final agotadosConCategoria = d.agotados.take(5).toList();

    return RefreshIndicator(
      onRefresh: _cargarTodo,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _kpiCard('${d.totalVentas}', 'Ventas registradas', Icons.point_of_sale_outlined),
              _kpiCard(formatCLP(d.montoVentas), 'Monto vendido (CLP)', Icons.payments_outlined),
              _kpiCard('${d.totalReservas}', 'Reservas totales (${d.reservasPendientes} pend.)',
                  Icons.event_note_outlined),
              _kpiCard('${d.reservasConfirmadas}',
                  'Por retirar (${d.unidadesRetenidas} u. · ${formatCLP(d.montoRetenido)})',
                  Icons.inventory_outlined),
              _kpiCard('${d.stockBajoCount}', 'Stock bajo (≤ 3 u.)', Icons.warning_amber_rounded),
              _kpiCard('${d.agotadosCount}', 'Productos agotados', Icons.report_outlined),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, constraints) {
            final dosColumnas = constraints.maxWidth > 800;
            final graficoLinea = _panel(
              titulo: 'Ventas de los últimos 14 días',
              alto: 280,
              child: serieVentas.every((e) => e.value == 0)
                  ? _sinDatos('Aún no hay ventas registradas en este período.')
                  : LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: true, drawVerticalLine: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 28,
                              interval: (serieVentas.length / 5).ceilToDouble().clamp(1, 14).toDouble(),
                              getTitlesWidget: (value, meta) {
                                final i = value.toInt();
                                if (i < 0 || i >= serieVentas.length) return const SizedBox.shrink();
                                final fecha = serieVentas[i].key;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text('${fecha.day}/${fecha.month}',
                                      style: TextStyle(fontSize: 10, color: AppColors.steel)),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 48,
                              getTitlesWidget: (value, meta) => Text(formatCLP(value),
                                  style: TextStyle(fontSize: 9, color: AppColors.steel)),
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (int i = 0; i < serieVentas.length; i++)
                                FlSpot(i.toDouble(), serieVentas[i].value.toDouble()),
                            ],
                            isCurved: true,
                            preventCurveOverShooting: true,
                            color: AppColors.red,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                                show: true, color: AppColors.red.withValues(alpha: 0.12)),
                          ),
                        ],
                      ),
                    ),
            );

            final graficoDona = _panel(
              titulo: 'Ventas por categoría',
              alto: 280,
              child: porCategoria.isEmpty
                  ? _sinDatos('Aún no hay ventas para mostrar por categoría.')
                  : Row(
                      children: [
                        Expanded(
                          child: PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 42,
                              sections: [
                                for (int i = 0; i < porCategoria.entries.length; i++)
                                  PieChartSectionData(
                                    value: porCategoria.values.elementAt(i).toDouble(),
                                    color: _colorSerie(i),
                                    title: '',
                                    radius: 46,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              for (int i = 0; i < porCategoria.entries.length; i++)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Row(
                                    children: [
                                      Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                              color: _colorSerie(i), shape: BoxShape.circle)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(porCategoria.keys.elementAt(i),
                                            style: const TextStyle(fontSize: 11),
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
            );

            if (dosColumnas) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: graficoLinea),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: graficoDona),
                ],
              );
            }
            return Column(children: [graficoLinea, const SizedBox(height: 16), graficoDona]);
          }),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final dosColumnas = constraints.maxWidth > 800;
            final tablaTop = _panel(
              titulo: 'Top 5 productos con mayor demanda',
              child: _tablaSimple(
                columnas: const ['Producto', 'SKU', 'Cantidad'],
                filas: top.isEmpty
                    ? [const ['Aún no hay datos suficientes.', '', '']]
                    : top.map((t) => [t.nombre, t.sku, '${t.cantidad}']).toList(),
              ),
            );
            final tablaAgotados = _panel(
              titulo: 'Productos sin stock (Top 5)',
              child: _tablaSimple(
                columnas: const ['Producto', 'Categoría'],
                filas: agotadosConCategoria.isEmpty
                    ? [const ['No hay productos agotados. 🎉', '']]
                    : agotadosConCategoria
                        .map((p) => [p.nombre, p.categoria.isEmpty ? 'Otros' : p.categoria])
                        .toList(),
              ),
            );

            if (dosColumnas) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: tablaTop),
                  const SizedBox(width: 16),
                  Expanded(child: tablaAgotados),
                ],
              );
            }
            return Column(children: [tablaTop, const SizedBox(height: 16), tablaAgotados]);
          }),
          const SizedBox(height: 16),
          _panel(
            titulo: 'Recomendaciones',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _insights()
                  .map((texto) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.yellow),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(texto,
                                    style: const TextStyle(fontSize: 13, height: 1.4))),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Color _colorSerie(int i) {
    const colores = [
      AppColors.red,
      AppColors.yellow,
      AppColors.ok,
      Color(0xFF3B7DD8),
      Color(0xFF8E5FD8),
      AppColors.warn,
      AppColors.steel,
    ];
    return colores[i % colores.length];
  }

  Widget _panel({required String titulo, required Widget child, double? alto}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.paper2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 14),
          SizedBox(height: alto, child: child),
        ],
      ),
    );
  }

  Widget _sinDatos(String texto) {
    return Center(
      child: Text(texto, style: TextStyle(color: AppColors.steel, fontSize: 12.5)),
    );
  }

  Widget _tablaSimple({required List<String> columnas, required List<List<String>> filas}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: columnas.map((c) => DataColumn(label: Text(c))).toList(),
        rows: filas
            .map((fila) => DataRow(cells: fila.map((c) => DataCell(Text(c))).toList()))
            .toList(),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Catálogo (vista de solo lectura para el admin)
  // ---------------------------------------------------------------

  Widget _buildCatalogoTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        InventarioAdmin(
          key: const ValueKey('inventario-catalogo'),
          editable: false,
          onCambio: _cargarResumen,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------
  // Ventas (registro rápido, embebido en Stock por simplicidad de nav)
  // ---------------------------------------------------------------

  Widget _formularioVenta() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.paper2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Registrar venta', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              SizedBox(
                width: 320,
                child: Autocomplete<Repuesto>(
                  displayStringForOption: (p) => '${p.nombre} (${p.sku})',
                  optionsBuilder: (v) async {
                    final q = v.text.trim();
                    if (q.length < 2) return const Iterable<Repuesto>.empty();
                    // Espera 300 ms sin escribir antes de consultar al servidor.
                    final marca = ++_ventaBusquedaMarca;
                    await Future<void>.delayed(const Duration(milliseconds: 300));
                    if (marca != _ventaBusquedaMarca) return const Iterable<Repuesto>.empty();
                    try {
                      final r = await ApiService.instance
                          .getRepuestosAdmin(q: q, stock: 'disponible', limite: 8);
                      return r.items;
                    } catch (_) {
                      return const Iterable<Repuesto>.empty();
                    }
                  },
                  onSelected: (p) => setState(() => _ventaProducto = p),
                  optionsViewBuilder: (context, onSelected, opciones) => Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 320),
                        child: ListView(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          children: opciones
                              .map((p) => ListTile(
                                    dense: true,
                                    title: Text(p.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text('${p.sku} · ${p.stock} disp. · ${formatCLP(p.precio)}'),
                                    onTap: () => onSelected(p),
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                  fieldViewBuilder: (context, ctrl, foco, _) => TextField(
                    controller: ctrl,
                    focusNode: foco,
                    onChanged: (_) {
                      if (_ventaProducto != null) setState(() => _ventaProducto = null);
                    },
                    decoration: InputDecoration(
                      labelText: 'Producto (escribe nombre o SKU)',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _ventaProducto == null
                          ? null
                          : const Icon(Icons.check_circle, color: AppColors.ok),
                      helperText: _ventaProducto == null
                          ? null
                          : '${_ventaProducto!.stock} disponibles · ${formatCLP(_ventaProducto!.precio)} c/u',
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _ventaCantidadCtrl,
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                  keyboardType: TextInputType.number,
                ),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _ventaClienteCtrl,
                  decoration: const InputDecoration(labelText: 'Cliente (opcional)'),
                ),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _ventaMetodoPagoCtrl,
                  decoration: const InputDecoration(labelText: 'Método de pago (opcional)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _registrandoVenta ? null : _registrarVenta,
            child: _registrandoVenta
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Registrar venta'),
          ),
          if (_resultadoVenta != null) ...[
            const SizedBox(height: 10),
            Text(_resultadoVenta!,
                style: TextStyle(
                    color: _resultadoVentaEsError ? AppColors.bad : AppColors.ok, fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Future<void> _registrarVenta() async {
    final productoId = _ventaProducto?.id;
    final cantidad = int.tryParse(_ventaCantidadCtrl.text) ?? 0;
    if (productoId == null || cantidad < 1) {
      setState(() {
        _resultadoVenta = 'Busca y selecciona un producto, e indica una cantidad válida.';
        _resultadoVentaEsError = true;
      });
      return;
    }
    setState(() {
      _registrandoVenta = true;
      _resultadoVenta = null;
    });
    try {
      final venta = await ApiService.instance.registrarVenta(
        repuestoId: productoId,
        cantidad: cantidad,
        cliente: _ventaClienteCtrl.text.trim(),
        metodoPago: _ventaMetodoPagoCtrl.text.trim(),
      );
      _ventaCantidadCtrl.text = '1';
      _ventaClienteCtrl.clear();
      _ventaMetodoPagoCtrl.clear();
      setState(() {
        _resultadoVenta =
            'Venta registrada: ${venta.cantidad} × ${venta.producto} (${formatCLP(venta.total)})';
        _resultadoVentaEsError = false;
        _ventaProducto = null;
        _inventarioVersion++; // fuerza a recargar la lista de stock con el descuento
      });
      await _cargarResumen();
    } catch (e) {
      setState(() {
        _resultadoVenta = 'Error: $e';
        _resultadoVentaEsError = true;
      });
    } finally {
      if (mounted) setState(() => _registrandoVenta = false);
    }
  }

  Future<void> _descargarPdfVentas() async {
    final filas = _ventas
        .map((v) => [
              _fmtFecha(v.fecha),
              '${v.producto} (${v.sku})',
              '${v.cantidad}',
              formatCLP(v.total),
              v.cliente.isEmpty ? '—' : v.cliente,
              v.metodoPago.isEmpty ? '—' : v.metodoPago,
            ])
        .toList();
    await generarReportePdf(
      titulo: 'Reporte de Ventas',
      columnas: const ['Fecha', 'Producto', 'Cant.', 'Total', 'Cliente', 'Pago'],
      filas: filas,
    );
  }

  // ---------------------------------------------------------------
  // Reservas
  // ---------------------------------------------------------------

  Widget _buildReservasTab() {
    return ReservasPanel(
      reservas: _reservas,
      puedeEditar: _sesion.puede('reservas'),
      onCambiarEstado: _cambiarEstadoReserva,
      onPdf: _descargarPdfReservas,
      onRefrescar: _cargarResumen,
    );
  }

  /// Cambia el estado de una reserva y refresca todo: confirmar/entregar descuenta stock,
  /// entregar registra una venta y rechazar repone y anula la venta.
  Future<void> _cambiarEstadoReserva(Reserva r, String nuevoEstado) async {
    final etiqueta = kEstadosReserva[nuevoEstado]?.etiqueta.toLowerCase() ?? nuevoEstado;
    try {
      final ajustes = await ApiService.instance.actualizarEstadoReserva(r.id, nuevoEstado);
      setState(() => _inventarioVersion++);
      await _cargarResumen();
      if (!mounted) return;
      final detalle = ajustes.isEmpty
          ? ''
          : ' Stock ${ajustes.first['cantidad'] < 0 ? 'descontado' : 'repuesto'}: '
              '${ajustes.map((a) => '${a['producto']} (${a['cantidad'] > 0 ? '+' : ''}${a['cantidad']} → ${a['stock']})').join(', ')}.';
      final venta = nuevoEstado == 'entregada'
          ? ' Se registró como venta.'
          : (r.estado == 'entregada' ? ' La venta asociada fue anulada.' : '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reserva ${r.id}: $etiqueta.$detalle$venta')),
      );
    } catch (e) {
      await _cargarResumen();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar: $e'), backgroundColor: AppColors.bad),
        );
      }
    }
  }

  Future<void> _descargarPdfReservas() async {
    final filas = _reservas
        .map((r) => [
              _fmtFecha(r.fecha),
              r.nombre,
              '${r.telefono} / ${r.email}',
              '${r.producto} (${r.sku})',
              '${r.cantidad}',
              r.estado,
            ])
        .toList();
    await generarReportePdf(
      titulo: 'Reporte de Reservas',
      columnas: const ['Fecha', 'Cliente', 'Contacto', 'Producto', 'Cant.', 'Estado'],
      filas: filas,
    );
  }

  // ---------------------------------------------------------------
  // Stock (incluye el registro de ventas y la descarga de PDF de ventas)
  // ---------------------------------------------------------------

  Widget _buildStockTab() {
    return RefreshIndicator(
      onRefresh: _cargarTodo,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_sesion.puede('stock')) ...[
            _formularioVenta(),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _descargarPdfVentas,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Ventas en PDF'),
              ),
            ),
            const SizedBox(height: 20),
          ],
          const Text('Precio y stock',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          InventarioAdmin(
            key: ValueKey('inventario-stock-$_inventarioVersion'),
            editable: _sesion.puede('stock'),
            onCambio: _cargarResumen,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Usuarios (roles y cuentas del panel admin)
  // ---------------------------------------------------------------

  Widget _buildUsuariosTab() {
    return RefreshIndicator(
      onRefresh: _cargarTodo,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Crea roles con permisos específicos y luego asigna esos roles a las '
                  'personas de tu equipo que necesiten acceso al panel.',
                  style: TextStyle(color: AppColors.steel, fontSize: 13, height: 1.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Roles', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _mostrarFormRol(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo rol'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _tablaRoles(),
          const SizedBox(height: 30),
          Row(
            children: [
              Text('Usuarios del panel',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _roles.isEmpty ? null : () => _mostrarFormUsuario(),
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Nuevo usuario'),
              ),
            ],
          ),
          if (_roles.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Crea al menos un rol antes de agregar usuarios.',
                  style: TextStyle(color: AppColors.steel, fontSize: 12)),
            ),
          const SizedBox(height: 12),
          _tablaUsuarios(),
        ],
      ),
    );
  }

  String _nombreRol(int rolId) {
    final r = _roles.where((x) => x.id == rolId);
    return r.isEmpty ? 'Rol eliminado' : r.first.nombre;
  }

  Widget _tablaRoles() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.paper2),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          dataRowMinHeight: 48,
          dataRowMaxHeight: 96,
          columns: const [
            DataColumn(label: Text('Rol')),
            DataColumn(label: Text('Permisos')),
            DataColumn(label: Text('')),
          ],
          rows: _roles.isEmpty
              ? [
                  const DataRow(cells: [
                    DataCell(Text('Aún no has creado ningún rol.')),
                    DataCell(Text('')),
                    DataCell(Text('')),
                  ])
                ]
              : _roles
                  .map((r) => DataRow(cells: [
                        DataCell(Text(r.nombre, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(SizedBox(
                          width: 340,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: r.permisos
                                .map((p) => Chip(
                                      label: Text(kNombrePermiso[p] ?? p,
                                          style: const TextStyle(fontSize: 10.5)),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      backgroundColor: AppColors.paper,
                                    ))
                                .toList(),
                          ),
                        )),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _mostrarFormRol(rol: r),
                              tooltip: 'Editar',
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 18, color: AppColors.bad),
                              onPressed: () => _eliminarRol(r),
                              tooltip: 'Eliminar',
                            ),
                          ],
                        )),
                      ]))
                  .toList(),
        ),
      ),
    );
  }

  Widget _tablaUsuarios() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.paper2),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Usuario')),
            DataColumn(label: Text('Nombre')),
            DataColumn(label: Text('Rol')),
            DataColumn(label: Text('Estado')),
            DataColumn(label: Text('')),
          ],
          rows: _usuariosAdmin.isEmpty
              ? [
                  const DataRow(cells: [
                    DataCell(Text('Aún no has creado usuarios adicionales.')),
                    DataCell(Text('')),
                    DataCell(Text('')),
                    DataCell(Text('')),
                    DataCell(Text('')),
                  ])
                ]
              : _usuariosAdmin
                  .map((u) => DataRow(cells: [
                        DataCell(Text(u.usuario)),
                        DataCell(Text(u.nombre.isEmpty ? '—' : u.nombre)),
                        DataCell(Text(_nombreRol(u.rolId))),
                        DataCell(Text(u.activo ? 'Activo' : 'Inactivo',
                            style: TextStyle(color: u.activo ? AppColors.ok : AppColors.steel))),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _mostrarFormUsuario(usuario: u),
                              tooltip: 'Editar',
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 18, color: AppColors.bad),
                              onPressed: () => _eliminarUsuario(u),
                              tooltip: 'Eliminar',
                            ),
                          ],
                        )),
                      ]))
                  .toList(),
        ),
      ),
    );
  }

  Future<void> _mostrarFormRol({Rol? rol}) async {
    final nombreCtrl = TextEditingController(text: rol?.nombre ?? '');
    final permisosSeleccionados = <String>{...(rol?.permisos ?? [])};
    String? error;
    bool guardando = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(rol == null ? 'Nuevo rol' : 'Editar rol',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nombreCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre del rol'),
                    ),
                    const SizedBox(height: 14),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Permisos', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                    ),
                    ...kPermisosDisponibles.map((p) => CheckboxListTile(
                          value: permisosSeleccionados.contains(p),
                          onChanged: (v) => setDialogState(() {
                            if (v == true) {
                              permisosSeleccionados.add(p);
                            } else {
                              permisosSeleccionados.remove(p);
                            }
                          }),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(kNombrePermiso[p] ?? p, style: const TextStyle(fontSize: 13)),
                        )),
                    if (error != null) ...[
                      const SizedBox(height: 6),
                      Text(error!, style: TextStyle(color: AppColors.bad, fontSize: 12)),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: guardando
                                ? null
                                : () async {
                                    if (nombreCtrl.text.trim().isEmpty) {
                                      setDialogState(() => error = 'El nombre es obligatorio.');
                                      return;
                                    }
                                    setDialogState(() {
                                      guardando = true;
                                      error = null;
                                    });
                                    try {
                                      if (rol == null) {
                                        await ApiService.instance.crearRol(
                                            nombreCtrl.text.trim(), permisosSeleccionados.toList());
                                      } else {
                                        await ApiService.instance.actualizarRol(
                                            rol.id, nombreCtrl.text.trim(), permisosSeleccionados.toList());
                                      }
                                      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                                      await _cargarTodo();
                                    } catch (e) {
                                      setDialogState(() {
                                        guardando = false;
                                        error = '$e';
                                      });
                                    }
                                  },
                            child: guardando
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Guardar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _eliminarRol(Rol rol) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar rol'),
        content: Text('¿Eliminar el rol "${rol.nombre}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Eliminar', style: TextStyle(color: AppColors.bad)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await ApiService.instance.eliminarRol(rol.id);
      await _cargarTodo();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _mostrarFormUsuario({UsuarioAdmin? usuario}) async {
    final usuarioCtrl = TextEditingController(text: usuario?.usuario ?? '');
    final nombreCtrl = TextEditingController(text: usuario?.nombre ?? '');
    final passwordCtrl = TextEditingController();
    int? rolSeleccionado = usuario?.rolId ?? (_roles.isNotEmpty ? _roles.first.id : null);
    bool activo = usuario?.activo ?? true;
    String? error;
    bool guardando = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(usuario == null ? 'Nuevo usuario' : 'Editar usuario',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: usuarioCtrl,
                      enabled: usuario == null,
                      decoration: const InputDecoration(labelText: 'Nombre de usuario'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nombreCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre completo (opcional)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                          labelText: usuario == null ? 'Contraseña' : 'Nueva contraseña (opcional)'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: rolSeleccionado,
                      decoration: const InputDecoration(labelText: 'Rol'),
                      items: _roles
                          .map((r) => DropdownMenuItem(value: r.id, child: Text(r.nombre)))
                          .toList(),
                      onChanged: (v) => setDialogState(() => rolSeleccionado = v),
                    ),
                    if (usuario != null) ...[
                      const SizedBox(height: 6),
                      SwitchListTile(
                        value: activo,
                        onChanged: (v) => setDialogState(() => activo = v),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('Usuario activo', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 6),
                      Text(error!, style: TextStyle(color: AppColors.bad, fontSize: 12)),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: guardando
                                ? null
                                : () async {
                                    if (usuarioCtrl.text.trim().isEmpty) {
                                      setDialogState(() => error = 'El usuario es obligatorio.');
                                      return;
                                    }
                                    if (usuario == null && passwordCtrl.text.isEmpty) {
                                      setDialogState(() => error = 'La contraseña es obligatoria.');
                                      return;
                                    }
                                    if (rolSeleccionado == null) {
                                      setDialogState(() => error = 'Debes seleccionar un rol.');
                                      return;
                                    }
                                    setDialogState(() {
                                      guardando = true;
                                      error = null;
                                    });
                                    try {
                                      if (usuario == null) {
                                        await ApiService.instance.crearUsuarioAdmin(
                                          usuario: usuarioCtrl.text.trim(),
                                          password: passwordCtrl.text,
                                          rolId: rolSeleccionado!,
                                          nombre: nombreCtrl.text.trim(),
                                        );
                                      } else {
                                        await ApiService.instance.actualizarUsuarioAdmin(
                                          usuario.id,
                                          nombre: nombreCtrl.text.trim(),
                                          rolId: rolSeleccionado,
                                          password: passwordCtrl.text,
                                          activo: activo,
                                        );
                                      }
                                      if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                                      await _cargarTodo();
                                    } catch (e) {
                                      setDialogState(() {
                                        guardando = false;
                                        error = '$e';
                                      });
                                    }
                                  },
                            child: guardando
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Guardar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _eliminarUsuario(UsuarioAdmin usuario) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text('¿Eliminar el acceso de "${usuario.usuario}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Eliminar', style: TextStyle(color: AppColors.bad)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await ApiService.instance.eliminarUsuarioAdmin(usuario.id);
      await _cargarTodo();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  // ---------------------------------------------------------------
  // Configuración
  // ---------------------------------------------------------------

  Widget _buildConfiguracionTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.paper2,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18, color: AppColors.steel),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Edita aquí el contenido que ven tus clientes en el sitio público: '
                  'historia, servicios, contacto y aviso legal. Los cambios se aplican '
                  'de inmediato al guardar.',
                  style: TextStyle(color: AppColors.steel, fontSize: 12.5, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _guardandoContenido ? null : _guardarContenido,
              icon: _guardandoContenido
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Guardar todos los cambios'),
            ),
            if (_resultadoContenido != null) ...[
              const SizedBox(width: 14),
              Expanded(
                child: Text(_resultadoContenido!,
                    style: TextStyle(
                        color: _resultadoContenidoEsError ? AppColors.bad : AppColors.ok,
                        fontSize: 12.5)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),

        // ---------- Textos generales / Portada (Hero) ----------
        _panel(
          titulo: 'Textos generales y portada (Hero)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nombreNegocioCtrl,
                decoration: const InputDecoration(labelText: 'Nombre del negocio'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _heroTituloCtrl,
                decoration: const InputDecoration(
                    labelText: 'Título principal (portada)',
                    helperText: 'Usa un salto de línea para partirlo en dos líneas'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _heroSubtituloCtrl,
                decoration: const InputDecoration(labelText: 'Subtítulo (portada)'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _heroBotonCatalogoCtrl,
                      decoration: const InputDecoration(labelText: 'Texto botón "Ver catálogo"'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _heroBotonContactoCtrl,
                      decoration: const InputDecoration(labelText: 'Texto botón "Contáctanos"'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Estadísticas de la portada',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: _heroEstadisticaProductosEtiquetaCtrl,
                decoration: const InputDecoration(
                    labelText: 'Etiqueta de productos (el número se calcula solo)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _heroEstadisticaMarcasValorCtrl,
                      decoration: const InputDecoration(labelText: 'Valor (marcas)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _heroEstadisticaMarcasEtiquetaCtrl,
                      decoration: const InputDecoration(labelText: 'Etiqueta (marcas)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _heroEstadisticaCategoriasValorCtrl,
                      decoration: const InputDecoration(labelText: 'Valor (categorías)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _heroEstadisticaCategoriasEtiquetaCtrl,
                      decoration: const InputDecoration(labelText: 'Etiqueta (categorías)'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---------- Encabezados de sección ----------
        _panel(
          titulo: 'Encabezados de sección',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _historiaKickerCtrl,
                decoration: const InputDecoration(labelText: 'Kicker de "Historia"'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _serviciosKickerCtrl,
                      decoration: const InputDecoration(labelText: 'Kicker de "Servicios"'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _serviciosTituloCtrl,
                      decoration: const InputDecoration(labelText: 'Título de "Servicios"'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _catalogoKickerCtrl,
                      decoration: const InputDecoration(labelText: 'Kicker de "Catálogo"'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _catalogoTituloCtrl,
                      decoration: const InputDecoration(labelText: 'Título de "Catálogo"'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _marcasTituloCtrl,
                decoration: const InputDecoration(labelText: 'Título de la sección de marcas'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _marcasSubtituloCtrl,
                decoration: const InputDecoration(labelText: 'Subtítulo de la sección de marcas'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _catalogoBusquedaHintCtrl,
                decoration: const InputDecoration(labelText: 'Texto de ayuda del buscador'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _contactoKickerCtrl,
                      decoration: const InputDecoration(labelText: 'Kicker de "Contacto"'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _contactoTituloCtrl,
                      decoration: const InputDecoration(labelText: 'Título de "Contacto"'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _footerDerechosCtrl,
                decoration: const InputDecoration(
                    labelText: 'Texto de derechos en el pie de página',
                    helperText: 'Se muestra como: © 2026 <este texto>'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---------- Historia ----------
        _panel(
          titulo: 'Historia de la empresa',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _historiaTituloCtrl,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _historiaTextoCtrl,
                decoration: const InputDecoration(labelText: 'Texto'),
                maxLines: 5,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Datos destacados (fichas)',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _mostrarFormFicha(),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Agregar'),
                  ),
                ],
              ),
              ..._contenidoEdit.historiaFichas.asMap().entries.map((entrada) {
                final i = entrada.key;
                final f = entrada.value;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(f.etiqueta, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text(f.valor, style: const TextStyle(fontSize: 12.5)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _mostrarFormFicha(indice: i),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 18, color: AppColors.bad),
                        onPressed: () => setState(() => _contenidoEdit.historiaFichas.removeAt(i)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---------- Servicios ----------
        _panel(
          titulo: 'Servicios',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Lo que se muestra en la sección "Servicios" del sitio.',
                        style: TextStyle(color: AppColors.steel, fontSize: 12.5)),
                  ),
                  TextButton.icon(
                    onPressed: () => _mostrarFormServicio(),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Agregar'),
                  ),
                ],
              ),
              ..._contenidoEdit.servicios.asMap().entries.map((entrada) {
                final i = entrada.key;
                final s = entrada.value;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(s.titulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text(s.descripcion, style: const TextStyle(fontSize: 12.5)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _mostrarFormServicio(indice: i),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 18, color: AppColors.bad),
                        onPressed: () => setState(() => _contenidoEdit.servicios.removeAt(i)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---------- Contacto ----------
        _panel(
          titulo: 'Datos de contacto',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _contactoWhatsappCtrl,
                decoration: const InputDecoration(
                    labelText: 'WhatsApp (solo números, con código de país)',
                    hintText: '56912345678'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contactoEmailCtrl,
                decoration: const InputDecoration(labelText: 'Correo de contacto'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contactoDireccionCtrl,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contactoMapsUrlCtrl,
                decoration: const InputDecoration(labelText: 'Enlace de Google Maps'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contactoHorarioCtrl,
                decoration: const InputDecoration(labelText: 'Horario de atención'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ---------- Aviso legal ----------
        _panel(
          titulo: 'Aviso legal',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _avisoLegalActualizadoCtrl,
                decoration: const InputDecoration(
                    labelText: 'Fecha de última actualización', hintText: 'septiembre de 2026'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('Secciones', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _mostrarFormSeccionLegal(),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Agregar sección'),
                  ),
                ],
              ),
              ..._contenidoEdit.avisoLegalSecciones.asMap().entries.map((entrada) {
                final i = entrada.key;
                final s = entrada.value;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(s.titulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Text(s.texto,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _mostrarFormSeccionLegal(indice: i),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 18, color: AppColors.bad),
                        onPressed: () =>
                            setState(() => _contenidoEdit.avisoLegalSecciones.removeAt(i)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton.icon(
            onPressed: _guardandoContenido ? null : _guardarContenido,
            icon: _guardandoContenido
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Guardar todos los cambios'),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Future<void> _mostrarFormFicha({int? indice}) async {
    final existente = indice != null ? _contenidoEdit.historiaFichas[indice] : null;
    final etiquetaCtrl = TextEditingController(text: existente?.etiqueta ?? '');
    final valorCtrl = TextEditingController(text: existente?.valor ?? '');

    final guardar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(indice == null ? 'Nueva ficha' : 'Editar ficha'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: etiquetaCtrl,
                decoration: const InputDecoration(labelText: 'Etiqueta', hintText: 'Ej: Ubicación'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valorCtrl,
                decoration: const InputDecoration(labelText: 'Valor'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Guardar')),
        ],
      ),
    );

    if (guardar != true) return;
    if (etiquetaCtrl.text.trim().isEmpty || valorCtrl.text.trim().isEmpty) return;
    setState(() {
      final ficha = FichaHistoria(etiqueta: etiquetaCtrl.text.trim(), valor: valorCtrl.text.trim());
      if (indice == null) {
        _contenidoEdit.historiaFichas.add(ficha);
      } else {
        _contenidoEdit.historiaFichas[indice] = ficha;
      }
    });
  }

  Future<void> _mostrarFormServicio({int? indice}) async {
    final existente = indice != null ? _contenidoEdit.servicios[indice] : null;
    final tituloCtrl = TextEditingController(text: existente?.titulo ?? '');
    final descripcionCtrl = TextEditingController(text: existente?.descripcion ?? '');

    final guardar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(indice == null ? 'Nuevo servicio' : 'Editar servicio'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tituloCtrl,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descripcionCtrl,
                decoration: const InputDecoration(labelText: 'Descripción'),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Guardar')),
        ],
      ),
    );

    if (guardar != true) return;
    if (tituloCtrl.text.trim().isEmpty) return;
    setState(() {
      final servicio =
          ServicioItem(titulo: tituloCtrl.text.trim(), descripcion: descripcionCtrl.text.trim());
      if (indice == null) {
        _contenidoEdit.servicios.add(servicio);
      } else {
        _contenidoEdit.servicios[indice] = servicio;
      }
    });
  }

  Future<void> _mostrarFormSeccionLegal({int? indice}) async {
    final existente = indice != null ? _contenidoEdit.avisoLegalSecciones[indice] : null;
    final tituloCtrl = TextEditingController(text: existente?.titulo ?? '');
    final textoCtrl = TextEditingController(text: existente?.texto ?? '');
    final itemsCtrl = TextEditingController(text: (existente?.items ?? []).join('\n'));

    final guardar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(indice == null ? 'Nueva sección' : 'Editar sección'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tituloCtrl,
                  decoration: const InputDecoration(labelText: 'Título', hintText: 'Ej: 4. Uso del sitio'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textoCtrl,
                  decoration: const InputDecoration(labelText: 'Texto'),
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: itemsCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Puntos en lista (opcional, uno por línea)'),
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Guardar')),
        ],
      ),
    );

    if (guardar != true) return;
    if (tituloCtrl.text.trim().isEmpty) return;
    setState(() {
      final items = itemsCtrl.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      final seccion = SeccionLegal(
        titulo: tituloCtrl.text.trim(),
        texto: textoCtrl.text.trim(),
        items: items,
      );
      if (indice == null) {
        _contenidoEdit.avisoLegalSecciones.add(seccion);
      } else {
        _contenidoEdit.avisoLegalSecciones[indice] = seccion;
      }
    });
  }
}
