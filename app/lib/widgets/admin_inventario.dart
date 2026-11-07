import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_service.dart';
import '../config.dart';
import '../models.dart';
import '../utils/format.dart';
import '../utils/pdf_report.dart';
import 'admin_ui.dart';
import 'diseno.dart';
import 'efectos.dart';
import 'portada_extra.dart';

/// Catálogo / stock del panel admin. Los datos se piden por páginas al
/// servidor (hay miles de productos), con búsqueda y filtros en el servidor,
/// y solo se guardan las filas que realmente se modificaron. La lista se
/// refresca sola cada minuto para reflejar lo que trae la sincronización.
class InventarioAdmin extends StatefulWidget {
  /// Con false es una vista de solo lectura (rol con permiso "catalogo" pero sin "stock").
  final bool editable;
  final VoidCallback? onCambio;

  const InventarioAdmin({super.key, required this.editable, this.onCambio});

  @override
  State<InventarioAdmin> createState() => _InventarioAdminState();
}

class _Filtro {
  final String id;
  final String etiqueta;
  final IconData icono;
  final List<Color> colores;
  const _Filtro(this.id, this.etiqueta, this.icono, this.colores);
}

const _grises = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
]);

const _fondoCampo = Color(0xFFF7F4EE);
const _fondoPendiente = Color(0xFFFFF4D6);
const _colorEsqueleto = Color(0xFFEAE5DB);

String _miles(int n) => formatCLP(n).replaceFirst('\$', '');

class _InventarioAdminState extends State<InventarioAdmin> {
  static const _porPaginaCuadricula = 24;
  static const _porPaginaLista = 30;
  static const _stockBajoMax = 3;
  static const _stockNivelLleno = 20;
  static const _altoCuerpoTarjeta = 212.0;
  static const _anchoAcciones = 196.0;

  static const _filtros = <_Filtro>[
    _Filtro('', 'Total', Icons.inventory_2_outlined, AdminColores.azul),
    _Filtro('disponible', 'Disponibles', Icons.check_circle_outline, AdminColores.verde),
    _Filtro('bajo', 'Stock bajo', Icons.warning_amber_rounded, AdminColores.ambar),
    _Filtro('agotado', 'Agotados', Icons.remove_shopping_cart_outlined, AdminColores.rojo),
    _Filtro('sinprecio', 'Sin precio', Icons.money_off, AdminColores.violeta),
    _Filtro('sinfoto', 'Sin foto', Icons.hide_image_outlined, [Color(0xFF22B8CF), Color(0xFF0E7490)]),
    _Filtro('OCULTO', 'Ocultos', Icons.visibility_off_outlined, AdminColores.gris),
  ];

  final _busquedaCtrl = TextEditingController();
  final _claveResultados = GlobalKey();
  Timer? _debounce;
  Timer? _auto;
  int _ticks = 0;

  String _q = '';
  String _categoria = '';
  String _filtro = '';
  bool _lista = false;
  int _pagina = 1;
  int _total = 0;
  List<Repuesto> _items = [];
  List<String> _categorias = [];
  bool _cargando = true;
  bool _guardando = false;
  bool _cargandoContadores = false;
  String? _error;
  EstadoInventario? _estado;
  DateTime? _ultimaCarga;
  final Map<String, int> _contadores = {};

  // Cambios sin guardar: id -> (precio, stock). Sobreviven al cambiar de página.
  final Map<int, ({int precio, int stock})> _pendientes = {};
  final Map<int, TextEditingController> _ctrlPrecio = {};
  final Map<int, TextEditingController> _ctrlStock = {};
  // Guardado individual: filas en curso y resultado reciente (true = guardado, false = falló).
  final Set<int> _guardandoFila = {};
  final Map<int, bool> _resultados = {};

  int get _porPagina => _lista ? _porPaginaLista : _porPaginaCuadricula;
  int get _paginas => (_total / _porPagina).ceil().clamp(1, 1000000);

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarCategorias();
    _cargarContadores();
    _auto = Timer.periodic(const Duration(seconds: 60), (_) => _refrescoAutomatico());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _auto?.cancel();
    _busquedaCtrl.dispose();
    _liberarControladores(inmediato: true);
    super.dispose();
  }

  void _liberarControladores({bool inmediato = false}) {
    final viejos = [..._ctrlPrecio.values, ..._ctrlStock.values];
    _ctrlPrecio.clear();
    _ctrlStock.clear();
    void soltar() {
      for (final c in viejos) {
        c.dispose();
      }
    }

    // Se liberan después del siguiente cuadro: los campos aún los usan mientras se reconstruyen.
    inmediato ? soltar() : WidgetsBinding.instance.addPostFrameCallback((_) => soltar());
  }

  Future<void> _cargarCategorias() async {
    try {
      final c = await ApiService.instance.getCategorias();
      if (mounted) setState(() => _categorias = c);
    } catch (_) {}
  }

  Future<int?> _contar(_Filtro f) async {
    try {
      final r = await ApiService.instance.getRepuestosAdmin(
        estado: f.id == 'OCULTO' ? 'OCULTO' : '',
        stock: f.id == 'OCULTO' ? '' : f.id,
        limite: 1,
      );
      return r.total;
    } catch (_) {
      return null;
    }
  }

  /// Contadores de las tarjetas de resumen: consultas de una sola fila (solo
  /// interesa el total), sin filtros de búsqueda ni de categoría.
  Future<void> _cargarContadores() async {
    if (_cargandoContadores) return;
    _cargandoContadores = true;
    try {
      final r = await Future.wait(_filtros.map(_contar));
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _filtros.length; i++) {
          final n = r[i];
          if (n != null) _contadores[_filtros[i].id] = n;
        }
      });
    } finally {
      _cargandoContadores = false;
    }
  }

  bool get _escribiendo {
    final foco = FocusManager.instance.primaryFocus;
    return foco != null && foco.context?.widget is EditableText;
  }

  void _refrescoAutomatico() {
    if (!mounted || _cargando || _guardando || _pendientes.isNotEmpty || _escribiendo) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    _cargar(silencioso: true);
    if (++_ticks % 3 == 0) _cargarContadores();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final r = await ApiService.instance.getRepuestosAdmin(
        q: _q,
        categoria: _categoria,
        estado: _filtro == 'OCULTO' ? 'OCULTO' : '',
        stock: _filtro == 'OCULTO' ? '' : _filtro,
        pagina: _pagina,
        limite: _porPagina,
      );
      EstadoInventario? estado;
      try {
        estado = await ApiService.instance.getEstadoInventario();
      } catch (_) {}
      if (!mounted) return;
      // Si el filtro dejó menos páginas que la actual, vuelve a la última.
      if (r.items.isEmpty && r.total > 0 && _pagina > 1) {
        _pagina = (r.total / _porPagina).ceil();
        await _cargar(silencioso: silencioso);
        return;
      }
      setState(() {
        _liberarControladores();
        _items = r.items;
        _total = r.total;
        _estado = estado ?? _estado;
        _ultimaCarga = DateTime.now();
        _cargando = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (silencioso) return;
      setState(() {
        _error = _msg(e);
        _cargando = false;
      });
    }
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  void _actualizarTodo() {
    _cargar();
    _cargarContadores();
  }

  void _aplicarFiltros({String? q, String? categoria, String? filtro}) {
    setState(() {
      if (q != null) _q = q;
      if (categoria != null) _categoria = categoria;
      if (filtro != null) _filtro = filtro;
      _pagina = 1;
    });
    _cargar();
  }

  void _limpiarFiltros() {
    _debounce?.cancel();
    _busquedaCtrl.clear();
    _aplicarFiltros(q: '', categoria: '', filtro: '');
  }

  bool get _hayFiltros => _q.isNotEmpty || _categoria.isNotEmpty || _filtro.isNotEmpty;

  void _irAPagina(int p) {
    if (p < 1 || p > _paginas || p == _pagina) return;
    setState(() => _pagina = p);
    _cargar();
    final ctx = _claveResultados.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          alignment: 0.02, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
  }

  void _cambiarVista(bool lista) {
    if (lista == _lista) return;
    final primero = (_pagina - 1) * _porPagina;
    setState(() {
      _lista = lista;
      _pagina = primero ~/ _porPagina + 1;
    });
    _cargar();
  }

  // ---------- Edición en línea ----------

  TextEditingController _controlador(Map<int, TextEditingController> mapa, int id, String inicial) =>
      mapa.putIfAbsent(id, () => TextEditingController(text: inicial));

  void _alEditar(Repuesto p) {
    final precio = int.tryParse(_ctrlPrecio[p.id]?.text ?? '') ?? p.precio.round();
    final stock = int.tryParse(_ctrlStock[p.id]?.text ?? '') ?? p.stock.round();
    setState(() {
      _resultados.remove(p.id);
      if (precio == p.precio.round() && stock == p.stock.round()) {
        _pendientes.remove(p.id);
      } else {
        _pendientes[p.id] = (precio: precio, stock: stock);
      }
    });
  }

  void _descartar() {
    setState(_pendientes.clear);
    _cargar();
  }

  void _marcarResultado(int id, bool ok) {
    if (!mounted) return;
    setState(() => _resultados[id] = ok);
    Timer(const Duration(seconds: 3), () {
      if (mounted && _resultados[id] == ok) setState(() => _resultados.remove(id));
    });
  }

  Future<void> _guardarFila(Repuesto p) async {
    final pend = _pendientes[p.id];
    if (pend == null || _guardandoFila.contains(p.id)) return;
    setState(() {
      _guardandoFila.add(p.id);
      _resultados.remove(p.id);
    });
    try {
      await ApiService.instance.guardarCambiosStock([
        <String, num>{'id': p.id, 'precio': pend.precio, 'stock': pend.stock}
      ]);
      _pendientes.remove(p.id);
      await _cargar(silencioso: true);
      _marcarResultado(p.id, true);
      widget.onCambio?.call();
      unawaited(_cargarContadores());
    } catch (e) {
      _marcarResultado(p.id, false);
      _aviso('No se pudo guardar "${p.nombre}": ${_msg(e)}', error: true);
    } finally {
      if (mounted) setState(() => _guardandoFila.remove(p.id));
    }
  }

  Future<void> _guardar() async {
    if (_pendientes.isEmpty) return;
    setState(() => _guardando = true);
    try {
      final cambios = _pendientes.entries
          .map((e) => <String, num>{'id': e.key, 'precio': e.value.precio, 'stock': e.value.stock})
          .toList();
      for (var i = 0; i < cambios.length; i += 500) {
        await ApiService.instance.guardarCambiosStock(
            cambios.sublist(i, i + 500 > cambios.length ? cambios.length : i + 500));
      }
      final n = cambios.length;
      _pendientes.clear();
      await _cargar();
      widget.onCambio?.call();
      unawaited(_cargarContadores());
      _aviso('$n producto${n == 1 ? '' : 's'} actualizado${n == 1 ? '' : 's'}.');
    } catch (e) {
      _aviso('No se pudo guardar: ${_msg(e)}', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _aviso(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? AppColors.bad : null,
    ));
  }

  // ---------- Acciones por producto ----------

  Future<void> _subirFoto(Repuesto p) async {
    final sel = await FilePicker.pickFiles(type: FileType.image);
    if (sel.isEmpty) return;
    final archivo = sel.first;
    final ext = (archivo.extension ?? '').toLowerCase();
    final tipo = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
    try {
      final bytes = await archivo.readAsBytes();
      if (bytes.length > 3 * 1024 * 1024) {
        _aviso('La imagen supera los 3 MB. Usa una más liviana.', error: true);
        return;
      }
      await ApiService.instance.subirImagenRepuesto(p.id, bytes, tipo);
      await _cargar(silencioso: true);
      widget.onCambio?.call();
      unawaited(_cargarContadores());
      _aviso('Foto de "${p.nombre}" actualizada.');
    } catch (e) {
      _aviso(_msg(e), error: true);
    }
  }

  Future<void> _alternarVisibilidad(Repuesto p) async {
    final ocultar = !p.oculto;
    if (ocultar) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Ocultar producto'),
          content: Text('"${p.nombre}" dejará de verse en el catálogo público. '
              'Puedes volver a publicarlo cuando quieras.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ocultar')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await ApiService.instance
          .editarProducto(p.id, {'estado_catalogo': ocultar ? 'OCULTO' : 'PUBLICADO'});
      await _cargar(silencioso: true);
      widget.onCambio?.call();
      unawaited(_cargarContadores());
      _aviso(ocultar ? 'Producto oculto del catálogo.' : 'Producto publicado.');
    } catch (e) {
      _aviso(_msg(e), error: true);
    }
  }

  Future<void> _dialogoProducto({Repuesto? p}) async {
    final nombre = TextEditingController(text: p?.nombre ?? '');
    final sku = TextEditingController();
    final categoria = TextEditingController(text: p?.categoria ?? '');
    final marca = TextEditingController(text: p?.marca == 'General' ? '' : (p?.marca ?? ''));
    final modelo = TextEditingController(
        text: (p?.modelo == 'Compatible' || p?.modelo == 'General') ? '' : (p?.modelo ?? ''));
    final precio = TextEditingController(text: '${p?.precio.round() ?? 0}');
    final stock = TextEditingController(text: '${p?.stock.round() ?? 0}');
    String? error;
    var guardando = false;
    var publicado = p == null || p.estadoCatalogo == 'PUBLICADO';

    await showDialog<void>(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(p == null ? 'Nuevo producto' : 'Editar producto'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: nombre,
                      maxLength: 180,
                      decoration: const InputDecoration(labelText: 'Nombre *', counterText: '')),
                  const SizedBox(height: 10),
                  if (p == null) ...[
                    TextField(
                        controller: sku,
                        decoration: const InputDecoration(
                            labelText: 'SKU / código (opcional, se genera solo)')),
                    const SizedBox(height: 10),
                  ],
                  Autocomplete<String>(
                    initialValue: TextEditingValue(text: categoria.text),
                    optionsBuilder: (v) => v.text.isEmpty
                        ? const Iterable<String>.empty()
                        : _categorias
                            .where((c) => c.toLowerCase().contains(v.text.toLowerCase()))
                            .take(8),
                    onSelected: (v) => categoria.text = v,
                    fieldViewBuilder: (c, ctrl, foco, _) => TextField(
                      controller: ctrl,
                      focusNode: foco,
                      onChanged: (v) => categoria.text = v,
                      decoration: const InputDecoration(labelText: 'Categoría'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: marca,
                            decoration: const InputDecoration(labelText: 'Marca del vehículo'))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextField(
                            controller: modelo,
                            decoration: const InputDecoration(labelText: 'Modelo'))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: precio,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'Precio (CLP)'))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextField(
                            controller: stock,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'Stock'))),
                  ]),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: publicado,
                    activeThumbColor: AppColors.red,
                    title: const Text('Visible en el catálogo público'),
                    onChanged: (v) => setD(() => publicado = v),
                  ),
                  if (error != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(error!, style: const TextStyle(color: AppColors.bad, fontSize: 12.5)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Cancelar')),
            FilledButton(
              onPressed: guardando
                  ? null
                  : () async {
                      if (nombre.text.trim().isEmpty) {
                        setD(() => error = 'El nombre es obligatorio.');
                        return;
                      }
                      setD(() {
                        guardando = true;
                        error = null;
                      });
                      try {
                        final pr = int.tryParse(precio.text) ?? 0;
                        final st = int.tryParse(stock.text) ?? 0;
                        if (p == null) {
                          final nuevo = await ApiService.instance.crearProducto(
                            nombre: nombre.text.trim(),
                            sku: sku.text.trim(),
                            categoria: categoria.text.trim(),
                            marca: marca.text.trim(),
                            modelo: modelo.text.trim(),
                            precio: pr,
                            stock: st,
                          );
                          if (!publicado) {
                            await ApiService.instance
                                .editarProducto(nuevo.id, {'estado_catalogo': 'OCULTO'});
                          }
                        } else {
                          await ApiService.instance.editarProducto(p.id, {
                            'nombre': nombre.text.trim(),
                            'categoria': categoria.text.trim(),
                            'marca': marca.text.trim(),
                            'modelo': modelo.text.trim(),
                            'precio': pr,
                            'stock': st,
                            'estado_catalogo': publicado ? 'PUBLICADO' : 'OCULTO',
                          });
                        }
                        if (dc.mounted) Navigator.pop(dc);
                        await _cargar(silencioso: true);
                        widget.onCambio?.call();
                        unawaited(_cargarContadores());
                        _aviso(p == null ? 'Producto creado.' : 'Producto actualizado.');
                      } catch (e) {
                        setD(() {
                          guardando = false;
                          error = '$e';
                        });
                      }
                    },
              child: Text(p == null ? 'Crear' : 'Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pdf() async {
    _aviso('Preparando el PDF (máx. 500 productos del filtro actual)…');
    try {
      final filas = <List<String>>[];
      for (var pg = 1; pg <= 3 && filas.length < 500; pg++) {
        final r = await ApiService.instance.getRepuestosAdmin(
          q: _q,
          categoria: _categoria,
          estado: _filtro == 'OCULTO' ? 'OCULTO' : '',
          stock: _filtro == 'OCULTO' ? '' : _filtro,
          pagina: pg,
          limite: 200,
        );
        filas.addAll(r.items.map((p) => [
              p.sku,
              p.nombre,
              p.categoria,
              '${p.marca} ${p.modelo}'.trim(),
              formatCLP(p.precio),
              '${p.stock}',
            ]));
        if (r.items.length < 200) break;
      }
      await generarReportePdf(
        titulo: 'Reporte de Stock',
        columnas: const ['SKU', 'Nombre', 'Categoría', 'Marca / Modelo', 'Precio', 'Stock'],
        filas: filas.take(500).toList(),
      );
    } catch (e) {
      _aviso('No se pudo generar el PDF: ${_msg(e)}', error: true);
    }
  }

  // ---------- Utilidades de presentación ----------

  ({String texto, Color color, IconData icono}) _estadoStock(int stock) {
    if (stock <= 0) {
      return (texto: 'Agotado', color: AppColors.bad, icono: Icons.remove_shopping_cart_outlined);
    }
    if (stock <= _stockBajoMax) {
      return (texto: 'Stock bajo', color: AppColors.warn, icono: Icons.warning_amber_rounded);
    }
    return (texto: 'Disponible', color: AppColors.ok, icono: Icons.check_circle_outline);
  }

  List<Widget> _etiquetasExtra(Repuesto p) => [
        if (p.oculto) const PillEstado('Oculto', AppColors.steel, icono: Icons.visibility_off_outlined),
        if (p.estadoCatalogo == 'PENDIENTE')
          const PillEstado('Pendiente', AppColors.warn, icono: Icons.hourglass_bottom_rounded),
        if (p.precio <= 0) const PillEstado('Sin precio', AppColors.bad, icono: Icons.money_off),
        if (p.imagenUrl == null)
          const PillEstado('Sin foto', AppColors.steel, icono: Icons.hide_image_outlined),
      ];

  String _hora(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  int _columnas(double w) => (w / 300).floor().clamp(1, 6);

  // ---------- Interfaz ----------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : MediaQuery.sizeOf(context).width;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _hero(w),
          const SizedBox(height: 16),
          _resumen(w),
          const SizedBox(height: 16),
          if (widget.editable) ...[_avisoSincronizacion(), const SizedBox(height: 16)],
          _barraHerramientas(w),
          const SizedBox(height: 14),
          _barraCambios(),
          KeyedSubtree(key: _claveResultados, child: _cuerpo(w)),
          if (_error == null && _items.isNotEmpty) ...[const SizedBox(height: 18), _pie(w)],
        ],
      );
    });
  }

  // --- Cabecera ---

  Widget _hero(double w) {
    return AdminHero(
      titulo: widget.editable ? 'Stock y precios' : 'Catálogo de productos',
      subtitulo: widget.editable
          ? 'Edita precio y stock, sube fotos y decide qué productos se publican.'
          : 'Consulta todos los productos del catálogo: publicados, ocultos y pendientes.',
      icono: widget.editable ? Icons.inventory_2_outlined : Icons.menu_book_outlined,
      colores: widget.editable
          ? const [Color(0xFF1A1A1C), Color(0xFF5A0F16)]
          : const [Color(0xFF14213D), Color(0xFF1B4F8A)],
      derecha: w < 720
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              Text(_miles(_total),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, height: 1)),
              const SizedBox(height: 4),
              Text(_hayFiltros ? 'productos en esta vista' : 'productos en total',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
    );
  }

  Widget _resumen(double w) {
    final cols = w >= 1500 ? 7 : w >= 1150 ? 4 : w >= 760 ? 3 : 2;
    const gap = 14.0;
    final ancho = (w - gap * (cols - 1)) / cols;
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [for (final f in _filtros) SizedBox(width: ancho - 0.01, child: _kpi(f))],
    );
  }

  Widget _kpi(_Filtro f) {
    final activo = _filtro == f.id;
    // Con el filtro activo (sin búsqueda ni categoría) el total real es el de la lista.
    final n = activo && _q.isEmpty && _categoria.isEmpty ? _total : _contadores[f.id];
    return _Hover(
      builder: (h) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, h ? -3 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: activo ? f.colores.first : Colors.transparent, width: 2.5),
          boxShadow: activo
              ? [BoxShadow(color: f.colores.first.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))]
              : null,
        ),
        child: Stack(children: [
          KpiTile(
            valor: n == null ? '…' : _miles(n),
            etiqueta: f.etiqueta,
            icono: f.icono,
            colores: f.colores,
            onTap: () => _aplicarFiltros(filtro: f.id),
          ),
          if (activo)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, color: f.colores.first),
                child: const Icon(Icons.check, size: 13, color: Colors.white),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _avisoSincronizacion() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFF6DD), Color(0xFFFFEDBA)]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF3D98A)),
      ),
      child: const Row(children: [
        InsigniaIcono(icono: Icons.sync_rounded, tam: 46, colores: AdminColores.ambar),
        SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Precio y stock se actualizan solos',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: AppColors.char)),
            SizedBox(height: 3),
            Text(
              'El sistema del cliente los sincroniza cada 30 minutos. Si cambias un valor a mano, '
              'puede ser reemplazado en la próxima sincronización.',
              style: TextStyle(fontSize: 13.5, color: AppColors.char2, height: 1.35),
            ),
          ]),
        ),
      ]),
    );
  }

  // --- Barra de herramientas ---

  InputDecoration _decoracionBusqueda() {
    OutlineInputBorder borde(Color color, [double ancho = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color, width: ancho),
        );
    return InputDecoration(
      hintText: 'Buscar por nombre, SKU o categoría…',
      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.steel),
      suffixIcon: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _busquedaCtrl,
        builder: (_, v, __) => v.text.isEmpty
            ? const SizedBox.shrink()
            : IconButton(
                tooltip: 'Limpiar búsqueda',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () {
                  _debounce?.cancel();
                  _busquedaCtrl.clear();
                  _aplicarFiltros(q: '');
                },
              ),
      ),
      filled: true,
      fillColor: _fondoCampo,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: borde(AdminColores.borde),
      enabledBorder: borde(AdminColores.borde),
      focusedBorder: borde(AppColors.red, 1.6),
    );
  }

  Widget _buscador() => TextField(
        controller: _busquedaCtrl,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 15),
        decoration: _decoracionBusqueda(),
        onChanged: (v) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 400), () => _aplicarFiltros(q: v));
        },
        onSubmitted: (v) {
          _debounce?.cancel();
          _aplicarFiltros(q: v);
        },
      );

  Widget _selectorCategoria() {
    final valor = _categoria.isEmpty || !_categorias.contains(_categoria) ? '' : _categoria;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _fondoCampo,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: valor.isEmpty ? AdminColores.borde : AppColors.red.withValues(alpha: 0.6)),
      ),
      child: Row(children: [
        Icon(Icons.category_outlined, size: 20, color: valor.isEmpty ? AppColors.steel : AppColors.red),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: valor,
              isExpanded: true,
              borderRadius: BorderRadius.circular(14),
              icon: const Icon(Icons.expand_more_rounded, color: AppColors.steel),
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.char),
              items: [
                const DropdownMenuItem(value: '', child: Text('Todas las categorías')),
                ..._categorias.map((c) =>
                    DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) => _aplicarFiltros(categoria: v ?? ''),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _selectorVista() {
    Widget boton(bool lista, IconData icono, String tip) {
      final activo = _lista == lista;
      return Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _cambiarVista(lista),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 46,
            height: 44,
            decoration: BoxDecoration(
              color: activo ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: activo
                  ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 8, offset: Offset(0, 2))]
                  : null,
            ),
            child: Icon(icono, size: 22, color: activo ? AppColors.red : AppColors.steel),
          ),
        ),
      );
    }

    return Container(
      height: 54,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: _fondoCampo,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminColores.borde),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        boton(false, Icons.grid_view_rounded, 'Vista de cuadrícula'),
        boton(true, Icons.view_list_rounded, 'Vista de lista'),
      ]),
    );
  }

  List<Widget> _botonesAccion() => [
        OutlinedButton.icon(
          onPressed: _pdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
          label: const Text('PDF'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 54),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            foregroundColor: AppColors.char,
            side: const BorderSide(color: AdminColores.borde, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
        ),
        if (widget.editable)
          FilledButton.icon(
            onPressed: () => _dialogoProducto(),
            icon: const Icon(Icons.add_rounded, size: 22),
            label: const Text('Nuevo producto'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 54),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              elevation: 3,
              shadowColor: AppColors.red.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
            ),
          ),
      ];

  Widget _barraHerramientas(double w) {
    final ancha = w >= 1180;
    final Widget controles;
    if (ancha) {
      controles = Row(children: [
        Expanded(child: _buscador()),
        const SizedBox(width: 12),
        SizedBox(width: 280, child: _selectorCategoria()),
        const SizedBox(width: 12),
        _selectorVista(),
        for (final b in _botonesAccion()) ...[const SizedBox(width: 12), b],
      ]);
    } else {
      controles = Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: w >= 720 ? w - 64 - 12 - 12 - 200 : w - 64, child: _buscador()),
        SizedBox(width: w >= 720 ? 200 : w - 64, child: _selectorCategoria()),
        _selectorVista(),
        ..._botonesAccion(),
      ]);
    }
    return AdminPanel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        controles,
        const SizedBox(height: 12),
        _filaSincronizacion(),
      ]),
    );
  }

  Widget _filaSincronizacion() {
    final e = _estado;
    final alerta = e?.desactualizado ?? false;
    final color = e == null ? AppColors.steel : (alerta ? AppColors.bad : AppColors.ok);
    return Wrap(
      spacing: 18,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 1)],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            e == null
                ? 'Estado de sincronización desconocido'
                : 'Sincronizado con el cliente ${EstadoInventario.textoHace(e.haceSegundos)}'
                    '${alerta ? ' — revisa el agente de sincronización' : ''}',
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ]),
        if (_ultimaCarga != null)
          Text('Lista actualizada a las ${_hora(_ultimaCarga!)}',
              style: const TextStyle(color: AppColors.steel, fontSize: 12.5)),
        TextButton.icon(
          onPressed: _cargando ? null : _actualizarTodo,
          icon: _cargando
              ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Actualizar'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.red,
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _barraCambios() {
    final n = _pendientes.length;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: !widget.editable || n == 0
          ? const SizedBox(width: double.infinity)
          : Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: _fondoPendiente,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.warn.withValues(alpha: 0.6)),
              ),
              child: Wrap(
                spacing: 14,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.edit_note_rounded, color: AppColors.warn, size: 28),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        '$n cambio${n == 1 ? '' : 's'} sin guardar. Guarda cada producto con su botón '
                        'o con Enter, o todos a la vez.',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.char),
                      ),
                    ),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(
                        onPressed: _guardando ? null : _descartar, child: const Text('Descartar')),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _guardando ? null : _guardar,
                      icon: _guardando
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text('Guardar todo ($n)'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.red,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
    );
  }

  // --- Resultados ---

  Widget _cuerpo(double w) {
    if (_error != null) {
      return AdminPanel(
        child: VacioAdmin(
          icono: Icons.cloud_off_rounded,
          titulo: 'No se pudo cargar el inventario',
          texto: _error,
          accion: FilledButton.icon(
            onPressed: _actualizarTodo,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.red),
          ),
        ),
      );
    }
    final cols = _lista ? 1 : _columnas(w);
    if (_cargando && _items.isEmpty) {
      return _Esqueleto(columnas: cols, alto: _lista ? 74 : 380, cantidad: _lista ? 8 : cols * 2);
    }
    if (_items.isEmpty) {
      return AdminPanel(
        child: VacioAdmin(
          icono: _hayFiltros ? Icons.search_off_rounded : Icons.inventory_2_outlined,
          titulo: _hayFiltros ? 'No encontramos productos con esos filtros' : 'Aún no hay productos',
          texto: _hayFiltros
              ? 'Prueba con otra búsqueda, otra categoría o quita los filtros.'
              : 'Cuando se sincronice el inventario o crees un producto, aparecerá aquí.',
          accion: _hayFiltros
              ? OutlinedButton.icon(
                  onPressed: _limpiarFiltros,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Quitar filtros'),
                )
              : null,
        ),
      );
    }
    final contenido = _lista ? _tabla(w) : _cuadricula(w, cols);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 4,
        child: _cargando
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(
                    minHeight: 4, color: AppColors.red, backgroundColor: Color(0x14D91E2B)))
            : null,
      ),
      const SizedBox(height: 10),
      AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _cargando ? 0.45 : 1,
        child: IgnorePointer(ignoring: _cargando, child: contenido),
      ),
    ]);
  }

  Widget _pie(double w) {
    final desde = (_pagina - 1) * _porPagina + 1;
    final hasta = desde + _items.length - 1;
    const base = TextStyle(color: AppColors.steel, fontSize: 13.5);
    const negrita = TextStyle(color: AppColors.char, fontWeight: FontWeight.w800);
    final resumen = Text.rich(TextSpan(style: base, children: [
      const TextSpan(text: 'Mostrando '),
      TextSpan(text: '${_miles(desde)}–${_miles(hasta)}', style: negrita),
      const TextSpan(text: ' de '),
      TextSpan(text: _miles(_total), style: negrita),
      TextSpan(text: ' producto${_total == 1 ? '' : 's'}'),
    ]));
    final paginas = Text('Página $_pagina de $_paginas · $_porPagina por página', style: base);
    final paginador = Paginador(pagina: _pagina, total: _paginas, onPagina: _irAPagina);
    if (w < 900) {
      return Column(children: [paginador, const SizedBox(height: 10), resumen]);
    }
    return Row(children: [
      Expanded(child: Align(alignment: Alignment.centerLeft, child: resumen)),
      paginador,
      Expanded(child: Align(alignment: Alignment.centerRight, child: paginas)),
    ]);
  }

  // --- Vista de cuadrícula ---

  Widget _cuadricula(double w, int cols) {
    const gap = 18.0;
    final anchoTarjeta = (w - gap * (cols - 1)) / cols;
    final fotoAlto = (anchoTarjeta * 0.6).clamp(150.0, 240.0);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      clipBehavior: Clip.none,
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      itemCount: _items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: gap,
        mainAxisSpacing: gap,
        mainAxisExtent: fotoAlto + _altoCuerpoTarjeta,
      ),
      itemBuilder: (_, i) => _tarjeta(_items[i], fotoAlto),
    );
  }

  Widget _sobreFoto(Widget hijo) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: hijo,
      );

  Widget _tarjeta(Repuesto p, double fotoAlto) {
    final pend = _pendientes[p.id];
    final stock = pend?.stock ?? p.stock.round();
    final est = _estadoStock(stock);
    final extras = _etiquetasExtra(p);
    final subtitulo = [
      if (p.categoria.isNotEmpty) p.categoria,
      if (p.marca.isNotEmpty && p.marca != 'General') p.marca,
    ].join(' · ');

    return _Hover(
      key: ValueKey(p.id),
      builder: (h) => AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, h ? -5 : 0, 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: pend != null
                ? AppColors.warn
                : h
                    ? est.color.withValues(alpha: 0.55)
                    : AdminColores.borde,
            width: pend != null ? 1.8 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Color(h ? 0x2A000000 : 0x0F000000),
              blurRadius: h ? 28 : 14,
              offset: Offset(0, h ? 16 : 6),
            ),
          ],
        ),
        child: Column(children: [
          SizedBox(
            height: fotoAlto,
            child: Stack(fit: StackFit.expand, clipBehavior: Clip.hardEdge, children: [
              AnimatedScale(
                scale: h ? 1.05 : 1,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: _FotoProducto(p: p, atenuada: p.oculto),
              ),
              Positioned(
                left: 10,
                top: 10,
                child: _sobreFoto(PillEstado(est.texto, est.color, icono: est.icono)),
              ),
              if (extras.isNotEmpty)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (final e in extras) ...[_sobreFoto(e), const SizedBox(height: 5)],
                  ]),
                ),
              if (esFotoReferencial(p))
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(8)),
                    child: const Text('Foto referencial',
                        style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                  ),
                ),
              if (widget.editable)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Row(mainAxisSize: MainAxisSize.min, children: _acciones(p, sobreFoto: true)),
                ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.sku,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.steel)),
                  const SizedBox(height: 2),
                  Text(p.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.char, height: 1.22)),
                  if (subtitulo.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.steel)),
                  ],
                ]),
                Column(children: [
                  if (widget.editable)
                    Row(children: [
                      Expanded(child: _campo(p, esPrecio: true)),
                      const SizedBox(width: 8),
                      Expanded(child: _campo(p, esPrecio: false)),
                      const SizedBox(width: 8),
                      _botonGuardar(p, tam: 48),
                    ])
                  else
                    Row(children: [
                      Expanded(child: _metrica('Precio', p.precio <= 0 ? 'Sin precio' : formatCLP(p.precio),
                          color: p.precio <= 0 ? AppColors.bad : AppColors.char)),
                      Expanded(child: _metrica('Stock', '$stock un.', color: est.color)),
                    ]),
                  BarraProgreso(
                    etiqueta: 'Nivel de stock',
                    valor: est.texto,
                    fraccion: stock / _stockNivelLleno,
                    color: est.color,
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _metrica(String etiqueta, String valor, {Color color = AppColors.char}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: const TextStyle(color: AppColors.steel, fontSize: 12)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(valor,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color, height: 1.15)),
          ),
        ],
      );

  // --- Campos y acciones compartidos entre vistas ---

  Widget _campo(Repuesto p, {required bool esPrecio, bool compacto = false}) {
    final pend = _pendientes[p.id];
    final ctrl = esPrecio
        ? _controlador(_ctrlPrecio, p.id, '${pend?.precio ?? p.precio.round()}')
        : _controlador(_ctrlStock, p.id, '${pend?.stock ?? p.stock.round()}');
    final cambiado = pend != null && (esPrecio ? pend.precio != p.precio.round() : pend.stock != p.stock.round());
    OutlineInputBorder borde(Color color, [double ancho = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: ancho),
        );
    return TextField(
      controller: ctrl,
      enabled: !_guardandoFila.contains(p.id),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textInputAction: TextInputAction.done,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      onChanged: (_) => _alEditar(p),
      onSubmitted: (_) => _guardarFila(p),
      decoration: InputDecoration(
        isDense: true,
        labelText: compacto ? null : (esPrecio ? 'Precio' : 'Stock'),
        prefixText: esPrecio ? '\$ ' : null,
        suffixText: esPrecio ? null : 'un.',
        filled: true,
        fillColor: cambiado ? _fondoPendiente : _fondoCampo,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: compacto ? 11 : 13),
        border: borde(AdminColores.borde),
        enabledBorder: borde(cambiado ? AppColors.warn : AdminColores.borde, cambiado ? 1.6 : 1),
        focusedBorder: borde(AppColors.red, 1.8),
        disabledBorder: borde(AdminColores.borde),
      ),
    );
  }

  Widget _botonGuardar(Repuesto p, {double tam = 44}) {
    final pend = _pendientes[p.id];
    final guardando = _guardandoFila.contains(p.id);
    final res = _resultados[p.id];
    final Color fondo;
    final Widget icono;
    final String tip;
    final String clave;
    if (guardando) {
      clave = 'guardando';
      fondo = AppColors.red;
      tip = 'Guardando…';
      icono = const SizedBox(
          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white));
    } else if (res == true) {
      clave = 'ok';
      fondo = AppColors.ok;
      tip = 'Guardado';
      icono = const Icon(Icons.check_rounded, color: Colors.white, size: 24);
    } else if (res == false) {
      clave = 'error';
      fondo = AppColors.bad;
      tip = 'No se pudo guardar. Toca para reintentar';
      icono = const Icon(Icons.error_outline_rounded, color: Colors.white, size: 22);
    } else if (pend != null) {
      clave = 'pendiente';
      fondo = AppColors.red;
      tip = 'Guardar cambios (Enter)';
      icono = const Icon(Icons.save_rounded, color: Colors.white, size: 21);
    } else {
      clave = 'sin-cambios';
      fondo = const Color(0xFFEFEBE3);
      tip = 'Sin cambios por guardar';
      icono = const Icon(Icons.check_rounded, color: Color(0xFFB4AFA4), size: 22);
    }
    final activo = !guardando && pend != null;
    return Tooltip(
      message: tip,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Material(
          key: ValueKey(clave),
          color: fondo,
          elevation: activo ? 3 : 0,
          shadowColor: AppColors.red.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: activo ? () => _guardarFila(p) : null,
            child: SizedBox(width: tam, height: tam, child: Center(child: icono)),
          ),
        ),
      ),
    );
  }

  List<Widget> _acciones(Repuesto p, {required bool sobreFoto}) {
    const tam = 38.0;
    return [
      _BotonRedondo(
        icono: p.imagenUrl == null ? Icons.add_photo_alternate_outlined : Icons.image_outlined,
        tooltip: p.imagenUrl == null ? 'Subir foto' : 'Cambiar foto',
        onTap: () => _subirFoto(p),
        sobreFoto: sobreFoto,
        tam: tam,
      ),
      const SizedBox(width: 6),
      _BotonRedondo(
        icono: Icons.edit_outlined,
        tooltip: 'Editar producto',
        onTap: () => _dialogoProducto(p: p),
        sobreFoto: sobreFoto,
        tam: tam,
      ),
      const SizedBox(width: 6),
      _BotonRedondo(
        icono: p.oculto ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        tooltip: p.oculto ? 'Publicar en el catálogo' : 'Ocultar del catálogo',
        color: p.oculto ? AppColors.ok : AppColors.steel,
        onTap: () => _alternarVisibilidad(p),
        sobreFoto: sobreFoto,
        tam: tam,
      ),
    ];
  }

  // --- Vista de lista (tabla) ---

  static const _flexProducto = 5;
  static const _flexCategoria = 3;
  static const _flexEstado = 3;
  static const _flexPrecio = 2;
  static const _flexStock = 2;

  Widget _tabla(double w) {
    final tabla = AdminPanel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(children: [
          _cabeceraTabla(),
          for (var i = 0; i < _items.length; i++) _filaLista(_items[i], i),
        ]),
      ),
    );
    if (w >= 960) return tabla;
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: 960, child: tabla));
  }

  Widget _cabeceraTabla() {
    Widget titulo(String t, int flex) => Expanded(
          flex: flex,
          child: Text(t,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: AppColors.steel)),
        );
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F4EE),
        border: Border(bottom: BorderSide(color: AdminColores.borde, width: 1.5)),
      ),
      child: Row(children: [
        const SizedBox(width: 64),
        titulo('PRODUCTO', _flexProducto),
        titulo('CATEGORÍA / MARCA', _flexCategoria),
        titulo('ESTADO', _flexEstado),
        titulo('PRECIO', _flexPrecio),
        titulo('STOCK', _flexStock),
        if (widget.editable)
          const SizedBox(
            width: _anchoAcciones,
            child: Text('ACCIONES',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: AppColors.steel)),
          ),
      ]),
    );
  }

  Widget _filaLista(Repuesto p, int i) {
    final pend = _pendientes[p.id];
    final stock = pend?.stock ?? p.stock.round();
    final est = _estadoStock(stock);
    final marcaModelo = [
      if (p.marca.isNotEmpty && p.marca != 'General') p.marca,
      if (p.modelo.isNotEmpty && p.modelo != 'Compatible' && p.modelo != 'General') p.modelo,
    ].join(' ');

    return _Hover(
      key: ValueKey(p.id),
      builder: (h) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: pend != null
              ? const Color(0xFFFFF8E6)
              : h
                  ? const Color(0xFFFFF3F1)
                  : (i.isEven ? Colors.white : const Color(0xFFFCFAF6)),
          border: Border(
            left: BorderSide(color: pend != null ? AppColors.warn : Colors.transparent, width: 4),
            bottom: const BorderSide(color: AdminColores.borde),
          ),
        ),
        child: Row(children: [
          SizedBox(
            width: 64,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 50,
                height: 50,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _FotoProducto(p: p, atenuada: p.oculto),
                ),
              ),
            ),
          ),
          Expanded(
            flex: _flexProducto,
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.sku,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: AppColors.steel)),
                Text(p.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.char, height: 1.2)),
              ]),
            ),
          ),
          Expanded(
            flex: _flexCategoria,
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(iconoCategoria(p.categoria), size: 16, color: AppColors.steel),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(p.categoria.isEmpty ? 'Sin categoría' : p.categoria,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.char)),
                  ),
                ]),
                if (marcaModelo.isNotEmpty)
                  Text(marcaModelo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: AppColors.steel)),
              ]),
            ),
          ),
          Expanded(
            flex: _flexEstado,
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 5, runSpacing: 4, children: [
                  PillEstado(est.texto, est.color, icono: est.icono),
                  ..._etiquetasExtra(p),
                ]),
              ),
            ),
          ),
          Expanded(
            flex: _flexPrecio,
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: widget.editable
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 170),
                          child: _campo(p, esPrecio: true, compacto: true)),
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Text(p.precio <= 0 ? 'Sin precio' : formatCLP(p.precio),
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: p.precio <= 0 ? AppColors.bad : AppColors.char)),
                    ),
            ),
          ),
          Expanded(
            flex: _flexStock,
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: widget.editable
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 130),
                          child: _campo(p, esPrecio: false, compacto: true)),
                    )
                  : Row(children: [
                      Text('$stock',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: est.color)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 90),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: (stock / _stockNivelLleno).clamp(0, 1).toDouble(),
                              minHeight: 7,
                              backgroundColor: est.color.withValues(alpha: 0.14),
                              valueColor: AlwaysStoppedAnimation(est.color),
                            ),
                          ),
                        ),
                      ),
                    ]),
            ),
          ),
          if (widget.editable)
            SizedBox(
              width: _anchoAcciones,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                _botonGuardar(p, tam: 40),
                const SizedBox(width: 10),
                ..._acciones(p, sobreFoto: false),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas privadas
// ---------------------------------------------------------------------------

/// Entrega al constructor si el cursor está encima (efectos hover en web/escritorio).
class _Hover extends StatefulWidget {
  final Widget Function(bool hover) builder;
  const _Hover({super.key, required this.builder});

  @override
  State<_Hover> createState() => _HoverState();
}

class _HoverState extends State<_Hover> {
  bool _h = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _h = true),
        onExit: (_) => setState(() => _h = false),
        child: widget.builder(_h),
      );
}

/// Foto del producto (propia o referencial); sin foto, degradado con el ícono de la categoría.
class _FotoProducto extends StatelessWidget {
  final Repuesto p;
  final bool atenuada;
  const _FotoProducto({required this.p, this.atenuada = false});

  @override
  Widget build(BuildContext context) {
    final img = fotoDe(p);
    final fondo = LayoutBuilder(builder: (_, c) {
      final lado = c.biggest.shortestSide.isFinite ? c.biggest.shortestSide : 60.0;
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFFF3EEE4), Color(0xFFD9D1C1)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Center(
          child: Icon(iconoCategoria(p.categoria),
              size: (lado * 0.42).clamp(20.0, 84.0), color: AppColors.steel.withValues(alpha: 0.55)),
        ),
      );
    });
    final Widget foto = img == null
        ? fondo
        : Stack(fit: StackFit.expand, children: [
            fondo,
            Image(
              image: img,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              frameBuilder: (_, hijo, frame, sync) => sync
                  ? hijo
                  : AnimatedOpacity(
                      opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 300), child: hijo),
            ),
          ]);
    return atenuada ? ColorFiltered(colorFilter: _grises, child: foto) : foto;
  }
}

/// Botón circular de acción (foto, editar, ocultar).
class _BotonRedondo extends StatelessWidget {
  final IconData icono;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;
  final bool sobreFoto;
  final double tam;
  const _BotonRedondo({
    required this.icono,
    required this.tooltip,
    required this.onTap,
    required this.sobreFoto,
    required this.tam,
    this.color = AppColors.char,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: sobreFoto ? Colors.white.withValues(alpha: 0.95) : _fondoCampo,
          elevation: sobreFoto ? 3 : 0,
          shape: CircleBorder(side: sobreFoto ? BorderSide.none : const BorderSide(color: AdminColores.borde)),
          child: InkWell(
            customBorder: const CircleBorder(),
            hoverColor: AppColors.red.withValues(alpha: 0.12),
            onTap: onTap,
            child: SizedBox(width: tam, height: tam, child: Icon(icono, size: 19, color: color)),
          ),
        ),
      );
}

/// Marcadores de posición con pulso mientras llega la primera página.
class _Esqueleto extends StatefulWidget {
  final int columnas;
  final double alto;
  final int cantidad;
  const _Esqueleto({required this.columnas, required this.alto, required this.cantidad});

  @override
  State<_Esqueleto> createState() => _EsqueletoState();
}

class _EsqueletoState extends State<_Esqueleto> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _bloque({double? ancho, required double alto}) => Container(
        width: ancho,
        height: alto,
        decoration: BoxDecoration(color: _colorEsqueleto, borderRadius: BorderRadius.circular(8)),
      );

  Widget _item() {
    final decoracion = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AdminColores.borde),
    );
    if (widget.columnas == 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: decoracion,
        child: Row(children: [
          _bloque(ancho: 50, alto: 50),
          const SizedBox(width: 16),
          Expanded(
              flex: 4,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                _bloque(ancho: 90, alto: 10),
                const SizedBox(height: 8),
                _bloque(alto: 14),
              ])),
          const SizedBox(width: 30),
          Expanded(flex: 2, child: _bloque(alto: 14)),
          const SizedBox(width: 30),
          Expanded(flex: 2, child: _bloque(alto: 14)),
          const SizedBox(width: 30),
          Expanded(flex: 1, child: _bloque(alto: 14)),
        ]),
      );
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: decoracion,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(height: widget.alto * 0.45, color: _colorEsqueleto),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _bloque(ancho: 80, alto: 10),
            const SizedBox(height: 10),
            _bloque(alto: 15),
            const SizedBox(height: 8),
            _bloque(ancho: 140, alto: 12),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(child: _bloque(alto: 44)),
              const SizedBox(width: 10),
              Expanded(child: _bloque(alto: 44)),
            ]),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.cantidad,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: widget.columnas,
            crossAxisSpacing: 18,
            mainAxisSpacing: widget.columnas == 1 ? 8 : 18,
            mainAxisExtent: widget.alto,
          ),
          itemBuilder: (_, __) => _item(),
        ),
      );
}
