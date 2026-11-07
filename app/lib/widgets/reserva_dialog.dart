import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_service.dart';
import '../config.dart';
import '../models.dart';
import '../utils/carrito.dart';
import '../utils/descarga.dart';

/// Abre el diálogo "Mi reserva": lista de repuestos agregados (HU-03), datos de
/// contacto y consentimiento. Al finalizar descarga el comprobante PDF y muestra
/// el ticket con botones para enviarlo por WhatsApp o correo.
Future<void> mostrarDialogoReserva(
  BuildContext context,
  VoidCallback onReservaCreada,
) {
  return showDialog(
    context: context,
    builder: (_) => _ReservaDialog(onReservaCreada: onReservaCreada),
  );
}

class _ReservaDialog extends StatefulWidget {
  final VoidCallback onReservaCreada;

  const _ReservaDialog({required this.onReservaCreada});

  @override
  State<_ReservaDialog> createState() => _ReservaDialogState();
}

class _ReservaDialogState extends State<_ReservaDialog> {
  static const _msgContacto =
      'Por favor ingrese un canal de contacto válido para enviar su comprobante';
  static final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _notaCtrl = TextEditingController();
  final _carrito = CarritoReserva.instance;

  bool _enviando = false;
  bool _acepta = false;
  bool _faltaConsentimiento = false;
  String? _error;
  Reserva? _reservaCreada;
  bool _pdfDescargado = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _emailCtrl.dispose();
    _notaCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    final formOk = _formKey.currentState!.validate();
    setState(() => _faltaConsentimiento = !_acepta);
    if (!formOk || !_acepta || _carrito.vacio) return;

    final lineas = _carrito.lineas;
    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      final reserva = await ApiService.instance.crearReserva(
        items: [for (final l in lineas) (id: l.producto.id, cantidad: l.cantidad)],
        nombre: _nombreCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        nota: _notaCtrl.text.trim(),
      );
      _carrito.limpiar();
      widget.onReservaCreada();
      if (mounted) {
        setState(() {
          _reservaCreada = reserva;
          _pdfDescargado = _descargarPdf(reserva);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  bool _descargarPdf(Reserva r) {
    final b64 = r.pdfBase64;
    if (b64 == null || b64.isEmpty) return false;
    return descargarBytes(base64Decode(b64), 'Reserva-${r.id}.pdf', 'application/pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: _reservaCreada != null
                ? _buildTicket(_reservaCreada!)
                : ListenableBuilder(
                    listenable: _carrito,
                    builder: (_, __) =>
                        _carrito.vacio ? _buildVacio() : _buildFormulario(),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _cabecera(String titulo) => Row(
        children: [
          Expanded(
            child: Text(
              titulo,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );

  Widget _buildVacio() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabecera('Mi reserva'),
        const SizedBox(height: 12),
        const Icon(Icons.shopping_bag_outlined, size: 44, color: AppColors.steel),
        const SizedBox(height: 10),
        const Text(
          'Tu lista está vacía. Usa «Agregar a reserva» en los repuestos que necesites.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.steel),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Seguir buscando'),
        ),
      ],
    );
  }

  Widget _lineaItem(LineaReserva l) {
    final p = l.producto;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text('${p.sku} · ${p.stock} disponibles',
                    style: const TextStyle(color: AppColors.steel, fontSize: 11.5)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Menos',
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            onPressed: l.cantidad > 1
                ? () => _carrito.cambiarCantidad(p.id, l.cantidad - 1)
                : null,
          ),
          Text('${l.cantidad}', style: const TextStyle(fontWeight: FontWeight.w700)),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Más',
            icon: const Icon(Icons.add_circle_outline, size: 20),
            onPressed: l.cantidad < p.stock
                ? () => _carrito.cambiarCantidad(p.id, l.cantidad + 1)
                : null,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Quitar',
            icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.bad),
            onPressed: () => _carrito.quitar(p.id),
          ),
        ],
      ),
    );
  }

  Widget _buildFormulario() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cabecera('Mi reserva (${_carrito.totalUnidades})'),
          const SizedBox(height: 4),
          for (final l in _carrito.lineas) _lineaItem(l),
          const SizedBox(height: 8),
          TextFormField(
            controller: _nombreCtrl,
            decoration: const InputDecoration(labelText: 'Nombre completo'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _telefonoCtrl,
            decoration: const InputDecoration(
                labelText: 'Teléfono (WhatsApp)', hintText: '+56 9 1234 5678'),
            keyboardType: TextInputType.phone,
            validator: (v) => (v == null || v.trim().length < 8) ? _msgContacto : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _emailCtrl,
            decoration: const InputDecoration(labelText: 'Correo electrónico'),
            keyboardType: TextInputType.emailAddress,
            validator: (v) =>
                (v == null || !_emailRegex.hasMatch(v.trim())) ? _msgContacto : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notaCtrl,
            decoration: const InputDecoration(
                labelText: 'Comentario (opcional)',
                hintText: 'Ej: modelo y año del vehículo'),
            maxLines: 2,
            maxLength: 500,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            value: _acepta,
            onChanged: (v) => setState(() {
              _acepta = v ?? false;
              _faltaConsentimiento = false;
            }),
            title: const Text(
              'Acepto el tratamiento de mis datos personales para gestionar esta '
              'reserva (Ley N° 19.628) y el aviso legal.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            subtitle: _faltaConsentimiento
                ? const Text('Debes aceptar para continuar',
                    style: TextStyle(color: AppColors.bad, fontSize: 11.5))
                : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: const TextStyle(color: AppColors.bad, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _enviando ? null : _confirmar,
            child: _enviando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Finalizar reserva'),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Seguir agregando repuestos'),
          ),
        ],
      ),
    );
  }

  Widget _buildTicket(Reserva r) {
    final fecha = DateTime.tryParse(r.fecha)?.toLocal() ?? DateTime.now();
    final fechaStr =
        '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
    final detalle = r.items.isEmpty
        ? '${r.producto} (${r.sku}) x${r.cantidad}'
        : r.items.map((i) => '${i.nombre} (${i.sku}) x${i.cantidad}').join('\n');

    final waTexto = Uri.encodeComponent(
      'Hola, quiero confirmar mi reserva en Maykel Repuestos:\n'
      '$detalle\n'
      'Nombre: ${r.nombre}\n'
      'N° de reserva: ${r.id}',
    );
    final mailSubject = Uri.encodeComponent('Reserva ${r.id} — Maykel Repuestos');
    final mailBody = Uri.encodeComponent(
      'Reserva N°: ${r.id}\n$detalle\n\n'
      'Nombre: ${r.nombre}\nTeléfono: ${r.telefono}\nCorreo: ${r.email}\n'
      '${r.nota.isNotEmpty ? 'Comentario: ${r.nota}\n' : ''}',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabecera('Reserva registrada'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.paper2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              _ticketRow('N° reserva', r.id),
              _ticketRow('Fecha', fechaStr),
              _ticketRow('Cliente', r.nombre),
              const Divider(height: 18),
              for (final i in r.items)
                _ticketRow('${i.nombre} · ${i.sku}', 'x${i.cantidad}'),
              if (r.items.isEmpty) _ticketRow(r.sku, 'x${r.cantidad}'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _pdfDescargado
              ? 'Tu comprobante PDF se descargó automáticamente. Envíanos la reserva por '
                  'WhatsApp o correo para que nuestro equipo la confirme.'
              : 'Tu reserva quedó registrada. Para confirmarla, envíanosla por '
                  'WhatsApp o correo; nuestro equipo te confirmará el retiro o despacho.',
          style: const TextStyle(fontSize: 12.5, color: AppColors.steel, height: 1.5),
        ),
        const SizedBox(height: 16),
        if (r.pdfBase64 != null && r.pdfBase64!.isNotEmpty) ...[
          ElevatedButton.icon(
            onPressed: () => setState(() => _pdfDescargado = _descargarPdf(r)),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Descargar comprobante PDF'),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: () => launchUrl(
            Uri.parse('https://wa.me/${SiteContent.actual.contactoWhatsapp}?text=$waTexto'),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.chat),
          label: const Text('Enviar por WhatsApp'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => launchUrl(Uri.parse(
              'mailto:${SiteContent.actual.contactoEmail}?subject=$mailSubject&body=$mailBody')),
          icon: const Icon(Icons.email_outlined),
          label: const Text('Enviar por correo'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }

  Widget _ticketRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: AppColors.steel, fontSize: 12.5)),
          ),
          const SizedBox(width: 12),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
        ],
      ),
    );
  }
}
