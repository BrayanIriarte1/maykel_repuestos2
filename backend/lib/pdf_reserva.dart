// Comprobante de reserva en PDF generado en memoria (RF03). Sin precios (RF01).
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> generarPdfReserva(
    Map<String, dynamic> reserva, List<String> lineas) async {
  final doc = pw.Document();
  final fecha = DateTime.tryParse('${reserva['fecha']}')?.toLocal();
  final fechaTxt = fecha == null
      ? ''
      : '${fecha.day.toString().padLeft(2, '0')}-${fecha.month.toString().padLeft(2, '0')}-${fecha.year} '
          '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';

  pw.Widget fila(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.SizedBox(
              width: 110,
              child: pw.Text(k, style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
          pw.Expanded(child: pw.Text(v)),
        ]),
      );

  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('MAYKEL REPUESTOS 2',
          style: pw.TextStyle(
              fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
      pw.Text('Calama - Comprobante de reserva'),
      pw.Divider(),
      fila('Folio', '${reserva['folio']}'),
      fila('Fecha', fechaTxt),
      fila('Estado', 'Pendiente de confirmacion'),
      pw.SizedBox(height: 10),
      pw.Text('Datos del cliente',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      fila('Nombre', '${reserva['nombre']}'),
      fila('Telefono', '${reserva['telefono']}'),
      fila('Correo', '${reserva['email']}'),
      if ('${reserva['nota'] ?? ''}'.isNotEmpty) fila('Nota', '${reserva['nota']}'),
      pw.SizedBox(height: 10),
      pw.Text('Repuestos reservados',
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      for (final l in lineas) pw.Bullet(text: l),
      pw.Spacer(),
      pw.Divider(),
      pw.Text(
          'Este comprobante no constituye una venta ni un cobro. El stock queda sujeto '
          'a confirmacion en mesón. Los precios se informan en la sucursal.',
          style: const pw.TextStyle(fontSize: 9)),
    ]),
  ));
  return doc.save();
}
