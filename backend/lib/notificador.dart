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
      {List<int>? pdf, String? nombrePdf, List<String>? para}) async {
    if (!smtpConfigurado) return false;
    final servidor = SmtpServer(
      env['SMTP_HOST']!,
      port: int.tryParse(env['SMTP_PORT'] ?? '') ?? 587,
      username: env['SMTP_USER'],
      password: env['SMTP_PASS'],
      ssl: (env['SMTP_SSL'] ?? 'false') == 'true',
    );
    final destinos = para ??
        env['EMAIL_DESTINO']!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final mensaje = Message()
      ..from = Address(env['SMTP_FROM'] ?? env['SMTP_USER']!, 'Maykel Repuestos 2')
      ..recipients.addAll(destinos)
      ..subject = asunto
      ..text = texto;
    if (pdf != null) {
      mensaje.attachments.add(StreamAttachment(
          Stream.value(pdf), 'application/pdf',
          fileName: nombrePdf ?? 'reserva.pdf'));
    }
    await send(mensaje, servidor).timeout(const Duration(seconds: 12));
    return true;
  }

  /// Qué canales están listos y qué variables faltan (sin revelar secretos).
  Map<String, dynamic> estado() {
    String enmascarar(String v) => v.length <= 4 ? '••••' : '${v.substring(0, 2)}••••${v.substring(v.length - 2)}';
    final faltaSmtp = [
      for (final k in ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASS', 'EMAIL_DESTINO'])
        if ((env[k] ?? '').isEmpty) k
    ];
    final faltaWa = [
      for (final k in ['WHATSAPP_TOKEN', 'WHATSAPP_PHONE_ID', 'WHATSAPP_DESTINO'])
        if ((env[k] ?? '').isEmpty) k
    ];
    return {
      'correo': {
        'configurado': smtpConfigurado,
        'servidor': env['SMTP_HOST'] ?? '',
        'puerto': env['SMTP_PORT'] ?? '587',
        'usuario': enmascarar(env['SMTP_USER'] ?? ''),
        'destinatarios': (env['EMAIL_DESTINO'] ?? '')
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        'faltantes': faltaSmtp,
      },
      'whatsapp': {
        'configurado': whatsappConfigurado,
        'destino': enmascarar(env['WHATSAPP_DESTINO'] ?? ''),
        'faltantes': faltaWa,
      },
    };
  }

  /// Envía un mensaje de prueba por el canal indicado y devuelve el resultado o el motivo del fallo.
  Future<Map<String, dynamic>> probar(String canal, {String? destinoCorreo}) async {
    final inicio = DateTime.now();
    try {
      bool ok;
      if (canal == 'whatsapp') {
        if (!whatsappConfigurado) {
          return {'ok': false, 'error': 'Faltan variables: ${(estado()['whatsapp'] as Map)['faltantes']}'};
        }
        ok = await _enviarWhatsapp('Prueba de Maykel Repuestos 2: las notificaciones por WhatsApp funcionan.');
      } else {
        if (!smtpConfigurado) {
          return {'ok': false, 'error': 'Faltan variables: ${(estado()['correo'] as Map)['faltantes']}'};
        }
        ok = await _enviarEmail('Prueba de correo - Maykel Repuestos 2',
            'Si recibes este mensaje, el envío de correos de la plataforma funciona correctamente.',
            para: (destinoCorreo != null && destinoCorreo.contains('@')) ? [destinoCorreo] : null);
      }
      return {
        'ok': ok,
        'ms': DateTime.now().difference(inicio).inMilliseconds,
        if (!ok) 'error': 'El proveedor rechazó el mensaje. Revisa el token o el número.',
      };
    } catch (e) {
      var msg = e.toString();
      if (msg.contains('Authentication') || msg.contains('535') || msg.contains('Username and Password')) {
        msg = 'Gmail rechazó la contraseña. Usa una «contraseña de aplicación» de 16 letras (no la clave normal) y verifica que la verificación en 2 pasos esté activa.';
      } else if (msg.contains('TimeoutException')) {
        msg = 'Tiempo de espera agotado: revisa SMTP_HOST/SMTP_PORT y que el servidor tenga salida a internet por ese puerto.';
      } else if (msg.length > 220) {
        msg = '${msg.substring(0, 220)}…';
      }
      return {'ok': false, 'error': msg};
    }
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
      // Confirmación al cliente con su comprobante; si falla no afecta al aviso interno.
      final correoCliente = '${reserva['email'] ?? ''}'.trim();
      if (smtpConfigurado && correoCliente.contains('@')) {
        try {
          await _enviarEmail(
              'Recibimos tu reserva ${reserva['folio']} - Maykel Repuestos 2',
              'Hola ${reserva['nombre']},\n\n'
              'Recibimos tu reserva ${reserva['folio']}. Adjuntamos tu comprobante en PDF.\n'
              'Un ejecutivo confirmará la disponibilidad por WhatsApp o correo y te avisará cuando '
              'puedas retirar en Vargas #2275, Calama.\n\n'
              'Repuestos:\n${lineas.map((l) => '- $l').join('\n')}\n\n'
              'Este comprobante no constituye una venta ni un cobro.\n'
              'Maykel Repuestos 2',
              pdf: pdf,
              nombrePdf: '${reserva['folio']}.pdf',
              para: [correoCliente]);
        } catch (e) {
          print('⚠️ No se pudo confirmar al cliente (${reserva['folio']}): $e');
        }
      }
    } catch (e) {
      print('⚠️ SMTP falló (${reserva['folio']}): $e');
    }
    return ResultadoNotificacion(whatsapp: okWa, email: okMail);
  }
}
