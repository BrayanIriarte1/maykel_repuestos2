// Notificaciones de reservas (RF04): WhatsApp Cloud API (Meta) y correo SMTP.
// Si WhatsApp falla, se envía el respaldo por correo (HU-04, escenario 2).
// Nada se envía si las variables de entorno no están configuradas.
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import 'pdf_reserva.dart';

class ResultadoNotificacion {
  final bool whatsapp;
  final bool email;
  const ResultadoNotificacion({required this.whatsapp, required this.email});
}

class Notificador {
  final Map<String, String> env;
  Notificador(this.env);

  bool get whatsappConfigurado =>
      (env['WHATSAPP_TOKEN'] ?? '').isNotEmpty &&
      (env['WHATSAPP_PHONE_ID'] ?? '').isNotEmpty &&
      (env['WHATSAPP_DESTINO'] ?? '').isNotEmpty;

  bool get smtpConfigurado =>
      (env['SMTP_HOST'] ?? '').isNotEmpty &&
      (env['SMTP_USER'] ?? '').isNotEmpty &&
      (env['SMTP_PASS'] ?? '').isNotEmpty &&
      (env['EMAIL_DESTINO'] ?? '').isNotEmpty;

  String _resumen(Map<String, dynamic> r, List<String> lineas) {
    final b = StringBuffer()
      ..writeln('Nueva reserva ${r['folio']} - Maykel Repuestos 2')
      ..writeln('Cliente: ${r['nombre']}')
      ..writeln('Teléfono: ${r['telefono']}')
      ..writeln('Correo: ${r['email']}');
    if ((r['nota'] ?? '').toString().isNotEmpty) {
      b.writeln('Nota: ${r['nota']}');
    }
    b.writeln('Repuestos:');
    for (final l in lineas) {
      b.writeln('- $l');
    }
    return b.toString();
  }

  Future<bool> _enviarWhatsapp(String texto) async {
    if (!whatsappConfigurado) return false;
    final version = env['WHATSAPP_API_VERSION'] ?? 'v20.0';
    final resp = await http
        .post(
          Uri.parse(
              'https://graph.facebook.com/$version/${env['WHATSAPP_PHONE_ID']}/messages'),
          headers: {
            'Authorization': 'Bearer ${env['WHATSAPP_TOKEN']}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'messaging_product': 'whatsapp',
            'to': env['WHATSAPP_DESTINO'],
            'type': 'text',
            'text': {'body': texto},
          }),
        )
        .timeout(const Duration(seconds: 4));
    return resp.statusCode >= 200 && resp.statusCode < 300;
  }

  Future<bool> _enviarEmail(String asunto, String texto,
      {List<int>? pdf, String? nombrePdf}) async {
    if (!smtpConfigurado) return false;
    final servidor = SmtpServer(
      env['SMTP_HOST']!,
      port: int.tryParse(env['SMTP_PORT'] ?? '') ?? 587,
      username: env['SMTP_USER'],
      password: env['SMTP_PASS'],
      ssl: (env['SMTP_SSL'] ?? 'false') == 'true',
    );
    final mensaje = Message()
      ..from = Address(env['SMTP_FROM'] ?? env['SMTP_USER']!, 'Maykel Repuestos 2')
      ..recipients.addAll(
          env['EMAIL_DESTINO']!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty))
      ..subject = asunto
      ..text = texto;
    if (pdf != null) {
      mensaje.attachments.add(StreamAttachment(
          Stream.value(pdf), 'application/pdf',
          fileName: nombrePdf ?? 'reserva.pdf'));
    }
    await send(mensaje, servidor).timeout(const Duration(seconds: 4));
    return true;
  }

  /// Nunca lanza: un fallo de mensajería no debe romper la reserva del cliente.
  Future<ResultadoNotificacion> notificarReserva(
      Map<String, dynamic> reserva, List<String> lineas,
      {Uint8List? pdfListo}) async {
    final texto = _resumen(reserva, lineas);
    var okWa = false;
    var okMail = false;
    try {
      okWa = await _enviarWhatsapp(texto);
    } catch (e) {
      print('⚠️ WhatsApp falló (${reserva['folio']}): $e');
    }
    try {
      final pdf = pdfListo ?? await generarPdfReserva(reserva, lineas);
      okMail = await _enviarEmail('Nueva reserva ${reserva['folio']}', texto,
          pdf: pdf, nombrePdf: '${reserva['folio']}.pdf');
    } catch (e) {
      print('⚠️ SMTP falló (${reserva['folio']}): $e');
    }
    return ResultadoNotificacion(whatsapp: okWa, email: okMail);
  }
}
