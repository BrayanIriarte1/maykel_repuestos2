import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_service.dart';
import '../config.dart';
import '../models.dart';
import '../utils/format.dart';
import '../utils/pdf_report.dart';
import 'efectos.dart';

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

class _InventarioAdminState extends State<InventarioAdmin> {
  static const _porPagina = 25;

  static const _filtros = <(String, String, IconData)>[
    ('', 'Todos', Icons.apps),
    ('agotado', 'Agotados', Icons.remove_shopping_cart_outlined),
    ('bajo', 'Stock bajo', Icons.warning_amber_rounded),
    ('sinprecio', 'Sin precio', Icons.money_off),
    ('sinfoto', 'Sin foto', Icons.hide_image_outlined),
    ('OCULTO', 'Ocultos', Icons.visibility_off_outlined),
  ];

  final _busquedaCtrl = TextEditingController();
  Timer? _debounce;
  Timer? _auto;

  String _q = '';
  String _categoria = '';
  String _filtro = '';
  int _pagina = 1;
  int _total = 0;
  List<Repuesto> _items = [];
  List<String> _categorias = [];
  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  EstadoInventario? _estado;
  DateTime? _ultimaCarga;

  // Cambios sin guardar: id -> (precio, stock). Sobreviven al cambiar de página.
  final Map<int, ({int precio, int stock})> _pendientes = {};
  final Map<int, TextEditingController> _ctrlPrecio = {};
  final Map<int, TextEditingController> _ctrlStock = {};

  int get _paginas => (_total / _porPagina).ceil().clamp(1, 1000000);

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarCategorias();
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

  bool get _escribiendo {
    final foco = FocusManager.instance.primaryFocus;
    return foco != null && foco.context?.widget is EditableText;
  }

  void _refrescoAutomatico() {
    if (!mounted || _cargando || _guardando || _pendientes.isNotEmpty || _escribiendo) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    _cargar(silencioso: true);
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
        _error = e.toString();
        _cargando = false;
      });
    }
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

  void _irAPagina(int p) {
    if (p < 1 || p > _paginas || p == _pagina) return;
    setState(() => _pagina = p);
    _cargar();
  }

  // ---------- Edición en línea ----------

  TextEditingController _controlador(Map<int, TextEditingController> mapa, int id, String inicial) =>
      mapa.putIfAbsent(id, () => TextEditingController(text: inicial));

  void _alEditar(Repuesto p) {
    final precio = int.tryParse(_ctrlPrecio[p.id]?.text ?? '') ?? p.precio.round();
    final stock = int.tryParse(_ctrlStock[p.id]?.text ?? '') ?? p.stock.round();
    setState(() {
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
      _aviso('$n producto${n == 1 ? '' : 's'} actualizado${n == 1 ? '' : 's'}.');
    } catch (e) {
      _aviso('No se pudo guardar: $e', error: true);
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
      _aviso('Foto de "${p.nombre}" actualizada.');
    } catch (e) {
      _aviso('$e', error: true);
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
      _aviso(ocultar ? 'Producto oculto del catálogo.' : 'Producto publicado.');
    } catch (e) {
      _aviso('$e', error: true);
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
      _aviso('No se pudo generar el PDF: $e', error: true);
    }
  }

  // ---------- Interfaz ----------

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _barraSuperior(),
        const SizedBox(height: 12),
        _filtrosFila(),
        const SizedBox(height: 10),
        _estadoFila(),
        const SizedBox(height: 8),
        if (_cargando)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          _bloqueError()
        else if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 50),
            child: Center(
                child: Text('No hay productos con esos filtros.',
                    style: TextStyle(color: AppColors.steel))),
          )
        else ...[
          ..._items.map(_fila),
          const SizedBox(height: 10),
          _paginador(),
        ],
      ],
    );
  }

  Widget _barraSuperior() {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 340,
          child: TextField(
            controller: _busquedaCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar por nombre, SKU o categoría',
              isDense: true,
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _busquedaCtrl.clear();
                        _aplicarFiltros(q: '');
                      },
                    ),
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () => _aplicarFiltros(q: v));
            },
          ),
        ),
        SizedBox(
          width: 230,
          child: DropdownButtonFormField<String>(
            initialValue: _categoria.isEmpty || !_categorias.contains(_categoria) ? '' : _categoria,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, labelText: 'Categoría'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Todas')),
              ..._categorias.map((c) => DropdownMenuItem(
                  value: c, child: Text(c, overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (v) => _aplicarFiltros(categoria: v ?? ''),
          ),
        ),
        if (widget.editable)
          OutlinedButton.icon(
            onPressed: () => _dialogoProducto(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nuevo producto'),
          ),
        OutlinedButton.icon(
          onPressed: _pdf,
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('PDF'),
        ),
        if (widget.editable && _pendientes.isNotEmpty) ...[
          TextButton(onPressed: _guardando ? null : _descartar, child: const Text('Descartar')),
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 18),
            label: Text('Guardar ${_pendientes.length} cambio${_pendientes.length == 1 ? '' : 's'}'),
          ),
        ],
      ],
    );
  }

  Widget _filtrosFila() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in _filtros)
          ChoiceChip(
            avatar: Icon(f.$3, size: 16, color: _filtro == f.$1 ? Colors.white : AppColors.steel),
            label: Text(f.$2),
            selected: _filtro == f.$1,
            selectedColor: AppColors.red,
            labelStyle: TextStyle(
                color: _filtro == f.$1 ? Colors.white : AppColors.char,
                fontWeight: FontWeight.w600,
                fontSize: 12.5),
            showCheckmark: false,
            onSelected: (_) => _aplicarFiltros(filtro: f.$1),
          ),
      ],
    );
  }

  Widget _estadoFila() {
    final e = _estado;
    final alerta = e?.desactualizado ?? false;
    final color = e == null ? AppColors.steel : (alerta ? AppColors.warn : AppColors.ok);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('$_total producto${_total == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.sync, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                e == null
                    ? 'Estado de sincronización desconocido'
                    : 'Sincronizado ${EstadoInventario.textoHace(e.haceSegundos)}'
                        '${alerta ? ' — revisa el agente de sincronización' : ''}',
                style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ]),
            if (_ultimaCarga != null)
              Text(
                'Lista actualizada ${_hora(_ultimaCarga!)}',
                style: const TextStyle(color: AppColors.steel, fontSize: 12),
              ),
            InkWell(
              onTap: _cargando ? null : () => _cargar(),
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.refresh, size: 18, color: AppColors.steel),
              ),
            ),
          ],
        ),
        if (widget.editable)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Precio y stock se actualizan solos desde el sistema del cliente cada 30 minutos: '
              'un cambio manual puede ser reemplazado en la próxima sincronización.',
              style: TextStyle(color: AppColors.steel, fontSize: 11.5),
            ),
          ),
      ],
    );
  }

  String _hora(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  Widget _bloqueError() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('No se pudo cargar: $_error', style: const TextStyle(color: AppColors.bad)),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ]),
        ),
      );

  Widget _paginador() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
            tooltip: 'Primera',
            onPressed: _pagina > 1 ? () => _irAPagina(1) : null,
            icon: const Icon(Icons.first_page)),
        IconButton(
            tooltip: 'Anterior',
            onPressed: _pagina > 1 ? () => _irAPagina(_pagina - 1) : null,
            icon: const Icon(Icons.chevron_left)),
        Text('Página $_pagina de $_paginas',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        IconButton(
            tooltip: 'Siguiente',
            onPressed: _pagina < _paginas ? () => _irAPagina(_pagina + 1) : null,
            icon: const Icon(Icons.chevron_right)),
        IconButton(
            tooltip: 'Última',
            onPressed: _pagina < _paginas ? () => _irAPagina(_paginas) : null,
            icon: const Icon(Icons.last_page)),
      ],
    );
  }

  Widget _miniatura(Repuesto p) {
    final url = p.imagenAbsoluta;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 58,
        height: 58,
        color: AppColors.paper2,
        child: url == null
            ? Icon(iconoCategoria(p.categoria), color: AppColors.steel)
            : Image.network(url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image_outlined, color: AppColors.steel)),
      ),
    );
  }

  Widget _campoNumero(TextEditingController c, String etiqueta, bool cambiado, VoidCallback alCambiar,
      {double ancho = 104}) {
    return SizedBox(
      width: ancho,
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => alCambiar(),
        decoration: InputDecoration(
          isDense: true,
          labelText: etiqueta,
          filled: cambiado,
          fillColor: const Color(0xFFFFF4D6),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cambiado ? AppColors.warn : AppColors.paper2),
          ),
        ),
      ),
    );
  }

  Widget _chip(String texto, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(texto,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
      );

  Widget _fila(Repuesto p) {
    final pend = _pendientes[p.id];
    final stockVisible = pend?.stock ?? p.stock.round();
    final Color colorStock = stockVisible <= 0
        ? AppColors.bad
        : stockVisible <= 3
            ? AppColors.warn
            : AppColors.ok;
    final textoStock = stockVisible <= 0 ? 'Agotado' : stockVisible <= 3 ? 'Stock bajo' : 'Disponible';

    return Container(
      key: ValueKey(p.id),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: pend != null ? AppColors.warn : AppColors.paper2),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _miniatura(p),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 220, maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                const SizedBox(height: 3),
                Text('${p.sku} · ${p.categoria}${p.marca.isNotEmpty && p.marca != 'General' ? ' · ${p.marca}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.steel, fontSize: 11.5)),
                const SizedBox(height: 5),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  _chip(textoStock, colorStock),
                  if (p.oculto) _chip('OCULTO', AppColors.steel),
                  if (p.estadoCatalogo == 'PENDIENTE') _chip('PENDIENTE', AppColors.warn),
                  if (p.precio <= 0) _chip('SIN PRECIO', AppColors.bad),
                  if (p.imagenUrl == null) _chip('SIN FOTO', AppColors.steel),
                ]),
              ],
            ),
          ),
          if (widget.editable) ...[
            _campoNumero(
              _controlador(_ctrlPrecio, p.id, '${pend?.precio ?? p.precio.round()}'),
              'Precio',
              pend != null && pend.precio != p.precio.round(),
              () => _alEditar(p),
              ancho: 118,
            ),
            _campoNumero(
              _controlador(_ctrlStock, p.id, '${pend?.stock ?? p.stock.round()}'),
              'Stock',
              pend != null && pend.stock != p.stock.round(),
              () => _alEditar(p),
              ancho: 92,
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: p.imagenUrl == null ? 'Subir foto' : 'Cambiar foto',
                onPressed: () => _subirFoto(p),
                icon: Icon(p.imagenUrl == null ? Icons.add_photo_alternate_outlined : Icons.image_outlined,
                    size: 20),
              ),
              IconButton(
                tooltip: 'Editar producto',
                onPressed: () => _dialogoProducto(p: p),
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                tooltip: p.oculto ? 'Publicar en el catálogo' : 'Ocultar del catálogo',
                onPressed: () => _alternarVisibilidad(p),
                icon: Icon(p.oculto ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 20, color: p.oculto ? AppColors.ok : AppColors.steel),
              ),
            ]),
          ] else ...[
            _dato('Precio', formatCLP(p.precio)),
            _dato('Stock', '${p.stock}'),
          ],
        ],
      ),
    );
  }

  Widget _dato(String etiqueta, String valor) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: const TextStyle(color: AppColors.steel, fontSize: 11)),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      );
}
