import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models.dart';

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

/// Pestaña Reservas del panel: filtros por estado con contadores, búsqueda,
/// tarjetas con contacto directo (WhatsApp / llamada) y botones de acción.
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
  String? _filtro; // null = automático (pendientes si hay, si no todas)
  String _q = '';
  int _limite = 25;
  final Set<String> _ocupadas = {};

  int _cuenta(String estado) => widget.reservas.where((r) => r.estado == estado).length;

  Future<void> _cambiar(Reserva r, String estado) async {
    if (estado == 'rechazada') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Rechazar reserva'),
          content: Text('¿Rechazar la reserva ${r.id} de ${r.nombre}?'
              '${r.estado == 'confirmada' || r.estado == 'entregada' ? ' Se repondrá el stock.' : ''}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.bad),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Rechazar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _ocupadas.add(r.id));
    try {
      await widget.onCambiarEstado(r, estado);
    } finally {
      if (mounted) setState(() => _ocupadas.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pend = _cuenta('pendiente');
    final filtro = _filtro ?? (pend > 0 ? 'pendiente' : '');
    final q = _q.trim().toLowerCase();
    final lista = widget.reservas.where((r) {
      if (filtro.isNotEmpty && r.estado != filtro) return false;
      if (q.isEmpty) return true;
      return r.nombre.toLowerCase().contains(q) ||
          r.id.toLowerCase().contains(q) ||
          r.telefono.contains(q) ||
          r.email.toLowerCase().contains(q) ||
          r.producto.toLowerCase().contains(q) ||
          r.sku.toLowerCase().contains(q);
    }).toList();
    final visibles = lista.take(_limite).toList();

    return RefreshIndicator(
      onRefresh: widget.onRefrescar,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipFiltro('', 'Todas', widget.reservas.length, filtro, AppColors.char, Icons.apps),
              for (final e in kEstadosReserva.entries)
                _chipFiltro(e.key, e.value.etiqueta, _cuenta(e.key), filtro, e.value.color, e.value.icono),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 360,
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar por cliente, folio, teléfono o producto',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() {
                    _q = v;
                    _limite = 25;
                  }),
                ),
              ),
              OutlinedButton.icon(
                onPressed: widget.onPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('PDF'),
              ),
              Text('${lista.length} reserva${lista.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: AppColors.steel, fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 14),
          if (lista.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Column(children: [
                  Icon(filtro == 'pendiente' ? Icons.celebration_outlined : Icons.event_busy_outlined,
                      size: 46, color: AppColors.paper2),
                  const SizedBox(height: 10),
                  Text(
                    filtro == 'pendiente'
                        ? '¡Todo al día! No hay reservas pendientes.'
                        : 'No hay reservas con ese filtro.',
                    style: const TextStyle(color: AppColors.steel),
                  ),
                ]),
              ),
            )
          else ...[
            for (final r in visibles) _tarjeta(r),
            if (lista.length > visibles.length)
              Center(
                child: TextButton.icon(
                  onPressed: () => setState(() => _limite += 25),
                  icon: const Icon(Icons.expand_more),
                  label: Text('Ver más (${lista.length - visibles.length} restantes)'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chipFiltro(String clave, String texto, int n, String actual, Color color, IconData icono) {
    final sel = actual == clave;
    return ChoiceChip(
      avatar: Icon(icono, size: 16, color: sel ? Colors.white : color),
      label: Text('$texto · $n'),
      selected: sel,
      selectedColor: color,
      showCheckmark: false,
      labelStyle: TextStyle(
          color: sel ? Colors.white : AppColors.char, fontWeight: FontWeight.w700, fontSize: 12.5),
      onSelected: (_) => setState(() {
        _filtro = clave;
        _limite = 25;
      }),
    );
  }

  Widget _tarjeta(Reserva r) {
    final est = kEstadosReserva[r.estado] ?? kEstadosReserva['pendiente']!;
    final ocupada = _ocupadas.contains(r.id);
    final items = r.items.isNotEmpty
        ? r.items
        : [(sku: r.sku, nombre: r.producto, cantidad: r.cantidad.toInt())];
    final wa = _telWhatsapp(r.telefono);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: r.estado == 'pendiente' ? est.color.withValues(alpha: 0.5) : AppColors.paper2),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 12, offset: Offset(0, 5))],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: est.color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(r.id,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 15, fontFamily: 'monospace')),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                              color: est.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(est.icono, size: 13, color: est.color),
                            const SizedBox(width: 4),
                            Text(est.etiqueta,
                                style: TextStyle(
                                    color: est.color, fontWeight: FontWeight.w800, fontSize: 11.5)),
                          ]),
                        ),
                        Text(tiempoRelativo(r.fecha),
                            style: const TextStyle(color: AppColors.steel, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.nombre,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                              const SizedBox(height: 4),
                              Text(r.telefono, style: const TextStyle(fontSize: 12.5)),
                              Text(r.email,
                                  style: const TextStyle(fontSize: 12, color: AppColors.steel)),
                              if (r.nota.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('“${r.nota}”',
                                    style: const TextStyle(
                                        fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.steel)),
                              ],
                            ],
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 260, maxWidth: 460),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final i in items)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: AppColors.paper, borderRadius: BorderRadius.circular(8)),
                                      child: Text('×${i.cantidad}',
                                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text('${i.nombre}  ·  ${i.sku}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12.5)),
                                    ),
                                  ]),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: wa.isEmpty
                              ? null
                              : () => launchUrl(Uri.parse(
                                  'https://wa.me/$wa?text=${Uri.encodeComponent('Hola ${r.nombre}, te escribimos de Maykel Repuestos por tu reserva ${r.id}.')}')),
                          icon: const Icon(Icons.chat_outlined, size: 16, color: Color(0xFF25D366)),
                          label: const Text('WhatsApp'),
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => launchUrl(Uri.parse('tel:${r.telefono}')),
                          icon: const Icon(Icons.call_outlined, size: 16),
                          label: const Text('Llamar'),
                          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                        ),
                        if (widget.puedeEditar) ...[
                          const SizedBox(width: 8),
                          if (ocupada)
                            const SizedBox(
                                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            for (final a in accionesReserva(r.estado))
                              a.principal
                                  ? FilledButton.icon(
                                      onPressed: () => _cambiar(r, a.estado),
                                      icon: Icon(a.icono, size: 16),
                                      label: Text(a.texto),
                                      style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.red,
                                          visualDensity: VisualDensity.compact),
                                    )
                                  : TextButton.icon(
                                      onPressed: () => _cambiar(r, a.estado),
                                      icon: Icon(a.icono, size: 16),
                                      label: Text(a.texto),
                                      style: TextButton.styleFrom(
                                          foregroundColor: a.peligro ? AppColors.bad : AppColors.steel,
                                          visualDensity: VisualDensity.compact),
                                    ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
