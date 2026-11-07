import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models.dart';
import 'admin_ui.dart';
import 'portada_extra.dart';

const kEstadosReserva = <String, ({String etiqueta, Color color, IconData icono})>{
  'pendiente': (etiqueta: 'Pendiente', color: Color(0xFFB8860B), icono: Icons.hourglass_top_rounded),
  'confirmada': (etiqueta: 'Por retirar', color: Color(0xFF1565C0), icono: Icons.inventory_outlined),
  'entregada': (etiqueta: 'Entregada', color: Color(0xFF2E7D46), icono: Icons.check_circle_outline),
  'rechazada': (etiqueta: 'Rechazada', color: Color(0xFFB0201F), icono: Icons.cancel_outlined),
};

/// "hace 5 min", "hace 2 h", "ayer"… a partir de una fecha ISO (UTC).
String tiempoRelativo(String iso) {
  final f = DateTime.tryParse(iso)?.toLocal();
  if (f == null) return iso;
  final d = DateTime.now().difference(f);
  if (d.inMinutes < 1) return 'ahora mismo';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  if (d.inDays == 1) return 'ayer';
  if (d.inDays < 30) return 'hace ${d.inDays} días';
  return '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';
}

/// Número en formato internacional para wa.me (Chile por defecto).
String _telWhatsapp(String t) {
  var n = t.replaceAll(RegExp(r'[^0-9]'), '');
  if (n.length == 9 && n.startsWith('9')) n = '56$n';
  if (n.length == 8) n = '569$n';
  return n;
}

/// Acciones disponibles según el estado actual de la reserva.
List<({String estado, String texto, IconData icono, bool principal, bool peligro})> accionesReserva(
    String estado) {
  switch (estado) {
    case 'pendiente':
      return [
        (estado: 'confirmada', texto: 'Confirmar', icono: Icons.check, principal: true, peligro: false),
        (estado: 'rechazada', texto: 'Rechazar', icono: Icons.close, principal: false, peligro: true),
      ];
    case 'confirmada':
      return [
        (estado: 'entregada', texto: 'Marcar entregada', icono: Icons.task_alt, principal: true, peligro: false),
        (estado: 'rechazada', texto: 'Rechazar', icono: Icons.close, principal: false, peligro: true),
      ];
    default:
      return [
        (estado: 'pendiente', texto: 'Reabrir', icono: Icons.undo, principal: false, peligro: false),
      ];
  }
}

// ---------------------------------------------------------------------------
// Utilidades internas
// ---------------------------------------------------------------------------

typedef _Item = ({String sku, String nombre, int cantidad});

const _pagina = 50;
const _horasAviso = 6;
const _horasCritico = 24;

({String etiqueta, Color color, IconData icono}) _estadoDe(String clave) =>
    kEstadosReserva[clave] ?? kEstadosReserva['pendiente']!;

List<_Item> _itemsDe(Reserva r) =>
    r.items.isNotEmpty ? r.items : [(sku: r.sku, nombre: r.producto, cantidad: r.cantidad.toInt())];

int _unidadesDe(Reserva r) => _itemsDe(r).fold(0, (s, i) => s + i.cantidad);

DateTime? _fechaDe(Reserva r) => DateTime.tryParse(r.fecha)?.toLocal();

String _fechaLarga(DateTime? f) {
  if (f == null) return '—';
  String d2(int n) => n.toString().padLeft(2, '0');
  return '${d2(f.day)}/${d2(f.month)}/${f.year} ${d2(f.hour)}:${d2(f.minute)}';
}

/// Urgencia de una reserva pendiente según el tiempo que lleva esperando.
({bool aviso, bool critico}) _urgencia(Reserva r) {
  if (r.estado != 'pendiente') return (aviso: false, critico: false);
  final f = _fechaDe(r);
  if (f == null) return (aviso: false, critico: false);
  final h = DateTime.now().difference(f).inHours;
  return (aviso: h >= _horasAviso && h < _horasCritico, critico: h >= _horasCritico);
}

void _abrirUrl(String url) => launchUrl(Uri.parse(url));

String _mensajeWhatsapp(Reserva r) => 'https://wa.me/${_telWhatsapp(r.telefono)}?text=${Uri.encodeComponent('Hola ${r.nombre}, te escribimos de Maykel Repuestos por tu reserva ${r.id}.')}';

Color _oscuro(Color c) => Color.lerp(c, Colors.black, 0.28)!;

bool _coincide(Reserva r, String q) {
  if (q.isEmpty) return true;
  return r.nombre.toLowerCase().contains(q) ||
      r.id.toLowerCase().contains(q) ||
      r.telefono.contains(q) ||
      r.email.toLowerCase().contains(q) ||
      r.producto.toLowerCase().contains(q) ||
      r.sku.toLowerCase().contains(q) ||
      r.items.any((i) => i.nombre.toLowerCase().contains(q) || i.sku.toLowerCase().contains(q));
}

// ---------------------------------------------------------------------------
// Panel principal
// ---------------------------------------------------------------------------

/// Pestaña Reservas del panel: KPIs por estado que filtran, búsqueda, vista
/// Tablero (Kanban) o Lista, tarjetas con contacto directo y acciones por estado.
class ReservasPanel extends StatefulWidget {
  final List<Reserva> reservas;
  final bool puedeEditar;
  final Future<void> Function(Reserva, String) onCambiarEstado;
  final VoidCallback onPdf;
  final Future<void> Function() onRefrescar;

  const ReservasPanel({
    super.key,
    required this.reservas,
    required this.puedeEditar,
    required this.onCambiarEstado,
    required this.onPdf,
    required this.onRefrescar,
  });

  @override
  State<ReservasPanel> createState() => _ReservasPanelState();
}

class _ReservasPanelState extends State<ReservasPanel> {
  String? _filtro; // null = automático; '' = todas
  bool? _tablero; // null = automático según el ancho de pantalla
  String _q = '';
  int _limiteLista = _pagina;
  final Map<String, int> _limiteCol = {};
  final Set<String> _ocupadas = {};
  final _buscador = TextEditingController();
  bool _refrescando = false;

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  void _reiniciarLimites() {
    _limiteLista = _pagina;
    _limiteCol.clear();
  }

  Future<void> _refrescar() async {
    if (_refrescando) return;
    setState(() => _refrescando = true);
    try {
      await widget.onRefrescar();
    } finally {
      if (mounted) setState(() => _refrescando = false);
    }
  }

  Future<bool> _confirmar(Reserva r, String nuevo) async {
    final est = _estadoDe(nuevo);
    final stockRepone = nuevo == 'rechazada' && (r.estado == 'confirmada' || r.estado == 'entregada');
    late final String titulo;
    late final String texto;
    late final String boton;
    switch (nuevo) {
      case 'confirmada':
        titulo = 'Confirmar reserva';
        texto = 'Se confirmará la reserva ${r.id} de ${r.nombre} y se descontará el stock de los repuestos reservados.';
        boton = 'Confirmar';
      case 'entregada':
        titulo = 'Marcar como entregada';
        texto = 'La reserva ${r.id} de ${r.nombre} se entregó al cliente y quedará registrada como venta.';
        boton = 'Entregada';
      case 'rechazada':
        titulo = 'Rechazar reserva';
        texto = '¿Rechazar la reserva ${r.id} de ${r.nombre}?${stockRepone ? ' Se repondrá el stock.' : ''}';
        boton = 'Rechazar';
      default:
        titulo = 'Reabrir reserva';
        texto = 'La reserva ${r.id} de ${r.nombre} volverá a Pendiente.'
            '${r.estado == 'entregada' ? ' La venta asociada será anulada.' : ''}';
        boton = 'Reabrir';
    }
    final color = nuevo == 'pendiente' ? AppColors.steel : est.color;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        icon: InsigniaIcono(
          icono: nuevo == 'pendiente' ? Icons.undo : est.icono,
          tam: 58,
          colores: [color, _oscuro(color)],
        ),
        title: Text(titulo, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.steel, height: 1.4)),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => Navigator.pop(c, true),
            child: Text(boton),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _cambiar(Reserva r, String estado) async {
    if (!await _confirmar(r, estado) || !mounted) return;
    setState(() => _ocupadas.add(r.id));
    try {
      await widget.onCambiarEstado(r, estado);
    } finally {
      if (mounted) setState(() => _ocupadas.remove(r.id));
    }
  }

  void _verDetalle(Reserva r) {
    showDialog<void>(
      context: context,
      builder: (c) => _DetalleReserva(
        reserva: r,
        puedeEditar: widget.puedeEditar,
        onAccion: (estado) {
          Navigator.pop(c);
          _cambiar(r, estado);
        },
      ),
    );
  }

  void _seleccionar(String clave, String actual) => setState(() {
        _filtro = actual == clave ? '' : clave;
        _reiniciarLimites();
      });

  Widget _tarjeta(Reserva r, {required bool mostrarEstado}) => _TarjetaReserva(
        reserva: r,
        puedeEditar: widget.puedeEditar,
        ocupada: _ocupadas.contains(r.id),
        mostrarEstado: mostrarEstado,
        onAbrir: () => _verDetalle(r),
        onAccion: (estado) => _cambiar(r, estado),
      );

  @override
  Widget build(BuildContext context) {
    final cuentas = <String, int>{for (final k in kEstadosReserva.keys) k: 0};
    var antiguas = 0;
    for (final r in widget.reservas) {
      cuentas[r.estado] = (cuentas[r.estado] ?? 0) + 1;
      if (_urgencia(r).critico) antiguas++;
    }
    final pend = cuentas['pendiente'] ?? 0;
    final tablero = _tablero ?? MediaQuery.sizeOf(context).width >= 1100;
    final filtro = _filtro ?? (!tablero && pend > 0 ? 'pendiente' : '');
    final q = _q.trim().toLowerCase();

    final fechas = <String, DateTime>{
      for (final r in widget.reservas) r.id: _fechaDe(r) ?? DateTime.fromMillisecondsSinceEpoch(0),
    };
    int porFecha(Reserva a, Reserva b) => fechas[b.id]!.compareTo(fechas[a.id]!);
    final grupos = <String, List<Reserva>>{
      for (final k in kEstadosReserva.keys)
        k: widget.reservas.where((r) => r.estado == k && _coincide(r, q)).toList()
          ..sort(k == 'pendiente' ? (a, b) => porFecha(b, a) : porFecha),
    };
    final lista = (filtro.isEmpty ? grupos.values.expand((g) => g).toList() : grupos[filtro] ?? <Reserva>[])
      ..sort((a, b) {
        if (a.estado == 'pendiente' && b.estado != 'pendiente') return -1;
        if (b.estado == 'pendiente' && a.estado != 'pendiente') return 1;
        return a.estado == 'pendiente' ? porFecha(b, a) : porFecha(a, b);
      });

    return LayoutBuilder(builder: (context, c) {
      final ancho = MediaQuery.sizeOf(context).width;
      final pad = ancho >= 900 ? 24.0 : 14.0;
      final altoFijo = c.maxHeight.isFinite;
      final columna = tablero && altoFijo && c.maxHeight >= 820;
      final conHero = !tablero || !altoFijo || c.maxHeight >= 960;
      final maxAncho = tablero ? 2560.0 : 1280.0;

      final cabecera = _cabecera(
        anchoUtil: (c.maxWidth - pad * 2).clamp(0, maxAncho).toDouble(),
        conHero: conHero,
        cuentas: cuentas,
        filtro: filtro,
        antiguas: antiguas,
        tablero: tablero,
      );

      if (columna) {
        return Padding(
          padding: EdgeInsets.fromLTRB(pad, 18, pad, 16),
          child: AdminAncho(
            max: maxAncho,
            child: Column(children: [
              cabecera,
              const SizedBox(height: 14),
              Expanded(child: _vistaTablero(grupos, filtro, q.isNotEmpty)),
            ]),
          ),
        );
      }

      final cuerpo = tablero
          ? SizedBox(height: 640, child: _vistaTablero(grupos, filtro, q.isNotEmpty))
          : _vistaLista(lista, filtro, q.isNotEmpty);
      return RefreshIndicator(
        onRefresh: widget.onRefrescar,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, 18, pad, 28),
          children: [
            AdminAncho(
              max: maxAncho,
              child: Column(children: [cabecera, const SizedBox(height: 14), cuerpo]),
            ),
          ],
        ),
      );
    });
  }

  // ---- Cabecera -------------------------------------------------------------

  Widget _cabecera({
    required double anchoUtil,
    required bool conHero,
    required Map<String, int> cuentas,
    required String filtro,
    required int antiguas,
    required bool tablero,
  }) {
    final pend = cuentas['pendiente'] ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (conHero) ...[
        AdminHero(
          titulo: 'Reservas',
          subtitulo: pend > 0
              ? '$pend reserva${pend == 1 ? '' : 's'} pendiente${pend == 1 ? '' : 's'} por atender · '
                  '${widget.reservas.length} en total'
              : 'Todo al día · ${widget.reservas.length} reserva${widget.reservas.length == 1 ? '' : 's'} en total',
          icono: Icons.event_available_outlined,
        ),
        const SizedBox(height: 14),
      ],
      _kpis(anchoUtil, cuentas, filtro, antiguas),
      const SizedBox(height: 14),
      _barra(anchoUtil, tablero),
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: antiguas > 0 && filtro != 'pendiente'
            ? Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _AvisoAntiguas(
                  cantidad: antiguas,
                  onAtender: () => _seleccionar('pendiente', ''),
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
      if (antiguas > 0 && filtro == 'pendiente')
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _AvisoAntiguas(cantidad: antiguas, onAtender: null),
        ),
    ]);
  }

  Widget _kpis(double ancho, Map<String, int> cuentas, String filtro, int antiguas) {
    final items = <({
      String clave,
      String etiqueta,
      int valor,
      IconData icono,
      List<Color> colores,
      Color color,
      String? nota
    })>[
      (
        clave: 'pendiente',
        etiqueta: 'Pendientes',
        valor: cuentas['pendiente'] ?? 0,
        icono: Icons.hourglass_top_rounded,
        colores: AdminColores.ambar,
        color: _estadoDe('pendiente').color,
        nota: antiguas > 0 ? '$antiguas con más de 24 h' : null,
      ),
      (
        clave: 'confirmada',
        etiqueta: 'Por retirar',
        valor: cuentas['confirmada'] ?? 0,
        icono: Icons.inventory_2_outlined,
        colores: AdminColores.azul,
        color: _estadoDe('confirmada').color,
        nota: null,
      ),
      (
        clave: 'entregada',
        etiqueta: 'Entregadas',
        valor: cuentas['entregada'] ?? 0,
        icono: Icons.task_alt,
        colores: AdminColores.verde,
        color: _estadoDe('entregada').color,
        nota: null,
      ),
      (
        clave: 'rechazada',
        etiqueta: 'Rechazadas',
        valor: cuentas['rechazada'] ?? 0,
        icono: Icons.cancel_outlined,
        colores: AdminColores.rojo,
        color: _estadoDe('rechazada').color,
        nota: null,
      ),
      (
        clave: '',
        etiqueta: 'Total de reservas',
        valor: widget.reservas.length,
        icono: Icons.apps_rounded,
        colores: AdminColores.violeta,
        color: const Color(0xFF5A2FA0),
        nota: null,
      ),
    ];

    if (ancho < 760) {
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in items)
          _ChipKpi(
            etiqueta: k.etiqueta,
            valor: k.valor,
            icono: k.icono,
            color: k.color,
            seleccionado: filtro == k.clave,
            onTap: () => _seleccionar(k.clave, filtro),
          ),
      ]);
    }

    final porFila = ancho >= 1300 ? 5 : 3;
    const gap = 14.0;
    final w = ((ancho - gap * (porFila - 1)) / porFila).floorToDouble();
    return Wrap(spacing: gap, runSpacing: gap, children: [
      for (final k in items)
        SizedBox(
          width: w,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: filtro == k.clave || filtro.isEmpty ? 1 : 0.72,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: filtro == k.clave && k.clave.isNotEmpty ? k.color : Colors.transparent, width: 2.5),
              ),
              child: KpiTile(
                valor: '${k.valor}',
                etiqueta: k.etiqueta,
                icono: k.icono,
                colores: k.colores,
                nota: k.nota,
                onTap: () => _seleccionar(k.clave, filtro),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _barra(double ancho, bool tablero) {
    final buscador = TextField(
      controller: _buscador,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Buscar por cliente, folio, teléfono o producto',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _q.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(() {
                  _buscador.clear();
                  _q = '';
                  _reiniciarLimites();
                }),
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AdminColores.borde),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.red, width: 2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AdminColores.borde),
        ),
      ),
      onChanged: (v) => setState(() {
        _q = v;
        _reiniciarLimites();
      }),
    );

    final conmutador = SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: true, icon: Icon(Icons.view_column_outlined, size: 18), label: Text('Tablero')),
        ButtonSegment(value: false, icon: Icon(Icons.view_agenda_outlined, size: 18), label: Text('Lista')),
      ],
      selected: {tablero},
      style: ButtonStyle(
        visualDensity: VisualDensity.comfortable,
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.char : Colors.white),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.char),
      ),
      onSelectionChanged: (s) => setState(() {
        _tablero = s.first;
        _reiniciarLimites();
      }),
    );

    final pdf = FilledButton.icon(
      onPressed: widget.onPdf,
      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
      label: const Text('PDF'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.red,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );

    final refrescar = IconButton.outlined(
      tooltip: 'Actualizar',
      onPressed: _refrescando ? null : _refrescar,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: AdminColores.borde),
        padding: const EdgeInsets.all(14),
      ),
      icon: _refrescando
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh_rounded),
    );

    if (ancho >= 860) {
      return Row(children: [
        Expanded(child: buscador),
        const SizedBox(width: 12),
        conmutador,
        const SizedBox(width: 12),
        pdf,
        const SizedBox(width: 8),
        refrescar,
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      buscador,
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        conmutador,
        pdf,
        refrescar,
      ]),
    ]);
  }

  // ---- Vista Lista ----------------------------------------------------------

  Widget _vistaLista(List<Reserva> lista, String filtro, bool buscando) {
    if (lista.isEmpty) {
      return AdminPanel(child: _vacio(filtro, buscando));
    }
    final visibles = lista.take(_limiteLista).toList();
    return Column(children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 4),
          child: Text('${lista.length} reserva${lista.length == 1 ? '' : 's'}',
              style: const TextStyle(color: AppColors.steel, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      ),
      for (final r in visibles)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: _tarjeta(r, mostrarEstado: true)),
      if (lista.length > visibles.length)
        Center(
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _limiteLista += _pagina),
            icon: const Icon(Icons.expand_more),
            label: Text('Ver más (${lista.length - visibles.length} restantes)'),
          ),
        ),
    ]);
  }

  Widget _vacio(String filtro, bool buscando) {
    if (buscando) {
      return const VacioAdmin(
        icono: Icons.search_off_rounded,
        titulo: 'Sin coincidencias',
        texto: 'Prueba con otro nombre, folio, teléfono o producto.',
      );
    }
    final (icono, titulo, texto) = _textoVacio(filtro);
    return VacioAdmin(icono: icono, titulo: titulo, texto: texto);
  }

  // ---- Vista Tablero --------------------------------------------------------

  Widget _vistaTablero(Map<String, List<Reserva>> grupos, String filtro, bool buscando) {
    final claves = filtro.isEmpty ? kEstadosReserva.keys.toList() : [filtro];
    return LayoutBuilder(builder: (context, c) {
      const gap = 14.0;
      const minAncho = 290.0;
      Widget columna(String k) => _ColumnaTablero(
            clave: k,
            reservas: grupos[k] ?? const [],
            limite: _limiteCol[k] ?? _pagina,
            cuadricula: claves.length == 1,
            buscando: buscando,
            tarjeta: (r) => _tarjeta(r, mostrarEstado: false),
            onMas: () => setState(() => _limiteCol[k] = (_limiteCol[k] ?? _pagina) + _pagina),
          );

      final n = claves.length;
      if (c.maxWidth >= n * minAncho + gap * (n - 1)) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            Expanded(child: columna(claves[i])),
          ],
        ]);
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          height: c.maxHeight.isFinite ? c.maxHeight : 640,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              SizedBox(width: 310, child: columna(claves[i])),
            ],
          ]),
        ),
      );
    });
  }
}

(IconData, String, String) _textoVacio(String clave) {
  switch (clave) {
    case 'pendiente':
      return (Icons.celebration_outlined, '¡Todo al día!', 'No hay reservas pendientes por atender.');
    case 'confirmada':
      return (Icons.inventory_2_outlined, 'Nada por retirar', 'Las reservas confirmadas aparecerán aquí.');
    case 'entregada':
      return (Icons.local_shipping_outlined, 'Aún sin entregas', 'Las reservas entregadas aparecerán aquí.');
    case 'rechazada':
      return (Icons.thumb_up_alt_outlined, 'Sin rechazadas', 'No hay reservas rechazadas.');
    default:
      return (Icons.event_busy_outlined, 'No hay reservas', 'Cuando un cliente reserve un repuesto lo verás aquí.');
  }
}

// ---------------------------------------------------------------------------
// Piezas de la cabecera
// ---------------------------------------------------------------------------

class _ChipKpi extends StatelessWidget {
  final String etiqueta;
  final int valor;
  final IconData icono;
  final Color color;
  final bool seleccionado;
  final VoidCallback onTap;
  const _ChipKpi({
    required this.etiqueta,
    required this.valor,
    required this.icono,
    required this.color,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: seleccionado ? color : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: seleccionado ? color : AdminColores.borde),
            boxShadow: [BoxShadow(color: color.withValues(alpha: seleccionado ? 0.3 : 0.08), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icono, size: 17, color: seleccionado ? Colors.white : color),
            const SizedBox(width: 6),
            Text('$etiqueta · $valor',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: seleccionado ? Colors.white : AppColors.char)),
          ]),
        ),
      ),
    );
  }
}

class _AvisoAntiguas extends StatelessWidget {
  final int cantidad;
  final VoidCallback? onAtender;
  const _AvisoAntiguas({required this.cantidad, required this.onAtender});

  @override
  Widget build(BuildContext context) {
    const color = AppColors.bad;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.12), const Color(0xFFFFC145).withValues(alpha: 0.14)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.notification_important_rounded, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            cantidad == 1
                ? 'Hay 1 reserva pendiente con más de 24 h sin atender. Respóndela primero.'
                : 'Hay $cantidad reservas pendientes con más de 24 h sin atender. Respóndelas primero.',
            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.char, fontSize: 13.5),
          ),
        ),
        if (onAtender != null) ...[
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onAtender,
            style: FilledButton.styleFrom(
                backgroundColor: color, visualDensity: VisualDensity.compact),
            child: const Text('Atender'),
          ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Columna del tablero
// ---------------------------------------------------------------------------

class _ColumnaTablero extends StatelessWidget {
  final String clave;
  final List<Reserva> reservas;
  final int limite;
  final bool cuadricula;
  final bool buscando;
  final Widget Function(Reserva) tarjeta;
  final VoidCallback onMas;
  const _ColumnaTablero({
    required this.clave,
    required this.reservas,
    required this.limite,
    required this.cuadricula,
    required this.buscando,
    required this.tarjeta,
    required this.onMas,
  });

  @override
  Widget build(BuildContext context) {
    final est = _estadoDe(clave);
    final visibles = reservas.take(limite).toList();
    final restantes = reservas.length - visibles.length;

    final botonMas = restantes > 0
        ? Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Center(
              child: TextButton.icon(
                onPressed: onMas,
                icon: const Icon(Icons.expand_more),
                label: Text('Ver más ($restantes)'),
              ),
            ),
          )
        : null;

    Widget cuerpo;
    if (reservas.isEmpty) {
      final (icono, titulo, texto) =
          buscando ? (Icons.search_off_rounded, 'Sin coincidencias', 'Nada coincide con la búsqueda.') : _textoVacio(clave);
      cuerpo = Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(shape: BoxShape.circle, color: est.color.withValues(alpha: 0.1)),
              child: Icon(icono, size: 30, color: est.color.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 12),
            Text(titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.char)),
            const SizedBox(height: 4),
            Text(texto,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: AppColors.steel)),
          ]),
        ),
      );
    } else if (cuadricula) {
      cuerpo = LayoutBuilder(builder: (context, c) {
        const gap = 12.0;
        final cols = ((c.maxWidth - 24) / 340).floor().clamp(1, 8);
        final w = (c.maxWidth - 24 - gap * (cols - 1)) / cols;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Wrap(spacing: gap, runSpacing: gap, children: [
              for (final r in visibles) SizedBox(width: w, child: tarjeta(r)),
            ]),
            if (botonMas != null) Padding(padding: const EdgeInsets.only(top: 10), child: botonMas),
          ]),
        );
      });
    } else {
      cuerpo = ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: visibles.length + (botonMas != null ? 1 : 0),
        itemBuilder: (context, i) => i < visibles.length
            ? Padding(padding: const EdgeInsets.only(bottom: 12), child: tarjeta(visibles[i]))
            : botonMas!,
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFECE7DE),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AdminColores.borde),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 4, color: est.color),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          color: est.color.withValues(alpha: 0.08),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [est.color, _oscuro(est.color)]),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(est.icono, size: 17, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(est.etiqueta,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.char)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: est.color, borderRadius: BorderRadius.circular(20)),
              child: Text('${reservas.length}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12.5)),
            ),
          ]),
        ),
        Expanded(child: cuerpo),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de reserva
// ---------------------------------------------------------------------------

/// Contenedor con elevación y borde de acento al pasar el cursor.
class _Elevable extends StatefulWidget {
  final Widget child;
  final Color acento;
  final bool destacada;
  final VoidCallback? onTap;
  const _Elevable({required this.child, required this.acento, this.destacada = false, this.onTap});

  @override
  State<_Elevable> createState() => _ElevableState();
}

class _ElevableState extends State<_Elevable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _hover
                  ? widget.acento.withValues(alpha: 0.7)
                  : widget.destacada
                      ? widget.acento.withValues(alpha: 0.55)
                      : AdminColores.borde,
              width: widget.destacada || _hover ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _hover ? widget.acento.withValues(alpha: 0.22) : const Color(0x0F000000),
                blurRadius: _hover ? 22 : 10,
                offset: Offset(0, _hover ? 10 : 4),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String nombre;
  final double tam;
  const _Avatar(this.nombre, {this.tam = 40});

  static const _paleta = [
    AdminColores.azul,
    AdminColores.verde,
    AdminColores.violeta,
    AdminColores.rojo,
    AdminColores.ambar,
    AdminColores.gris,
  ];

  @override
  Widget build(BuildContext context) {
    final n = nombre.trim();
    final colores = _paleta[n.codeUnits.fold<int>(0, (s, c) => s + c) % _paleta.length];
    return Container(
      width: tam,
      height: tam,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: colores, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Text(n.isEmpty ? '?' : n.characters.first.toUpperCase(),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: tam * 0.42)),
    );
  }
}

class _ChipTiempo extends StatelessWidget {
  final Reserva r;
  const _ChipTiempo(this.r);

  @override
  Widget build(BuildContext context) {
    final u = _urgencia(r);
    final color = u.critico ? AppColors.bad : (u.aviso ? const Color(0xFFD98200) : AppColors.steel);
    final destacado = u.critico || u.aviso;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: destacado ? color.withValues(alpha: 0.12) : AppColors.paper,
        borderRadius: BorderRadius.circular(20),
        border: destacado ? Border.all(color: color.withValues(alpha: 0.4)) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(u.critico ? Icons.warning_amber_rounded : Icons.schedule_rounded, size: 13, color: color),
        const SizedBox(width: 4),
        Text(tiempoRelativo(r.fecha),
            style: TextStyle(fontSize: 11.5, fontWeight: destacado ? FontWeight.w800 : FontWeight.w600, color: color)),
      ]),
    );
  }
}

class _ChipRepuesto extends StatelessWidget {
  final _Item item;
  const _ChipRepuesto(this.item);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 5, 10, 5),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.paper2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: AppColors.char, borderRadius: BorderRadius.circular(8)),
          child: Text('×${item.cantidad}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(item.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2)),
            if (item.sku.isNotEmpty)
              Text(item.sku,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: AppColors.steel, fontFamily: 'monospace')),
          ]),
        ),
      ]),
    );
  }
}

/// Pasos Pendiente → Confirmada → Entregada (o Pendiente → Rechazada).
class _LineaEstado extends StatelessWidget {
  final String estado;
  final bool mini;
  const _LineaEstado({required this.estado, this.mini = false});

  @override
  Widget build(BuildContext context) {
    final rechazada = estado == 'rechazada';
    final pasos = rechazada ? ['pendiente', 'rechazada'] : ['pendiente', 'confirmada', 'entregada'];
    const etiquetas = {
      'pendiente': 'Pendiente',
      'confirmada': 'Confirmada',
      'entregada': 'Entregada',
      'rechazada': 'Rechazada',
    };
    final actual = pasos.indexOf(estado).clamp(0, pasos.length - 1);
    final nodo = mini ? 14.0 : 26.0;

    Widget punto(int i) {
      final est = _estadoDe(pasos[i]);
      final hecho = i < actual;
      final activo = i == actual;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: nodo,
          height: nodo,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hecho || activo ? est.color : Colors.white,
            border: Border.all(color: hecho || activo ? est.color : AppColors.paper2, width: 2),
            boxShadow: activo && !mini
                ? [BoxShadow(color: est.color.withValues(alpha: 0.35), blurRadius: 10, spreadRadius: 2)]
                : null,
          ),
          child: mini
              ? null
              : Icon(hecho ? Icons.check_rounded : est.icono,
                  size: 15, color: hecho || activo ? Colors.white : AppColors.paper2),
        ),
        if (!mini) ...[
          const SizedBox(height: 5),
          Text(etiquetas[pasos[i]]!,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: activo ? FontWeight.w900 : FontWeight.w600,
                  color: hecho || activo ? AppColors.char : AppColors.steel)),
        ],
      ]);
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < pasos.length; i++) ...[
        punto(i),
        if (i < pasos.length - 1)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: nodo / 2 - 1, left: 3, right: 3),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 2.5,
                decoration: BoxDecoration(
                  color: i < actual ? _estadoDe(pasos[i + 1]).color : AppColors.paper2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
      ],
    ]);
  }
}

/// Botones de contacto: WhatsApp y llamada.
List<Widget> _botonesContacto(Reserva r, {bool compacto = false}) {
  final tieneTel = _telWhatsapp(r.telefono).isNotEmpty;
  final densidad = compacto ? VisualDensity.compact : VisualDensity.standard;
  return [
    OutlinedButton.icon(
      onPressed: tieneTel ? () => _abrirUrl(_mensajeWhatsapp(r)) : null,
      icon: const LogoWhatsapp(size: 20),
      label: const Text('WhatsApp'),
      style: OutlinedButton.styleFrom(
        visualDensity: densidad,
        foregroundColor: const Color(0xFF128C4A),
        backgroundColor: const Color(0xFF25D366).withValues(alpha: 0.1),
        side: BorderSide(color: const Color(0xFF25D366).withValues(alpha: 0.6)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    OutlinedButton.icon(
      onPressed: r.telefono.trim().isEmpty ? null : () => _abrirUrl('tel:${r.telefono}'),
      icon: const Icon(Icons.call_rounded, size: 17),
      label: const Text('Llamar'),
      style: OutlinedButton.styleFrom(
        visualDensity: densidad,
        foregroundColor: const Color(0xFF1565C0),
        backgroundColor: const Color(0xFF1565C0).withValues(alpha: 0.07),
        side: BorderSide(color: const Color(0xFF1565C0).withValues(alpha: 0.4)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
  ];
}

/// Acciones de cambio de estado con el color del estado destino.
List<Widget> _botonesAccion(
  Reserva r, {
  required bool ocupada,
  required void Function(String) onAccion,
  bool compacto = false,
}) {
  if (ocupada) {
    return [const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))];
  }
  final densidad = compacto ? VisualDensity.compact : VisualDensity.standard;
  return [
    for (final a in accionesReserva(r.estado))
      if (a.principal)
        FilledButton.icon(
          onPressed: () => onAccion(a.estado),
          icon: Icon(a.icono, size: 17),
          label: Text(a.texto),
          style: FilledButton.styleFrom(
            backgroundColor: _estadoDe(a.estado).color,
            visualDensity: densidad,
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        )
      else
        TextButton.icon(
          onPressed: () => onAccion(a.estado),
          icon: Icon(a.icono, size: 17),
          label: Text(a.texto),
          style: TextButton.styleFrom(
            foregroundColor: a.peligro ? AppColors.bad : AppColors.steel,
            visualDensity: densidad,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
  ];
}

class _TarjetaReserva extends StatelessWidget {
  final Reserva reserva;
  final bool puedeEditar;
  final bool ocupada;
  final bool mostrarEstado;
  final VoidCallback onAbrir;
  final void Function(String) onAccion;
  const _TarjetaReserva({
    required this.reserva,
    required this.puedeEditar,
    required this.ocupada,
    required this.mostrarEstado,
    required this.onAbrir,
    required this.onAccion,
  });

  @override
  Widget build(BuildContext context) {
    final r = reserva;
    final est = _estadoDe(r.estado);
    final critico = _urgencia(r).critico;
    return _Elevable(
      acento: critico ? AppColors.bad : est.color,
      destacada: critico,
      onTap: onAbrir,
      child: Stack(children: [
        Positioned(left: 0, top: 0, bottom: 0, width: 5, child: ColoredBox(color: critico ? AppColors.bad : est.color)),
        Padding(
          padding: const EdgeInsets.fromLTRB(19, 14, 14, 14),
          child: LayoutBuilder(
            builder: (context, c) => c.maxWidth >= 820 ? _ancha(est) : _compacta(est),
          ),
        ),
      ]),
    );
  }

  Widget _encabezado(({String etiqueta, Color color, IconData icono}) est) {
    final r = reserva;
    return Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(r.id,
          style: const TextStyle(
              fontWeight: FontWeight.w900, fontSize: 16, fontFamily: 'monospace', color: AppColors.char)),
      if (mostrarEstado) PillEstado(est.etiqueta, est.color, icono: est.icono),
      _ChipTiempo(r),
    ]);
  }

  Widget _cliente({bool conNota = true}) {
    final r = reserva;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Avatar(r.nombre, tam: 42),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.nombre.isEmpty ? 'Sin nombre' : r.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
          if (r.telefono.isNotEmpty)
            _lineaDato(Icons.phone_outlined, r.telefono),
          if (r.email.isNotEmpty) _lineaDato(Icons.mail_outline_rounded, r.email),
          if (conNota && r.nota.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6DD),
                borderRadius: BorderRadius.circular(9),
                border: Border(left: BorderSide(color: const Color(0xFFD98200).withValues(alpha: 0.7), width: 3)),
              ),
              child: Text('“${r.nota.trim()}”',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF6B5200))),
            ),
          ],
        ]),
      ),
    ]);
  }

  Widget _lineaDato(IconData icono, String texto) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          Icon(icono, size: 13, color: AppColors.steel),
          const SizedBox(width: 5),
          Expanded(
            child: Text(texto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.2, color: AppColors.steel)),
          ),
        ]),
      );

  Widget _repuestos({required int max}) {
    final items = _itemsDe(reserva);
    final visibles = items.take(max).toList();
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final i in visibles) _ChipRepuesto(i),
      if (items.length > visibles.length)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: AppColors.paper2, borderRadius: BorderRadius.circular(11)),
          child: Text('+${items.length - visibles.length} más',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.steel)),
        ),
    ]);
  }

  Widget _unidades() {
    final n = _unidadesDe(reserva);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: AppColors.char, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.inventory_2_outlined, size: 13, color: Colors.white70),
        const SizedBox(width: 5),
        Text('$n ${n == 1 ? 'unidad' : 'unidades'}',
            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  List<Widget> _acciones({bool compacto = false}) => puedeEditar
      ? _botonesAccion(reserva, ocupada: ocupada, onAccion: onAccion, compacto: compacto)
      : const [];

  Widget _compacta(({String etiqueta, Color color, IconData icono}) est) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _encabezado(est),
      const SizedBox(height: 12),
      _cliente(),
      const SizedBox(height: 12),
      _repuestos(max: 3),
      const SizedBox(height: 12),
      Row(children: [
        _unidades(),
        const SizedBox(width: 14),
        Expanded(child: _LineaEstado(estado: reserva.estado, mini: true)),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ..._botonesContacto(reserva, compacto: true),
      ]),
      if (puedeEditar) ...[
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: _acciones(compacto: true)),
      ],
    ]);
  }

  Widget _ancha(({String etiqueta, Color color, IconData icono}) est) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _encabezado(est)),
        _unidades(),
      ]),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 300, child: _cliente()),
        const SizedBox(width: 24),
        Expanded(child: _repuestos(max: 8)),
        const SizedBox(width: 24),
        SizedBox(width: 250, child: _LineaEstado(estado: reserva.estado)),
      ]),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ..._botonesContacto(reserva),
        if (puedeEditar) const SizedBox(width: 6),
        ..._acciones(),
        TextButton.icon(
          onPressed: onAbrir,
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('Ver detalle'),
          style: TextButton.styleFrom(foregroundColor: AppColors.steel),
        ),
      ]),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Detalle de la reserva (diálogo)
// ---------------------------------------------------------------------------

class _DetalleReserva extends StatelessWidget {
  final Reserva reserva;
  final bool puedeEditar;
  final void Function(String) onAccion;
  const _DetalleReserva({required this.reserva, required this.puedeEditar, required this.onAccion});

  @override
  Widget build(BuildContext context) {
    final r = reserva;
    final est = _estadoDe(r.estado);
    final items = _itemsDe(r);
    final unidades = _unidadesDe(r);
    final f = _fechaDe(r);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 12, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [est.color, _oscuro(est.color)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Row(children: [
              _Avatar(r.nombre, tam: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.nombre.isEmpty ? 'Sin nombre' : r.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text('Reserva ${r.id} · ${est.etiqueta}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'monospace')),
                ]),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ]),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _LineaEstado(estado: r.estado),
                const SizedBox(height: 22),
                _seccion('Contacto'),
                _dato(context, Icons.phone_outlined, 'Teléfono', r.telefono),
                _dato(context, Icons.mail_outline_rounded, 'Correo', r.email),
                _dato(context, Icons.event_outlined, 'Reservada',
                    '${_fechaLarga(f)} · ${tiempoRelativo(r.fecha)}',
                    copiable: false),
                if (r.nota.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _seccion('Nota del cliente'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6DD),
                      borderRadius: BorderRadius.circular(12),
                      border: Border(left: BorderSide(color: const Color(0xFFD98200).withValues(alpha: 0.7), width: 3)),
                    ),
                    child: Text('“${r.nota.trim()}”',
                        style: const TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF6B5200), height: 1.4)),
                  ),
                ],
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: _seccion('Repuestos reservados')),
                  Text('$unidades ${unidades == 1 ? 'unidad' : 'unidades'}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.steel)),
                ]),
                for (final i in items)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.char, borderRadius: BorderRadius.circular(9)),
                        child: Text('×${i.cantidad}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(i.nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                      ),
                      if (i.sku.isNotEmpty)
                        Text(i.sku,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.steel, fontFamily: 'monospace')),
                    ]),
                  ),
              ]),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
            decoration: const BoxDecoration(
              color: Color(0xFFFAF8F4),
              border: Border(top: BorderSide(color: AdminColores.borde)),
            ),
            child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ..._botonesContacto(r),
              if (puedeEditar) const SizedBox(width: 6),
              if (puedeEditar) ..._botonesAccion(r, ocupada: false, onAccion: onAccion),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _seccion(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: AppColors.steel)),
      );

  Widget _dato(BuildContext context, IconData icono, String titulo, String valor, {bool copiable = true}) {
    final vacio = valor.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icono, size: 18, color: AppColors.steel),
        const SizedBox(width: 10),
        SizedBox(
          width: 86,
          child: Text(titulo, style: const TextStyle(fontSize: 12.5, color: AppColors.steel)),
        ),
        Expanded(
          child: SelectableText(vacio ? '—' : valor,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        ),
        if (copiable && !vacio)
          IconButton(
            tooltip: 'Copiar',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 16),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: valor));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$titulo copiado'), duration: const Duration(seconds: 2)),
              );
            },
          ),
      ]),
    );
  }
}
