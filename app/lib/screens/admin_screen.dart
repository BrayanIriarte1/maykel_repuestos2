import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../api_service.dart';
import '../config.dart';
import '../models.dart';
import '../utils/format.dart';
import '../utils/pdf_report.dart';
import '../widgets/admin_config_widgets.dart';
import '../widgets/admin_inventario.dart';
import '../widgets/admin_notificaciones.dart';
import '../widgets/admin_reservas.dart';
import '../widgets/admin_ui.dart';
import '../widgets/efectos.dart';
import '../widgets/portada_extra.dart';

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
  String _cfgSeccion = 'portada';
  late final Listenable _cfgCambios = Listenable.merge([
    _nombreNegocioCtrl, _heroTituloCtrl, _heroSubtituloCtrl, _heroBotonCatalogoCtrl, _heroBotonContactoCtrl,
    _heroEstadisticaProductosEtiquetaCtrl, _heroEstadisticaMarcasValorCtrl, _heroEstadisticaMarcasEtiquetaCtrl,
    _heroEstadisticaCategoriasValorCtrl, _heroEstadisticaCategoriasEtiquetaCtrl, _historiaKickerCtrl,
    _serviciosKickerCtrl, _serviciosTituloCtrl, _catalogoKickerCtrl, _catalogoTituloCtrl, _marcasTituloCtrl,
    _marcasSubtituloCtrl, _catalogoBusquedaHintCtrl, _contactoKickerCtrl, _contactoTituloCtrl,
    _footerDerechosCtrl, _historiaTituloCtrl, _historiaTextoCtrl, _contactoWhatsappCtrl, _contactoEmailCtrl,
    _contactoDireccionCtrl, _contactoMapsUrlCtrl, _contactoHorarioCtrl, _avisoLegalActualizadoCtrl,
  ]);
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
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: AppColors.red.withValues(alpha: 0.35), blurRadius: 22),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset('assets/images/logo_maykel.jpg', fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('PANEL DE ADMINISTRACIÓN',
                    style: TextStyle(
                        color: Colors.white38, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
              ],
            ),
          ),
          const SizedBox(height: 6),
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
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: activo
                ? const LinearGradient(colors: [Color(0xFFE53945), Color(0xFFB01822)])
                : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: activo
                ? [BoxShadow(color: AppColors.red.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))]
                : null,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            hoverColor: Colors.white.withValues(alpha: 0.07),
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
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: activo ? 0.2 : 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(s.icono, size: 18, color: activo ? Colors.white : Colors.white60),
                  ),
                  const SizedBox(width: 12),
                  Text(s.etiqueta,
                      style: TextStyle(
                          color: activo ? Colors.white : Colors.white70,
                          fontSize: 14.5,
                          fontWeight: activo ? FontWeight.w800 : FontWeight.w500)),
                  if (s.clave == 'reservas' && _pendientes > 0) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: activo ? Colors.white : AppColors.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('$_pendientes',
                          style: TextStyle(
                              color: activo ? AppColors.red : Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900)),
                    ),
                  ],
                ],
              ),
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
          InsigniaIcono(icono: seccion.icono, tam: 40),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(seccion.etiqueta,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.char, height: 1.1)),
              Text(_descripcionSeccion(seccion.clave),
                  style: const TextStyle(fontSize: 12, color: AppColors.steel)),
            ],
          ),
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
  String _descripcionSeccion(String clave) {
    switch (clave) {
      case 'analitica':
        return 'Ventas, demanda y rendimiento del negocio';
      case 'catalogo':
        return 'Todos los repuestos publicados en la web';
      case 'reservas':
        return 'Solicitudes de clientes por confirmar y entregar';
      case 'stock':
        return 'Ventas de mostrador, precios y existencias';
      case 'usuarios':
        return 'Equipo, roles y permisos de acceso';
      case 'configuracion':
        return 'Textos del sitio, notificaciones y sincronización';
      default:
        return 'Resumen del día y tareas pendientes';
    }
  }

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
    return AdminAncho(child: _contenidoSeccion());
  }

  Widget _contenidoSeccion() {
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
          AdminHero(
            titulo: 'Hola, ${_sesion.usuario.isEmpty ? "administrador" : _sesion.usuario} 👋',
            subtitulo:
                '${_saludoDia()} · ${_sesion.esSuperAdmin ? 'Propietario' : (_sesion.rolNombre ?? 'Equipo')}'
                '${_pendientes > 0 && _sesion.puede('reservas') ? ' · Tienes $_pendientes reserva${_pendientes == 1 ? '' : 's'} por atender' : ''}',
            icono: Icons.dashboard_customize_outlined,
            derecha: Wrap(spacing: 10, runSpacing: 10, children: [
              if (_sesion.puede('reservas'))
                FilledButton.icon(
                  onPressed: () => setState(() => _seccionActiva = 'reservas'),
                  icon: const Icon(Icons.event_note_outlined, size: 18),
                  label: const Text('Ver reservas'),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.char,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
                ),
              if (_sesion.puede('stock'))
                OutlinedButton.icon(
                  onPressed: () => setState(() => _seccionActiva = 'stock'),
                  icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                  label: const Text('Registrar venta'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
                ),
            ]),
          ),
          const SizedBox(height: 24),
          if (d != null)
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth >= 1500 ? 6 : (c.maxWidth >= 1100 ? 3 : (c.maxWidth >= 640 ? 2 : 1));
              const gap = 16.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              Widget k(Widget kpi) => SizedBox(width: w, child: kpi);
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  if (_sesion.puede('reservas'))
                    k(KpiTile(
                        valor: '$_pendientes',
                        etiqueta: 'Reservas por atender',
                        icono: Icons.hourglass_top_rounded,
                        colores: AdminColores.ambar,
                        nota: _pendientes > 0 ? 'Atender ahora' : 'Todo al día',
                        onTap: () => setState(() => _seccionActiva = 'reservas'))),
                  if (_sesion.puede('reservas'))
                    k(KpiTile(
                        valor: '${d.reservasConfirmadas}',
                        etiqueta: 'Por retirar (${d.unidadesRetenidas} u.)',
                        icono: Icons.inventory_outlined,
                        colores: AdminColores.azul)),
                  k(KpiTile(
                      valor: '${d.productosPublicados}',
                      etiqueta: 'Productos publicados',
                      icono: Icons.inventory_2_outlined,
                      colores: AdminColores.verde,
                      onTap: _sesion.puede('catalogo') ? () => setState(() => _seccionActiva = 'catalogo') : null)),
                  k(KpiTile(
                      valor: '${d.agotadosCount}',
                      etiqueta: 'Productos agotados',
                      icono: Icons.report_outlined,
                      colores: AdminColores.rojo)),
                  if (_sesion.puede('stock'))
                    k(KpiTile(
                        valor: '${d.totalVentas}',
                        etiqueta: 'Ventas registradas',
                        icono: Icons.point_of_sale_outlined,
                        colores: AdminColores.violeta)),
                  if (_sesion.puede('stock'))
                    k(KpiTile(
                        valor: formatCLP(d.montoVentas),
                        etiqueta: 'Monto vendido',
                        icono: Icons.payments_outlined,
                        colores: AdminColores.verde)),
                ],
              );
            }),
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
    return AdminPanel(
      titulo: titulo,
      icono: icono,
      accion: accion == null
          ? null
          : TextButton.icon(
              onPressed: onAccion,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: Text(accion),
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
            ),
      child: child,
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
        duration: const Duration(milliseconds: 200),
        width: 210,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: hover ? const [Color(0xFF2A2A2E), AppColors.char] : const [Colors.white, Colors.white],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hover ? AppColors.red : AdminColores.borde, width: 1.4),
          boxShadow: [
            BoxShadow(
                color: (hover ? AppColors.red : Colors.black).withValues(alpha: hover ? 0.25 : 0.06),
                blurRadius: hover ? 22 : 12,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InsigniaIcono(icono: s.icono, tam: 46),
            const SizedBox(height: 14),
            Text(s.etiqueta,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: hover ? Colors.white : AppColors.char)),
            const SizedBox(height: 2),
            Text(_descripcionSeccion(s.clave),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, height: 1.3, color: hover ? Colors.white60 : AppColors.steel)),
          ],
        ),
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
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 1500 ? 6 : (c.maxWidth >= 1100 ? 3 : (c.maxWidth >= 640 ? 2 : 1));
            const gap = 16.0;
            final w = (c.maxWidth - gap * (cols - 1)) / cols;
            Widget k(String v, String e, IconData i, List<Color> col) =>
                SizedBox(width: w, child: KpiTile(valor: v, etiqueta: e, icono: i, colores: col));
            return Wrap(spacing: gap, runSpacing: gap, children: [
              k('${d.totalVentas}', 'Ventas registradas', Icons.point_of_sale_outlined, AdminColores.violeta),
              k(formatCLP(d.montoVentas), 'Monto vendido (CLP)', Icons.payments_outlined, AdminColores.verde),
              k('${d.totalReservas}', 'Reservas totales (${d.reservasPendientes} pend.)',
                  Icons.event_note_outlined, AdminColores.azul),
              k('${d.reservasConfirmadas}',
                  'Por retirar (${d.unidadesRetenidas} u. · ${formatCLP(d.montoRetenido)})',
                  Icons.inventory_outlined, AdminColores.ambar),
              k('${d.stockBajoCount}', 'Stock bajo (≤ 3 u.)', Icons.warning_amber_rounded, AdminColores.ambar),
              k('${d.agotadosCount}', 'Productos agotados', Icons.report_outlined, AdminColores.rojo),
            ]);
          }),
          const SizedBox(height: 20),
          LayoutBuilder(builder: (context, c) {
            final totalRes = _reservas.isEmpty ? 1 : _reservas.length;
            int n(String e) => _reservas.where((r) => r.estado == e).length;
            final pub = d.productosPublicados == 0 ? 1 : d.productosPublicados;
            final embudo = AdminPanel(
              titulo: 'Embudo de reservas',
              subtitulo: 'Cómo avanzan las solicitudes de los clientes',
              icono: Icons.filter_alt_outlined,
              colores: AdminColores.azul,
              child: Column(children: [
                BarraProgreso(etiqueta: 'Pendientes', valor: '${n('pendiente')}', fraccion: n('pendiente') / totalRes, color: const Color(0xFFF08A00)),
                BarraProgreso(etiqueta: 'Por retirar (confirmadas)', valor: '${n('confirmada')}', fraccion: n('confirmada') / totalRes, color: const Color(0xFF1B4F8A)),
                BarraProgreso(etiqueta: 'Entregadas', valor: '${n('entregada')}', fraccion: n('entregada') / totalRes, color: const Color(0xFF14785C)),
                BarraProgreso(etiqueta: 'Rechazadas', valor: '${n('rechazada')}', fraccion: n('rechazada') / totalRes, color: const Color(0xFF9E1119)),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                      _reservas.isEmpty
                          ? 'Aún no hay reservas.'
                          : 'Conversión: ${(n('entregada') * 100 / totalRes).toStringAsFixed(0)} % de las reservas terminan en venta.',
                      style: const TextStyle(color: AppColors.steel, fontSize: 12.5)),
                ),
              ]),
            );
            final salud = AdminPanel(
              titulo: 'Salud del inventario',
              subtitulo: 'Sobre ${d.productosPublicados} productos publicados',
              icono: Icons.health_and_safety_outlined,
              colores: AdminColores.verde,
              child: Column(children: [
                BarraProgreso(etiqueta: 'Con stock suficiente', valor: '${(d.productosPublicados - d.agotadosCount - d.stockBajoCount).clamp(0, 1 << 30)}', fraccion: (d.productosPublicados - d.agotadosCount - d.stockBajoCount) / pub, color: const Color(0xFF14785C)),
                BarraProgreso(etiqueta: 'Stock bajo (≤ 3)', valor: '${d.stockBajoCount}', fraccion: d.stockBajoCount / pub, color: const Color(0xFFF08A00)),
                BarraProgreso(etiqueta: 'Agotados', valor: '${d.agotadosCount}', fraccion: d.agotadosCount / pub, color: const Color(0xFF9E1119)),
                BarraProgreso(etiqueta: 'Sin precio', valor: '${d.sinPrecioCount}', fraccion: d.sinPrecioCount / pub, color: const Color(0xFF5A2FA0)),
              ]),
            );
            if (c.maxWidth < 900) return Column(children: [embudo, const SizedBox(height: 16), salud]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: embudo),
              const SizedBox(width: 16),
              Expanded(child: salud),
            ]);
          }),
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
    final t = titulo.toLowerCase();
    final icono = t.contains('venta') && t.contains('día')
        ? Icons.show_chart
        : t.contains('categor')
            ? Icons.donut_large
            : t.contains('demanda')
                ? Icons.local_fire_department_outlined
                : t.contains('sin stock')
                    ? Icons.remove_shopping_cart_outlined
                    : Icons.insights_outlined;
    return AdminPanel(
      titulo: titulo,
      icono: icono,
      colores: t.contains('sin stock') ? AdminColores.rojo : (t.contains('demanda') ? AdminColores.ambar : AdminColores.azul),
      child: SizedBox(height: alto, child: child),
    );
  }

  Widget _sinDatos(String texto) {
    return VacioAdmin(icono: Icons.query_stats, titulo: 'Sin datos todavía', texto: texto);
  }

  Widget _tablaSimple({required List<String> columnas, required List<List<String>> filas}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: AdminColores.fondo, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            for (final c in columnas)
              Expanded(
                  child: Text(c.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.steel))),
          ]),
        ),
        for (var i = 0; i < filas.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: i == filas.length - 1 ? Colors.transparent : AdminColores.borde)),
            ),
            child: Row(children: [
              for (final c in filas[i])
                Expanded(
                    child: Text(c,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.char))),
            ]),
          ),
      ],
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AdminColores.borde),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const InsigniaIcono(icono: Icons.point_of_sale_outlined, tam: 44, colores: AdminColores.violeta),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Registrar venta de mostrador',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.char)),
                Text('Descuenta el stock al instante y queda reflejada en Analítica.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.steel)),
              ]),
            ),
            OutlinedButton.icon(
              onPressed: _descargarPdfVentas,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('Ventas en PDF'),
            ),
          ]),
          const SizedBox(height: 18),
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
            const SizedBox(height: 22),
          ],
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

  /// Recarga solo roles y usuarios (sin el spinner de pantalla completa).
  Future<void> _usrRecargar() async {
    try {
      final r = await Future.wait<Object?>([
        ApiService.instance.getRoles(),
        ApiService.instance.getUsuariosAdmin(),
      ]);
      if (!mounted) return;
      setState(() {
        _roles = r[0] as List<Rol>;
        _usuariosAdmin = r[1] as List<UsuarioAdmin>;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _usrCambiarActivo(UsuarioAdmin u, bool activo) async {
    try {
      await ApiService.instance.actualizarUsuarioAdmin(u.id, activo: activo);
      await _usrRecargar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _buildUsuariosTab() {
    final activos = _usuariosAdmin.where((u) => u.activo).length;
    final ancho = MediaQuery.of(context).size.width;
    final botones = Wrap(spacing: 12, runSpacing: 10, children: [
      ElevatedButton.icon(
        onPressed: _roles.isEmpty ? null : () => _mostrarFormUsuario(),
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17)),
        icon: const Icon(Icons.person_add_alt_1, size: 20),
        label: const Text('Nuevo usuario'),
      ),
      ElevatedButton.icon(
        onPressed: () => _mostrarFormRol(),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.char,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
        ),
        icon: const Icon(Icons.add_moderator_outlined, size: 20),
        label: const Text('Nuevo rol'),
      ),
    ]);
    final resumen = Wrap(spacing: 12, runSpacing: 10, children: [
      UsrMiniStat('${_usuariosAdmin.length}', 'Usuarios'),
      UsrMiniStat('$activos', 'Activos'),
      UsrMiniStat('${_roles.length}', 'Roles'),
    ]);

    return RefreshIndicator(
      onRefresh: _usrRecargar,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          AdminAncho(
            max: 2200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminHero(
                  titulo: 'Usuarios y roles',
                  subtitulo: 'Crea roles con permisos específicos y asígnalos a las personas de tu equipo '
                      'que necesiten acceso al panel.',
                  icono: Icons.admin_panel_settings_outlined,
                  derecha: ancho >= 1300 ? resumen : null,
                ),
                const SizedBox(height: 14),
                if (ancho < 1300) ...[
                  resumen,
                  const SizedBox(height: 14),
                ],
                botones,
                const SizedBox(height: 28),
                _usrEncabezado('Usuarios del panel', '${_usuariosAdmin.length} en total · $activos activos',
                    Icons.people_alt_outlined, AdminColores.azul),
                if (_roles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: CfgAviso(
                      texto: 'Crea al menos un rol antes de agregar usuarios.',
                      color: AppColors.warn,
                      icono: Icons.info_outline,
                    ),
                  ),
                UsrListaUsuarios(
                  usuarios: _usuariosAdmin,
                  roles: _roles,
                  usuarioActual: _sesion.usuario,
                  onEditar: (u) => _mostrarFormUsuario(usuario: u),
                  onEliminar: _eliminarUsuario,
                  onActivo: _usrCambiarActivo,
                  onNuevo: _roles.isEmpty ? null : () => _mostrarFormUsuario(),
                ),
                const SizedBox(height: 34),
                _usrEncabezado('Roles y permisos', 'Qué puede hacer cada rol dentro del panel',
                    Icons.shield_outlined, AdminColores.violeta),
                if (_roles.isEmpty)
                  AdminPanel(
                    child: VacioAdmin(
                      icono: Icons.shield_outlined,
                      titulo: 'Aún no has creado ningún rol',
                      texto: 'Un rol agrupa los permisos (catálogo, reservas, stock…) que tendrá una persona.',
                      accion: ElevatedButton.icon(
                        onPressed: () => _mostrarFormRol(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Nuevo rol'),
                      ),
                    ),
                  )
                else
                  CfgCuadricula(
                    minAncho: 360,
                    maxColumnas: 4,
                    children: [
                      for (final r in _roles)
                        UsrTarjetaRol(
                          key: ValueKey('rol-${r.id}'),
                          rol: r,
                          usuarios: _usuariosAdmin.where((u) => u.rolId == r.id).length,
                          onEditar: () => _mostrarFormRol(rol: r),
                          onEliminar: () => _eliminarRol(r),
                        ),
                    ],
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _usrEncabezado(String titulo, String subtitulo, IconData icono, List<Color> colores) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        InsigniaIcono(icono: icono, tam: 40, colores: colores),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.char)),
            Text(subtitulo, style: const TextStyle(fontSize: 12.5, color: AppColors.steel)),
          ]),
        ),
      ]),
    );
  }

  Future<void> _mostrarFormRol({Rol? rol}) =>
      mostrarDialogoRol(context, rol: rol, alGuardar: _usrRecargar);

  Future<void> _eliminarRol(Rol rol) async {
    final enUso = _usuariosAdmin.where((u) => u.rolId == rol.id).length;
    final confirmar = await mostrarConfirmacionEliminar(
      context,
      titulo: 'Eliminar rol',
      mensaje: '¿Eliminar el rol "${rol.nombre}"?',
      detalle: enUso > 0
          ? 'Hay $enUso ${enUso == 1 ? 'usuario' : 'usuarios'} con este rol. '
              'Cámbiales el rol antes de eliminarlo.'
          : null,
    );
    if (!confirmar) return;
    try {
      await ApiService.instance.eliminarRol(rol.id);
      await _usrRecargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _mostrarFormUsuario({UsuarioAdmin? usuario}) =>
      mostrarDialogoUsuario(context, usuario: usuario, roles: _roles, alGuardar: _usrRecargar);

  Future<void> _eliminarUsuario(UsuarioAdmin usuario) async {
    final confirmar = await mostrarConfirmacionEliminar(
      context,
      titulo: 'Eliminar usuario',
      mensaje: '¿Eliminar el acceso de "${usuario.usuario}"?',
      detalle: 'Si solo quieres suspender el acceso temporalmente, desactívalo con el interruptor de su tarjeta.',
    );
    if (!confirmar) return;
    try {
      await ApiService.instance.eliminarUsuarioAdmin(usuario.id);
      await _usrRecargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  // ---------------------------------------------------------------
  // Configuración
  // ---------------------------------------------------------------

  static const _cfgSecciones = <CfgSeccionInfo>[
    CfgSeccionInfo('portada', 'Portada', 'Título, botones y cifras', Icons.web_asset_outlined),
    CfgSeccionInfo('marcas', 'Marcas y catálogo', 'Encabezados y buscador', Icons.sell_outlined),
    CfgSeccionInfo('historia', 'Historia', 'Texto y datos destacados', Icons.history_edu_outlined),
    CfgSeccionInfo('servicios', 'Servicios', 'Lo que ofreces', Icons.build_circle_outlined),
    CfgSeccionInfo('contacto', 'Contacto y horario', 'WhatsApp, dirección y horario', Icons.contact_phone_outlined),
    CfgSeccionInfo('legal', 'Aviso legal', 'Secciones legales', Icons.gavel_outlined),
    CfgSeccionInfo('pie', 'Pie de página', 'Derechos de autor', Icons.vertical_align_bottom),
    CfgSeccionInfo('notificaciones', 'Notificaciones y sincronización', 'Correo, WhatsApp y sync',
        Icons.notifications_active_outlined),
  ];

  static const _cfgAyudas = <String, String>{
    'portada': 'Lo primero que ven tus clientes: título, botones y cifras destacadas.',
    'marcas': 'Encabezados de la sección de marcas y del catálogo, y el texto del buscador.',
    'historia': 'Cuenta quién eres y destaca datos clave de tu negocio.',
    'servicios': 'Encabezado de la sección y listado de los servicios que ofreces.',
    'contacto': 'Cómo te encuentran los clientes: WhatsApp, correo, dirección y horario.',
    'legal': 'Textos legales del sitio. Cada sección se muestra como un apartado.',
    'pie': 'Texto de derechos que aparece al final de todas las páginas.',
    'notificaciones':
        'Comprueba que los avisos de reservas lleguen por correo y WhatsApp, y sincroniza el stock con el sistema del cliente.',
  };

  /// Secciones con cambios sin guardar (se compara con lo último guardado).
  Set<String> _cfgModificadas() {
    final g = SiteContent.actual;
    final m = <String>{};
    void c(String sec, TextEditingController ctrl, String guardado) {
      if (ctrl.text.trim() != guardado.trim()) m.add(sec);
    }

    c('portada', _nombreNegocioCtrl, g.nombreNegocio);
    c('portada', _heroTituloCtrl, g.heroTitulo);
    c('portada', _heroSubtituloCtrl, g.heroSubtitulo);
    c('portada', _heroBotonCatalogoCtrl, g.heroBotonCatalogo);
    c('portada', _heroBotonContactoCtrl, g.heroBotonContacto);
    c('portada', _heroEstadisticaProductosEtiquetaCtrl, g.heroEstadisticaProductosEtiqueta);
    c('portada', _heroEstadisticaMarcasValorCtrl, g.heroEstadisticaMarcasValor);
    c('portada', _heroEstadisticaMarcasEtiquetaCtrl, g.heroEstadisticaMarcasEtiqueta);
    c('portada', _heroEstadisticaCategoriasValorCtrl, g.heroEstadisticaCategoriasValor);
    c('portada', _heroEstadisticaCategoriasEtiquetaCtrl, g.heroEstadisticaCategoriasEtiqueta);
    c('marcas', _catalogoKickerCtrl, g.catalogoKicker);
    c('marcas', _catalogoTituloCtrl, g.catalogoTitulo);
    c('marcas', _marcasTituloCtrl, g.marcasTitulo);
    c('marcas', _marcasSubtituloCtrl, g.marcasSubtitulo);
    c('marcas', _catalogoBusquedaHintCtrl, g.catalogoBusquedaHint);
    c('historia', _historiaKickerCtrl, g.historiaKicker);
    c('historia', _historiaTituloCtrl, g.historiaTitulo);
    c('historia', _historiaTextoCtrl, g.historiaTexto);
    if (!cfgJsonIgual(_contenidoEdit.historiaFichas.map((f) => f.toJson()).toList(),
        g.historiaFichas.map((f) => f.toJson()).toList())) {
      m.add('historia');
    }
    c('servicios', _serviciosKickerCtrl, g.serviciosKicker);
    c('servicios', _serviciosTituloCtrl, g.serviciosTitulo);
    if (!cfgJsonIgual(_contenidoEdit.servicios.map((s) => s.toJson()).toList(),
        g.servicios.map((s) => s.toJson()).toList())) {
      m.add('servicios');
    }
    c('contacto', _contactoKickerCtrl, g.contactoKicker);
    c('contacto', _contactoTituloCtrl, g.contactoTitulo);
    c('contacto', _contactoWhatsappCtrl, g.contactoWhatsapp);
    c('contacto', _contactoEmailCtrl, g.contactoEmail);
    c('contacto', _contactoDireccionCtrl, g.contactoDireccion);
    c('contacto', _contactoMapsUrlCtrl, g.contactoMapsUrl);
    c('contacto', _contactoHorarioCtrl, g.contactoHorario);
    c('legal', _avisoLegalActualizadoCtrl, g.avisoLegalActualizado);
    if (!cfgJsonIgual(_contenidoEdit.avisoLegalSecciones.map((s) => s.toJson()).toList(),
        g.avisoLegalSecciones.map((s) => s.toJson()).toList())) {
      m.add('legal');
    }
    c('pie', _footerDerechosCtrl, g.footerDerechos);
    return m;
  }

  Future<void> _cfgDescartar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar cambios'),
        content: const Text('Se perderán los cambios que no hayas guardado y se volverá al último contenido guardado.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Seguir editando')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Descartar', style: TextStyle(color: AppColors.bad)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _contenidoEdit = SiteContent.actual.copiaProfunda();
      _sincronizarControladoresContenido();
      _resultadoContenido = null;
    });
  }

  Widget _buildConfiguracionTab() {
    final angosto = MediaQuery.of(context).size.width < 1100;
    return AnimatedBuilder(
      animation: _cfgCambios,
      builder: (context, _) {
        final mod = _cfgModificadas();
        final nav = CfgNavegacion(
          secciones: _cfgSecciones,
          activa: _cfgSeccion,
          modificadas: mod,
          horizontal: angosto,
          onSeleccionar: (c) => setState(() => _cfgSeccion = c),
        );
        return Column(children: [
          CfgBarraGuardar(
            hayCambios: mod.isNotEmpty,
            guardando: _guardandoContenido,
            seccionesModificadas: mod.length,
            mensaje: _resultadoContenido,
            mensajeEsError: _resultadoContenidoEsError,
            onGuardar: _guardarContenido,
            onDescartar: _cfgDescartar,
          ),
          if (angosto) Material(color: Colors.white, child: nav),
          Expanded(
            child: angosto
                ? _cfgContenido()
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 300,
                      child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 24, 0, 24), child: nav),
                    ),
                    Expanded(child: _cfgContenido()),
                  ]),
          ),
        ]);
      },
    );
  }

  Widget _cfgContenido() {
    final info = _cfgSecciones.firstWhere((s) => s.clave == _cfgSeccion, orElse: () => _cfgSecciones.first);
    final List<Widget> hijos;
    switch (info.clave) {
      case 'marcas':
        hijos = _cfgMarcas();
      case 'historia':
        hijos = _cfgHistoria();
      case 'servicios':
        hijos = _cfgServicios();
      case 'contacto':
        hijos = _cfgContacto();
      case 'legal':
        hijos = _cfgLegal();
      case 'pie':
        hijos = _cfgPie();
      case 'notificaciones':
        hijos = [
          NotificacionesSyncPanel(
            verNotificaciones: _sesion.puede('configuracion'),
            verSincronizacion: _sesion.puede('stock'),
          ),
        ];
      default:
        hijos = _cfgPortada();
    }
    return ListView(
      key: PageStorageKey('cfg-${info.clave}'),
      padding: const EdgeInsets.all(24),
      children: [
        AdminAncho(
          max: 1500,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              InsigniaIcono(icono: info.icono, tam: 50),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(info.etiqueta,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.char)),
                  Text(_cfgAyudas[info.clave] ?? '',
                      style: const TextStyle(fontSize: 13, color: AppColors.steel, height: 1.4)),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            ...hijos,
            const SizedBox(height: 20),
          ]),
        ),
      ],
    );
  }

  List<Widget> _cfgPortada() => [
        CfgDosColumnas(
          izquierda: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AdminPanel(
              titulo: 'Textos principales',
              subtitulo: 'Lo primero que ve el cliente al entrar al sitio',
              icono: Icons.title,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                CfgCampo(
                  controller: _nombreNegocioCtrl,
                  etiqueta: 'Nombre del negocio',
                  ayuda: 'Se muestra en el encabezado, la portada y el pie de página.',
                  icono: Icons.storefront_outlined,
                ),
                const SizedBox(height: 14),
                CfgCampo(
                  controller: _heroTituloCtrl,
                  etiqueta: 'Título principal',
                  ayuda: 'Usa un salto de línea (Enter) para partirlo en dos líneas.',
                  maxLines: 2,
                  minLines: 2,
                ),
                const SizedBox(height: 14),
                CfgCampo(
                  controller: _heroSubtituloCtrl,
                  etiqueta: 'Subtítulo',
                  ayuda: 'Una o dos frases que resuman lo que ofreces.',
                  maxLines: 3,
                  minLines: 2,
                ),
              ]),
            ),
            const SizedBox(height: 18),
            AdminPanel(
              titulo: 'Botones de la portada',
              subtitulo: 'Los dos accesos grandes bajo el título',
              icono: Icons.smart_button_outlined,
              colores: AdminColores.azul,
              child: CfgFila(children: [
                CfgCampo(
                  controller: _heroBotonCatalogoCtrl,
                  etiqueta: 'Texto del botón «Ver catálogo»',
                  ayuda: 'Lleva al catálogo de productos.',
                  icono: Icons.grid_view_outlined,
                ),
                CfgCampo(
                  controller: _heroBotonContactoCtrl,
                  etiqueta: 'Texto del botón «Contáctanos»',
                  ayuda: 'Lleva a la sección de contacto.',
                  icono: Icons.chat_bubble_outline,
                ),
              ]),
            ),
            const SizedBox(height: 18),
            AdminPanel(
              titulo: 'Estadísticas de la portada',
              subtitulo: 'Tres cifras que transmiten confianza',
              icono: Icons.bar_chart,
              colores: AdminColores.verde,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                CfgCampo(
                  controller: _heroEstadisticaProductosEtiquetaCtrl,
                  etiqueta: 'Etiqueta de productos',
                  ayuda: 'El número se calcula solo a partir del catálogo.',
                  icono: Icons.inventory_2_outlined,
                ),
                const SizedBox(height: 14),
                CfgFila(flex: const [1, 2], children: [
                  CfgCampo(
                    controller: _heroEstadisticaMarcasValorCtrl,
                    etiqueta: 'Valor (marcas)',
                    ayuda: 'Ej.: 46',
                  ),
                  CfgCampo(
                    controller: _heroEstadisticaMarcasEtiquetaCtrl,
                    etiqueta: 'Etiqueta (marcas)',
                    ayuda: 'Ej.: Marcas disponibles',
                  ),
                ]),
                const SizedBox(height: 14),
                CfgFila(flex: const [1, 2], children: [
                  CfgCampo(
                    controller: _heroEstadisticaCategoriasValorCtrl,
                    etiqueta: 'Valor (categorías)',
                    ayuda: 'Ej.: 130',
                  ),
                  CfgCampo(
                    controller: _heroEstadisticaCategoriasEtiquetaCtrl,
                    etiqueta: 'Etiqueta (categorías)',
                    ayuda: 'Ej.: Categorías',
                  ),
                ]),
              ]),
            ),
          ]),
          derecha: CfgVistaPrevia(
            ayuda: 'Se actualiza mientras escribes',
            child: CfgPreviewHero(
              nombre: _nombreNegocioCtrl,
              titulo: _heroTituloCtrl,
              subtitulo: _heroSubtituloCtrl,
              botonCatalogo: _heroBotonCatalogoCtrl,
              botonContacto: _heroBotonContactoCtrl,
              productosEtiqueta: _heroEstadisticaProductosEtiquetaCtrl,
              marcasValor: _heroEstadisticaMarcasValorCtrl,
              marcasEtiqueta: _heroEstadisticaMarcasEtiquetaCtrl,
              categoriasValor: _heroEstadisticaCategoriasValorCtrl,
              categoriasEtiqueta: _heroEstadisticaCategoriasEtiquetaCtrl,
            ),
          ),
        ),
      ];

  List<Widget> _cfgMarcas() => [
        AdminPanel(
          titulo: 'Sección de marcas',
          subtitulo: 'El bloque con los logotipos de las marcas con las que trabajas',
          icono: Icons.sell_outlined,
          colores: AdminColores.ambar,
          child: CfgFila(flex: const [1, 1], children: [
            CfgCampo(
              controller: _marcasTituloCtrl,
              etiqueta: 'Título',
              ayuda: 'Pregunta o frase que invita a buscar por marca.',
              maxLines: 2,
              minLines: 2,
            ),
            CfgCampo(
              controller: _marcasSubtituloCtrl,
              etiqueta: 'Subtítulo',
              ayuda: 'Explica qué pasa al tocar una marca.',
              maxLines: 2,
              minLines: 2,
            ),
          ]),
        ),
        const SizedBox(height: 18),
        AdminPanel(
          titulo: 'Catálogo',
          subtitulo: 'Encabezado de la sección y buscador',
          icono: Icons.grid_view_outlined,
          colores: AdminColores.azul,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CfgFila(children: [
              CfgCampo(
                controller: _catalogoKickerCtrl,
                etiqueta: 'Kicker del catálogo',
                ayuda: 'La etiqueta pequeña sobre el título. Ej.: CATÁLOGO',
              ),
              CfgCampo(
                controller: _catalogoTituloCtrl,
                etiqueta: 'Título del catálogo',
                ayuda: 'El título grande de la sección.',
              ),
            ]),
            const SizedBox(height: 14),
            CfgCampo(
              controller: _catalogoBusquedaHintCtrl,
              etiqueta: 'Texto de ayuda del buscador',
              ayuda: 'Lo que aparece dentro de la caja de búsqueda antes de escribir.',
              icono: Icons.search,
            ),
          ]),
        ),
      ];

  List<Widget> _cfgHistoria() => [
        AdminPanel(
          titulo: 'Texto de la historia',
          subtitulo: 'Presenta tu negocio',
          icono: Icons.history_edu_outlined,
          colores: AdminColores.violeta,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CfgFila(flex: const [1, 2], children: [
              CfgCampo(
                controller: _historiaKickerCtrl,
                etiqueta: 'Kicker',
                ayuda: 'Etiqueta pequeña sobre el título. Ej.: NUESTRA HISTORIA',
              ),
              CfgCampo(
                controller: _historiaTituloCtrl,
                etiqueta: 'Título',
                ayuda: 'El título grande de la sección.',
              ),
            ]),
            const SizedBox(height: 14),
            CfgCampo(
              controller: _historiaTextoCtrl,
              etiqueta: 'Texto',
              ayuda: 'Cuenta tu historia con tus palabras. Puedes usar varios párrafos.',
              maxLines: 8,
              minLines: 5,
            ),
          ]),
        ),
        const SizedBox(height: 18),
        AdminPanel(
          titulo: 'Datos destacados',
          subtitulo: 'Fichas cortas junto a la historia (ubicación, años de experiencia…)',
          icono: Icons.badge_outlined,
          colores: AdminColores.azul,
          accion: ElevatedButton.icon(
            onPressed: () => _mostrarFormFicha(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Agregar ficha'),
          ),
          child: _contenidoEdit.historiaFichas.isEmpty
              ? const CfgListaVacia('Aún no hay fichas. Agrega la primera con «Agregar ficha».',
                  icono: Icons.badge_outlined)
              : CfgCuadricula(minAncho: 420, maxColumnas: 2, espacio: 12, children: [
                  for (final e in _contenidoEdit.historiaFichas.asMap().entries)
                    CfgItemLista(
                      icono: Icons.badge_outlined,
                      titulo: e.value.etiqueta,
                      subtitulo: e.value.valor,
                      onEditar: () => _mostrarFormFicha(indice: e.key),
                      onEliminar: () => setState(() => _contenidoEdit.historiaFichas.removeAt(e.key)),
                    ),
                ]),
        ),
      ];

  List<Widget> _cfgServicios() => [
        AdminPanel(
          titulo: 'Encabezado de la sección',
          icono: Icons.title,
          colores: AdminColores.verde,
          child: CfgFila(children: [
            CfgCampo(
              controller: _serviciosKickerCtrl,
              etiqueta: 'Kicker',
              ayuda: 'Etiqueta pequeña sobre el título. Ej.: SERVICIOS',
            ),
            CfgCampo(
              controller: _serviciosTituloCtrl,
              etiqueta: 'Título',
              ayuda: 'El título grande de la sección.',
            ),
          ]),
        ),
        const SizedBox(height: 18),
        AdminPanel(
          titulo: 'Servicios',
          subtitulo: 'Lo que se muestra en la sección «Servicios» del sitio',
          icono: Icons.build_circle_outlined,
          colores: AdminColores.verde,
          accion: ElevatedButton.icon(
            onPressed: () => _mostrarFormServicio(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Agregar servicio'),
          ),
          child: _contenidoEdit.servicios.isEmpty
              ? const CfgListaVacia('Aún no hay servicios. Agrega el primero con «Agregar servicio».',
                  icono: Icons.build_circle_outlined)
              : CfgCuadricula(minAncho: 420, maxColumnas: 2, espacio: 12, children: [
                  for (final e in _contenidoEdit.servicios.asMap().entries)
                    CfgItemLista(
                      icono: Icons.build_outlined,
                      colores: AdminColores.verde,
                      titulo: e.value.titulo,
                      subtitulo: e.value.descripcion,
                      onEditar: () => _mostrarFormServicio(indice: e.key),
                      onEliminar: () => setState(() => _contenidoEdit.servicios.removeAt(e.key)),
                    ),
                ]),
        ),
      ];

  List<Widget> _cfgContacto() => [
        CfgDosColumnas(
          izquierda: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AdminPanel(
              titulo: 'Encabezado de la sección',
              icono: Icons.title,
              colores: AdminColores.azul,
              child: CfgFila(children: [
                CfgCampo(
                  controller: _contactoKickerCtrl,
                  etiqueta: 'Kicker',
                  ayuda: 'Etiqueta pequeña sobre el título. Ej.: CONTACTO',
                ),
                CfgCampo(
                  controller: _contactoTituloCtrl,
                  etiqueta: 'Título',
                  ayuda: 'El título grande de la sección.',
                ),
              ]),
            ),
            const SizedBox(height: 18),
            AdminPanel(
              titulo: 'Datos de contacto',
              subtitulo: 'Por aquí te escriben tus clientes',
              icono: Icons.contact_phone_outlined,
              colores: AdminColores.verde,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                CfgFila(children: [
                  CfgCampo(
                    controller: _contactoWhatsappCtrl,
                    etiqueta: 'WhatsApp',
                    hint: '56912345678',
                    ayuda: 'Solo números, con código de país y sin «+».',
                    icono: Icons.phone_outlined,
                    teclado: TextInputType.phone,
                  ),
                  CfgCampo(
                    controller: _contactoEmailCtrl,
                    etiqueta: 'Correo de contacto',
                    ayuda: 'Es el correo que ven tus clientes en el sitio.',
                    icono: Icons.mail_outline,
                    teclado: TextInputType.emailAddress,
                  ),
                ]),
                const SizedBox(height: 14),
                CfgCampo(
                  controller: _contactoDireccionCtrl,
                  etiqueta: 'Dirección',
                  ayuda: 'Calle, número y ciudad.',
                  icono: Icons.place_outlined,
                ),
                const SizedBox(height: 14),
                CfgCampo(
                  controller: _contactoMapsUrlCtrl,
                  etiqueta: 'Enlace de Google Maps',
                  ayuda: 'En Google Maps usa «Compartir» → «Copiar enlace» y pégalo aquí.',
                  icono: Icons.map_outlined,
                  teclado: TextInputType.url,
                ),
              ]),
            ),
            const SizedBox(height: 18),
            AdminPanel(
              titulo: 'Horario de atención',
              icono: Icons.schedule,
              colores: AdminColores.ambar,
              child: CfgCampo(
                controller: _contactoHorarioCtrl,
                etiqueta: 'Horario',
                ayuda: 'Una línea por tramo. Ej.: Lunes a viernes, 9:30 – 19:00',
                maxLines: 4,
                minLines: 2,
              ),
            ),
          ]),
          derecha: CfgVistaPrevia(
            child: CfgPreviewContacto(
              horario: _contactoHorarioCtrl,
              direccion: _contactoDireccionCtrl,
              whatsapp: _contactoWhatsappCtrl,
              email: _contactoEmailCtrl,
            ),
          ),
        ),
      ];

  List<Widget> _cfgLegal() => [
        AdminPanel(
          titulo: 'Fecha de actualización',
          icono: Icons.event_outlined,
          colores: AdminColores.violeta,
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: CfgCampo(
                controller: _avisoLegalActualizadoCtrl,
                etiqueta: 'Última actualización',
                hint: 'septiembre de 2026',
                ayuda: 'Se muestra al inicio del aviso legal.',
                icono: Icons.event_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        AdminPanel(
          titulo: 'Secciones del aviso legal',
          subtitulo: 'Cada una aparece como un apartado con su título y texto',
          icono: Icons.gavel_outlined,
          colores: AdminColores.violeta,
          accion: ElevatedButton.icon(
            onPressed: () => _mostrarFormSeccionLegal(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Agregar sección'),
          ),
          child: _contenidoEdit.avisoLegalSecciones.isEmpty
              ? const CfgListaVacia('Aún no hay secciones. Agrega la primera con «Agregar sección».',
                  icono: Icons.gavel_outlined)
              : Column(children: [
                  for (final e in _contenidoEdit.avisoLegalSecciones.asMap().entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: CfgItemLista(
                        icono: Icons.description_outlined,
                        colores: AdminColores.violeta,
                        titulo: e.value.titulo,
                        subtitulo: e.value.items.isEmpty
                            ? e.value.texto
                            : '${e.value.texto}\n${e.value.items.length} puntos en lista',
                        onEditar: () => _mostrarFormSeccionLegal(indice: e.key),
                        onEliminar: () => setState(() => _contenidoEdit.avisoLegalSecciones.removeAt(e.key)),
                      ),
                    ),
                ]),
        ),
      ];

  List<Widget> _cfgPie() => [
        CfgDosColumnas(
          izquierda: AdminPanel(
            titulo: 'Derechos de autor',
            subtitulo: 'La línea final de todas las páginas',
            icono: Icons.copyright,
            colores: AdminColores.gris,
            child: CfgCampo(
              controller: _footerDerechosCtrl,
              etiqueta: 'Texto de derechos',
              ayuda: 'Se muestra como: © ${DateTime.now().year} <este texto>',
              icono: Icons.copyright,
            ),
          ),
          derecha: CfgVistaPrevia(
            child: CfgPreviewPie(derechos: _footerDerechosCtrl, nombre: _nombreNegocioCtrl),
          ),
        ),
      ];

  Future<void> _mostrarFormFicha({int? indice}) async {
    final existente = indice != null ? _contenidoEdit.historiaFichas[indice] : null;
    final ficha = await mostrarDialogoFicha(context, existente: existente);
    if (ficha == null || !mounted) return;
    setState(() {
      if (indice == null) {
        _contenidoEdit.historiaFichas.add(ficha);
      } else {
        _contenidoEdit.historiaFichas[indice] = ficha;
      }
    });
  }

  Future<void> _mostrarFormServicio({int? indice}) async {
    final existente = indice != null ? _contenidoEdit.servicios[indice] : null;
    final servicio = await mostrarDialogoServicio(context, existente: existente);
    if (servicio == null || !mounted) return;
    setState(() {
      if (indice == null) {
        _contenidoEdit.servicios.add(servicio);
      } else {
        _contenidoEdit.servicios[indice] = servicio;
      }
    });
  }

  Future<void> _mostrarFormSeccionLegal({int? indice}) async {
    final existente = indice != null ? _contenidoEdit.avisoLegalSecciones[indice] : null;
    final seccion = await mostrarDialogoSeccionLegal(context, existente: existente);
    if (seccion == null || !mounted) return;
    setState(() {
      if (indice == null) {
        _contenidoEdit.avisoLegalSecciones.add(seccion);
      } else {
        _contenidoEdit.avisoLegalSecciones[indice] = seccion;
      }
    });
  }
}
