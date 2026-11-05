import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_service.dart';
import '../config.dart';
import '../models.dart';
import '../widgets/admin_login_dialog.dart';
import '../widgets/carrusel_productos.dart';
import '../widgets/efectos.dart';
import '../widgets/mapa_ubicacion.dart';
import '../widgets/product_card.dart';
import '../widgets/reserva_dialog.dart';
import 'aviso_legal_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _historiaKey = GlobalKey();
  final _serviciosKey = GlobalKey();
  final _catalogoKey = GlobalKey();
  final _contactoKey = GlobalKey();
  final _scrollController = ScrollController();
  final _busquedaCtrl = TextEditingController();

  List<Repuesto> _productos = []; // pool para carruseles y hero
  bool _cargando = true;
  String? _error;

  // Catálogo paginado desde el servidor
  List<Repuesto> _items = [];
  int _total = 0;
  int _totalGeneral = 0;
  int _pagina = 1;
  bool _cargandoCat = false;
  bool _cargandoMas = false;
  String? _errorCat;
  static const _porPagina = 24;

  String _busqueda = '';
  String? _marca;
  String? _modelo;
  String? _categoria;
  bool _soloDisponibles = false;
  List<(String, int)> _marcas = [];
  List<(String, int)> _modelos = [];
  List<String> _categoriasLista = [];
  Timer? _debounce;
  Timer? _autoRefresco;
  EstadoInventario? _estadoInv;
  bool _refrescando = false;

  @override
  void initState() {
    super.initState();
    _cargarProductos();
    _cargarContenido();
    _cargarEstado();
    // El stock cambia con cada sincronización (cada 30 min) y con cada venta:
    // el catálogo se actualiza solo cada 2 minutos mientras la pestaña esté abierta.
    _autoRefresco = Timer.periodic(const Duration(minutes: 2), (_) => _refrescarSilencioso());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _autoRefresco?.cancel();
    _scrollController.dispose();
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarEstado() async {
    try {
      final e = await ApiService.instance.getEstadoInventario();
      if (mounted) setState(() => _estadoInv = e);
    } catch (_) {
      // El indicador es informativo: si falla simplemente no se muestra.
    }
  }

  /// Vuelve a pedir lo que se está viendo, sin spinners ni perder la posición.
  Future<void> _refrescarSilencioso({bool avisar = false}) async {
    if (_refrescando || _cargandoCat || _cargandoMas) return;
    setState(() => _refrescando = true);
    try {
      final estado = await ApiService.instance.getEstadoInventario();
      final r = await ApiService.instance.getRepuestosPagina(
        buscar: _busqueda.trim(),
        categoria: _categoria,
        marca: _marca,
        modelo: _modelo,
        soloDisponibles: _soloDisponibles,
        pagina: 1,
        limite: (_pagina * _porPagina).clamp(_porPagina, 200),
      );
      final pool = await ApiService.instance.getRepuestosPagina(limite: 200, soloDisponibles: true);
      if (!mounted) return;
      setState(() {
        _estadoInv = estado;
        _items = r.items;
        _total = r.total;
        _productos = pool.items;
      });
      if (avisar) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inventario actualizado.'), duration: Duration(seconds: 2)),
        );
      }
    } catch (_) {
      if (avisar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo actualizar. Revisa tu conexión.')),
        );
      }
    } finally {
      if (mounted) setState(() => _refrescando = false);
    }
  }

  Future<void> _cargarProductos() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final pool = await ApiService.instance
          .getRepuestosPagina(limite: 200, soloDisponibles: true);
      if (!mounted) return;
      setState(() {
        _productos = pool.items;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
    _cargarFiltros();
    _buscarCatalogo();
  }

  Future<void> _cargarFiltros() async {
    try {
      final f = await ApiService.instance.getFiltrosCatalogo(marca: _marca);
      final cats = await ApiService.instance.getCategorias();
      if (!mounted) return;
      setState(() {
        _marcas = f.marcas;
        _modelos = f.modelos;
        _categoriasLista = cats;
      });
    } catch (_) {
      // Los filtros son opcionales: si fallan, el catálogo sigue con búsqueda por texto.
    }
  }

  Future<void> _buscarCatalogo({bool mas = false}) async {
    if (mas) {
      setState(() => _cargandoMas = true);
    } else {
      setState(() {
        _cargandoCat = true;
        _errorCat = null;
        _pagina = 1;
      });
    }
    try {
      final r = await ApiService.instance.getRepuestosPagina(
        buscar: _busqueda.trim(),
        categoria: _categoria,
        marca: _marca,
        modelo: _modelo,
        soloDisponibles: _soloDisponibles,
        pagina: mas ? _pagina + 1 : 1,
        limite: _porPagina,
      );
      if (!mounted) return;
      setState(() {
        if (mas) {
          _pagina++;
          _items = [..._items, ...r.items];
        } else {
          _items = r.items;
        }
        _total = r.total;
        if (_busqueda.trim().isEmpty &&
            _marca == null &&
            _modelo == null &&
            _categoria == null &&
            !_soloDisponibles) {
          _totalGeneral = r.total;
        }
        _cargandoCat = false;
        _cargandoMas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCat = e.toString();
        _cargandoCat = false;
        _cargandoMas = false;
      });
    }
  }

  void _filtrar(VoidCallback cambio, {bool recargarFiltros = false}) {
    setState(cambio);
    _buscarCatalogo();
    if (recargarFiltros) _cargarFiltros();
  }

  Future<void> _cargarContenido() async {
    try {
      final contenido = await ApiService.instance.getContenido();
      if (!mounted) return;
      setState(() => SiteContent.actual = contenido);
    } catch (_) {
      // Si falla, el sitio sigue mostrando el contenido de referencia
      // (SiteContent.actual ya trae ContenidoSitio.porDefecto() por defecto).
    }
  }

  /// Reparte los productos entre categorías para que el carrusel no sea monótono.
  List<Repuesto> _variados(Iterable<Repuesto> origen, int max) {
    final porCat = <String, List<Repuesto>>{};
    for (final p in origen) {
      porCat.putIfAbsent(p.categoria, () => []).add(p);
    }
    final listas = porCat.values.toList();
    final res = <Repuesto>[];
    for (var i = 0; res.length < max; i++) {
      var agregado = false;
      for (final l in listas) {
        if (i < l.length && res.length < max) {
          res.add(l[i]);
          agregado = true;
        }
      }
      if (!agregado) break;
    }
    return res;
  }

  List<Repuesto> get _destacados =>
      _variados(_productos.where((p) => p.stock > 3), 12);

  List<Repuesto> get _ultimas =>
      _variados(_productos.where((p) => p.stock > 0 && p.stock <= 3), 12);

  void _irAMarca(String marca) {
    _filtrar(() {
      _marca = marca;
      _modelo = null;
      _modelos = [];
    }, recargarFiltros: true);
    _scrollA(_catalogoKey);
  }

  void _irACategoria(String categoria) {
    _filtrar(() => _categoria = categoria);
    _scrollA(_catalogoKey);
  }

  Widget _chipMarca(String nombre, int total, {bool oscuro = false}) {
    return HoverLift(
      onTap: () => _irAMarca(nombre),
      builder: (_, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: hover ? AppColors.red : (oscuro ? Colors.white10 : Colors.white),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: hover ? AppColors.red : AppColors.paper2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.directions_car_filled_outlined,
              size: 16, color: hover ? Colors.white : AppColors.red),
          const SizedBox(width: 8),
          Text(nombre,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: hover ? Colors.white : (oscuro ? Colors.white : AppColors.char))),
          const SizedBox(width: 8),
          Text('$total',
              style: TextStyle(
                  fontSize: 12, color: hover ? Colors.white70 : AppColors.steel)),
        ]),
      ),
    );
  }

  List<(String, int)> get _marcasTop {
    final l = [..._marcas]..sort((a, b) => b.$2.compareTo(a.$2));
    return l.take(14).toList();
  }

  /// Franja "Compra por marca": accesos directos al filtro del catálogo.
  Widget _buildMarcasRapidas(bool esAngosto) {
    if (_marcasTop.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: EdgeInsets.symmetric(
          horizontal: _padX(esAngosto), vertical: esAngosto ? 30 : 44),
      child: Centrado(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TituloSeccion(
                kicker: 'Encuentra el tuyo', titulo: 'Compra por marca de vehículo'),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _marcasTop.map((m) => _chipMarca(m.$1, m.$2)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  static const _iconosCategoria = <String, IconData>{
    'aceite': Icons.oil_barrel_outlined,
    'filtro': Icons.filter_alt_outlined,
    'freno': Icons.disc_full_outlined,
    'bater': Icons.battery_charging_full,
    'luz': Icons.lightbulb_outline,
    'faro': Icons.lightbulb_outline,
    'suspens': Icons.height,
    'amortig': Icons.height,
    'motor': Icons.settings_outlined,
    'correa': Icons.sync,
    'bujía': Icons.flash_on_outlined,
    'bujia': Icons.flash_on_outlined,
    'refriger': Icons.ac_unit,
    'radiador': Icons.ac_unit,
    'embrague': Icons.settings_applications_outlined,
    'rodam': Icons.circle_outlined,
    'neum': Icons.tire_repair,
    'electric': Icons.electrical_services,
    'escobill': Icons.cleaning_services_outlined,
    'espejo': Icons.flip,
  };

  IconData _iconoCategoria(String nombre) {
    final n = nombre.toLowerCase();
    for (final e in _iconosCategoria.entries) {
      if (n.contains(e.key)) return e.value;
    }
    return Icons.build_circle_outlined;
  }

  /// Cuadrícula "Explora por categoría".
  Widget _buildCategoriasRapidas(bool esAngosto) {
    final cats = _categoriasLista
        .where((c) => c.trim().isNotEmpty && c.length <= 26)
        .take(12)
        .toList();
    if (cats.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppColors.paper,
      padding: EdgeInsets.symmetric(
          horizontal: _padX(esAngosto), vertical: esAngosto ? 36 : 56),
      child: Centrado(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TituloSeccion(kicker: 'Todo para tu vehículo', titulo: 'Explora por categoría'),
            const SizedBox(height: 22),
            LayoutBuilder(builder: (context, c) {
              final cols = esAngosto ? 2 : (c.maxWidth / 200).floor().clamp(3, 6);
              const gap = 14.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: cats
                    .map((cat) => SizedBox(
                          width: w,
                          child: HoverLift(
                            onTap: () => _irACategoria(cat),
                            builder: (_, hover) => AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
                              decoration: BoxDecoration(
                                color: hover ? AppColors.char : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(hover ? 0.18 : 0.06),
                                      blurRadius: hover ? 18 : 8,
                                      offset: const Offset(0, 4))
                                ],
                              ),
                              child: Column(children: [
                                Icon(_iconoCategoria(cat),
                                    size: 34,
                                    color: hover ? AppColors.yellow : AppColors.red),
                                const SizedBox(height: 10),
                                Text(cat,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: hover ? Colors.white : AppColors.char)),
                              ]),
                            ),
                          ),
                        ))
                    .toList(),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Panel lateral de "Últimas unidades": urgencia + acceso al catálogo.
  Widget _panelUltimas() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.red, Color(0xFF7A1A22)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department, color: AppColors.yellow, size: 40),
          const SizedBox(height: 12),
          const Text('¡Quedan pocas!',
              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text(
              'Reserva online tu repuesto y retíralo en tienda antes de que se agote.',
              style: TextStyle(color: Colors.white70, height: 1.5)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => _scrollA(_catalogoKey),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellow,
              foregroundColor: AppColors.char,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: const Text('Ver catálogo completo'),
          ),
        ],
      ),
    );
  }

  void _scrollA(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    }
  }

  Future<void> _abrirAdmin() async {
    final ok = ApiService.instance.sesionAdminActiva || await mostrarLoginAdmin(context) == true;
    if (ok && mounted) {
      await Navigator.of(context).pushNamed('/admin');
      _cargarProductos();
    }
  }

  void _abrirReserva(Repuesto p) {
    mostrarDialogoReserva(context, p, _cargarProductos);
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final esAngosto = ancho < 760;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            launchUrl(Uri.parse('https://wa.me/${SiteContent.actual.contactoWhatsapp}')),
        backgroundColor: const Color(0xFF25D366),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.chat_bubble_outline),
        label: esAngosto ? const SizedBox.shrink() : const Text('Escríbenos'),
      ),
      body: Column(
        children: [
          _buildNavbar(esAngosto),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  _buildHero(esAngosto),
                  if (!_cargando && _error == null)
                    SeccionCarrusel(
                      kicker: 'Lo más buscado',
                      titulo: 'Productos destacados',
                      productos: _destacados,
                      onReservar: _abrirReserva,
                    ),
                  _buildMarcasRapidas(esAngosto),
                  Container(key: _historiaKey, child: _buildHistoria(esAngosto)),
                  Container(key: _serviciosKey, child: _buildServicios(esAngosto)),
                  if (!_cargando && _error == null)
                    SeccionCarrusel(
                      kicker: 'No te quedes sin ellos',
                      titulo: 'Últimas unidades',
                      productos: _ultimas,
                      onReservar: _abrirReserva,
                      oscuro: true,
                      lateral: esAngosto ? null : _panelUltimas(),
                    ),
                  _buildCategoriasRapidas(esAngosto),
                  Container(key: _catalogoKey, child: _buildCatalogo(esAngosto)),
                  Container(key: _contactoKey, child: _buildContacto(esAngosto)),
                  _buildFooter(esAngosto),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _padX(bool esAngosto) => esAngosto ? 20 : 60;

  // ---------- Navbar ----------

  Widget _buildNavbar(bool esAngosto) {
    return Material(
      color: AppColors.char,
      elevation: 6,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: esAngosto ? 16 : 40, vertical: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/images/logo_maykel.jpg',
                  height: esAngosto ? 38 : 46, fit: BoxFit.contain),
            ),
            const Spacer(),
            if (!esAngosto) ...[
              _navLink('Historia', () => _scrollA(_historiaKey)),
              _navLink('Servicios', () => _scrollA(_serviciosKey)),
              _navLink('Catálogo', () => _scrollA(_catalogoKey)),
              _navLink('Contacto', () => _scrollA(_contactoKey)),
              const SizedBox(width: 12),
            ],
            OutlinedButton.icon(
              onPressed: _abrirAdmin,
              icon: const Icon(Icons.lock_outline, size: 16),
              label: const Text('Admin'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navLink(String texto, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(foregroundColor: Colors.white70),
        child: Text(texto, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ---------- Hero ----------

  Widget _buildHero(bool esAngosto) {
    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.red.withOpacity(0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.red.withOpacity(0.5)),
          ),
          child: const Text('CALAMA · REGIÓN DE ANTOFAGASTA',
              style: TextStyle(
                  color: AppColors.yellow,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
        ),
        const SizedBox(height: 18),
        Text(
          SiteContent.actual.heroTitulo,
          style: TextStyle(
            color: Colors.white,
            fontSize: esAngosto ? 34 : 54,
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            SiteContent.actual.heroSubtitulo,
            style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.55),
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton.icon(
              onPressed: () => _scrollA(_catalogoKey),
              icon: const Icon(Icons.search, size: 18),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              label: Text(SiteContent.actual.heroBotonCatalogo),
            ),
            OutlinedButton(
              onPressed: () => _scrollA(_contactoKey),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: Text(SiteContent.actual.heroBotonContacto),
            ),
          ],
        ),
        const SizedBox(height: 36),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            _statHero(_totalGeneral > 0 ? '$_totalGeneral' : '${_productos.length}', SiteContent.actual.heroEstadisticaProductosEtiqueta),
            _statHero(_marcas.isNotEmpty ? '${_marcas.length}+' : SiteContent.actual.heroEstadisticaMarcasValor,
                SiteContent.actual.heroEstadisticaMarcasEtiqueta),
            _statHero(SiteContent.actual.heroEstadisticaCategoriasValor,
                SiteContent.actual.heroEstadisticaCategoriasEtiqueta),
          ],
        ),
      ],
    );

    final destacados = _productos.where((p) => p.stock > 0).take(5).toList();
    final carrusel = (!_cargando && destacados.isNotEmpty)
        ? HeroCarrusel(productos: destacados, onReservar: _abrirReserva)
        : const SizedBox.shrink();

    return Container(
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A1C), Color(0xFF2B1013), Color(0xFF1A1A1C)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -120,
            top: -120,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.red.withOpacity(0.12),
              ),
            ),
          ),
          Positioned(
            left: -80,
            bottom: -140,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.03),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: _padX(esAngosto), vertical: esAngosto ? 40 : 80),
            child: Centrado(
              child: esAngosto
                  ? Column(children: [textos, const SizedBox(height: 32), carrusel])
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 6, child: textos),
                        const SizedBox(width: 48),
                        Expanded(flex: 5, child: carrusel),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statHero(String numero, String etiqueta) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(numero,
              style: const TextStyle(
                  color: AppColors.yellow, fontSize: 28, fontWeight: FontWeight.w900)),
          Text(etiqueta, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      ),
    );
  }

  // ---------- Historia ----------

  static const _iconosFicha = [
    Icons.place_outlined,
    Icons.storefront_outlined,
    Icons.stars_outlined,
    Icons.calendar_month_outlined,
    Icons.support_agent_outlined,
  ];

  Widget _buildHistoria(bool esAngosto) {
    final fichas = SiteContent.actual.historiaFichas;
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: EdgeInsets.symmetric(
          horizontal: _padX(esAngosto), vertical: esAngosto ? 40 : 70),
      child: Centrado(
        child: Flex(
          direction: esAngosto ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: esAngosto ? 0 : 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TituloSeccion(
                      kicker: SiteContent.actual.historiaKicker,
                      titulo: SiteContent.actual.historiaTitulo),
                  const SizedBox(height: 22),
                  Text(
                    SiteContent.actual.historiaTexto,
                    style: const TextStyle(color: AppColors.steel, fontSize: 15, height: 1.75),
                  ),
                ],
              ),
            ),
            SizedBox(width: esAngosto ? 0 : 48, height: esAngosto ? 28 : 0),
            Expanded(
              flex: esAngosto ? 0 : 5,
              child: Column(
                children: [
                  for (var i = 0; i < fichas.length; i++)
                    _filaFicha(_iconosFicha[i % _iconosFicha.length], fichas[i].etiqueta,
                        fichas[i].valor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaFicha(IconData icono, String etiqueta, String valor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.paper2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icono, color: AppColors.red, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(etiqueta.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.8,
                        color: AppColors.steel,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(valor,
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.char, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Servicios ----------

  static const _iconosServicio = [
    Icons.directions_car_filled_outlined,
    Icons.engineering_outlined,
    Icons.picture_as_pdf_outlined,
    Icons.build_outlined,
    Icons.local_shipping_outlined,
    Icons.verified_outlined,
  ];

  Widget _buildServicios(bool esAngosto) {
    final servicios = SiteContent.actual.servicios;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A1C), Color(0xFF242427)],
        ),
      ),
      padding: EdgeInsets.symmetric(
          horizontal: _padX(esAngosto), vertical: esAngosto ? 40 : 70),
      child: Centrado(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TituloSeccion(
                kicker: SiteContent.actual.serviciosKicker,
                titulo: SiteContent.actual.serviciosTitulo,
                oscuro: true),
            const SizedBox(height: 32),
            LayoutBuilder(builder: (context, c) {
              final cols = esAngosto ? 1 : (c.maxWidth > 900 ? 4 : 2);
              const gap = 18.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < servicios.length; i++)
                    SizedBox(
                      width: w,
                      child: HoverLift(
                        builder: (context, hover) => AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          height: 190,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: hover ? const Color(0xFF2E2E32) : AppColors.char2,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: hover ? AppColors.red : Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.red,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(_iconosServicio[i % _iconosServicio.length],
                                    color: Colors.white, size: 22),
                              ),
                              const SizedBox(height: 14),
                              Text(servicios[i].titulo,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15.5)),
                              const SizedBox(height: 6),
                              Expanded(
                                child: Text(servicios[i].descripcion,
                                    overflow: TextOverflow.fade,
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 13, height: 1.5)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  // ---------- Catálogo ----------

  Widget _buildCatalogo(bool esAngosto) {
    return Container(
      width: double.infinity,
      color: AppColors.paper,
      padding: EdgeInsets.symmetric(
          horizontal: _padX(esAngosto), vertical: esAngosto ? 40 : 70),
      child: Centrado(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TituloSeccion(
                kicker: SiteContent.actual.catalogoKicker,
                titulo: SiteContent.actual.catalogoTitulo),
            const SizedBox(height: 26),
            Material(
              elevation: 3,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(30),
              child: TextField(
                controller: _busquedaCtrl,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: AppColors.red),
                  hintText: SiteContent.actual.catalogoBusquedaHint,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) {
                  _busqueda = v;
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), _buscarCatalogo);
                },
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Búsquedas rápidas:',
                    style: TextStyle(color: AppColors.steel, fontSize: 12.5)),
                for (final s in const ['Filtro de aceite', 'Pastillas de freno', 'Bujías', 'Amortiguador', 'Batería', 'Correa'])
                  ActionChip(
                    label: Text(s, style: const TextStyle(fontSize: 12.5)),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.paper2),
                    onPressed: () {
                      _busqueda = s;
                      _busquedaCtrl.text = s;
                      _buscarCatalogo();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _buildFiltros(),
            const SizedBox(height: 14),
            _indicadorInventario(),
            if (!_cargandoCat && _errorCat == null) ...[
              const SizedBox(height: 6),
              Text('$_total producto${_total == 1 ? '' : 's'}',
                  style: const TextStyle(color: AppColors.steel, fontSize: 12.5)),
            ],
            const SizedBox(height: 18),
            if (_cargandoCat)
              const Center(
                  child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(),
              ))
            else if (_errorCat != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Text('No se pudo cargar el catálogo: $_errorCat',
                    style: const TextStyle(color: AppColors.bad)),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Text('No encontramos repuestos que coincidan con tu búsqueda.',
                    style: TextStyle(color: AppColors.steel)),
              )
            else ...[
              LayoutBuilder(builder: (context, c) {
                final cols = esAngosto ? 1 : (c.maxWidth / 270).floor().clamp(2, 6);
                const gap = 18.0;
                final w = (c.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: _items
                      .map((p) => SizedBox(
                            width: w,
                            child: ProductCard(
                              producto: p,
                              onReservar: () => _abrirReserva(p),
                            ),
                          ))
                      .toList(),
                );
              }),
              if (_items.length < _total) ...[
                const SizedBox(height: 26),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _cargandoMas ? null : () => _buscarCatalogo(mas: true),
                    icon: _cargandoMas
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.expand_more),
                    label: Text('Ver más (${_total - _items.length} restantes)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _indicadorInventario() {
    final e = _estadoInv;
    final alerta = e?.desactualizado ?? false;
    final color = e == null ? AppColors.steel : (alerta ? AppColors.warn : AppColors.ok);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Text(
          e == null
              ? 'Consultando inventario…'
              : 'Inventario actualizado ${EstadoInventario.textoHace(e.haceSegundos)} · '
                  '${e.disponibles} disponibles de ${e.total}',
          style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _refrescando ? null : () => _refrescarSilencioso(avisar: true),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: _refrescando
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 17, color: AppColors.steel),
          ),
        ),
      ],
    );
  }

  Widget _desplegable({
    required String etiqueta,
    required String? valor,
    required List<DropdownMenuItem<String?>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return SizedBox(
      width: 230,
      child: DropdownButtonFormField<String?>(
        value: valor,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: etiqueta,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.paper2),
          ),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  /// Filtro jerárquico: Marca -> Modelo, más categoría y disponibilidad.
  Widget _buildFiltros() {
    final hayFiltros = _marca != null || _modelo != null || _categoria != null || _soloDisponibles;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _desplegable(
          etiqueta: 'Marca del vehículo',
          valor: _marca,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Todas las marcas')),
            ..._marcas.map((m) =>
                DropdownMenuItem<String?>(value: m.$1, child: Text('${m.$1} (${m.$2})'))),
          ],
          onChanged: (v) => _filtrar(() {
            _marca = v;
            _modelo = null;
            _modelos = [];
          }, recargarFiltros: true),
        ),
        _desplegable(
          etiqueta: 'Modelo',
          valor: _modelos.any((m) => m.$1 == _modelo) ? _modelo : null,
          items: [
            DropdownMenuItem<String?>(
                value: null,
                child: Text(_marca == null ? 'Elige una marca' : 'Todos los modelos')),
            ..._modelos.map((m) =>
                DropdownMenuItem<String?>(value: m.$1, child: Text('${m.$1} (${m.$2})'))),
          ],
          onChanged: _marca == null ? (_) {} : (v) => _filtrar(() => _modelo = v),
        ),
        _desplegable(
          etiqueta: 'Categoría',
          valor: _categoria,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Todas las categorías')),
            ..._categoriasLista
                .map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
          ],
          onChanged: (v) => _filtrar(() => _categoria = v),
        ),
        FilterChip(
          label: const Text('Solo con stock'),
          selected: _soloDisponibles,
          selectedColor: AppColors.red.withOpacity(0.15),
          checkmarkColor: AppColors.red,
          onSelected: (v) => _filtrar(() => _soloDisponibles = v),
        ),
        if (hayFiltros)
          TextButton.icon(
            onPressed: () => _filtrar(() {
              _marca = null;
              _modelo = null;
              _categoria = null;
              _soloDisponibles = false;
              _modelos = [];
            }, recargarFiltros: true),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Limpiar filtros'),
          ),
      ],
    );
  }

  // ---------- Contacto ----------

  Widget _buildContacto(bool esAngosto) {
    final tarjetas = <(IconData, String, String, VoidCallback?)>[
      (Icons.chat_outlined, 'WhatsApp', '+${SiteContent.actual.contactoWhatsapp}',
          () => launchUrl(Uri.parse('https://wa.me/${SiteContent.actual.contactoWhatsapp}'))),
      (Icons.mail_outline, 'Correo', SiteContent.actual.contactoEmail,
          () => launchUrl(Uri.parse('mailto:${SiteContent.actual.contactoEmail}'))),
      (Icons.place_outlined, 'Dirección', SiteContent.actual.contactoDireccion,
          () => launchUrl(Uri.parse(SiteContent.actual.contactoMapsUrl))),
      (Icons.schedule_outlined, 'Horario', SiteContent.actual.contactoHorario, null),
    ];

    return Container(
      width: double.infinity,
      color: AppColors.char2,
      padding: EdgeInsets.symmetric(
          horizontal: _padX(esAngosto), vertical: esAngosto ? 40 : 70),
      child: Centrado(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TituloSeccion(
                kicker: SiteContent.actual.contactoKicker,
                titulo: SiteContent.actual.contactoTitulo,
                oscuro: true),
            const SizedBox(height: 28),
            LayoutBuilder(builder: (context, c) {
              final cols = esAngosto ? 1 : (c.maxWidth > 900 ? 4 : 2);
              const gap = 16.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: tarjetas.map((t) => _tarjetaContacto(t, w)).toList(),
              );
            }),
            const SizedBox(height: 28),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: MapaUbicacion(
                consulta: SiteContent.actual.contactoDireccion,
                alto: esAngosto ? 260 : 380,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaContacto((IconData, String, String, VoidCallback?) t, double ancho) {
    return SizedBox(
      width: ancho,
      child: HoverLift(
        onTap: t.$4,
        builder: (context, hover) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 118,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.char,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: hover && t.$4 != null ? AppColors.red : Colors.white12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(t.$1, color: AppColors.yellow, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.$2,
                        style: const TextStyle(
                            color: AppColors.yellow, fontWeight: FontWeight.w800, fontSize: 12)),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Text(t.$3,
                          overflow: TextOverflow.fade,
                          style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Footer ----------

  Widget _buildFooter(bool esAngosto) {
    return Container(
      width: double.infinity,
      color: AppColors.char,
      padding: EdgeInsets.symmetric(horizontal: esAngosto ? 20 : 60, vertical: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/images/logo_maykel.jpg', height: 56, fit: BoxFit.contain),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              InkWell(
                onTap: () =>
                    launchUrl(Uri.parse('https://wa.me/${SiteContent.actual.contactoWhatsapp}')),
                child: Text('WhatsApp: +${SiteContent.actual.contactoWhatsapp}',
                    style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
              ),
              InkWell(
                onTap: () => launchUrl(Uri.parse('mailto:${SiteContent.actual.contactoEmail}')),
                child: Text(SiteContent.actual.contactoEmail,
                    style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
              ),
              InkWell(
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AvisoLegalScreen())),
                child: const Text('Aviso legal',
                    style: TextStyle(color: Colors.white60, fontSize: 12.5)),
              ),
              InkWell(
                onTap: _abrirAdmin,
                child: const Text('Acceso administrador',
                    style: TextStyle(color: Colors.white60, fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Â© ${DateTime.now().year} ${SiteContent.actual.footerDerechos}',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}
