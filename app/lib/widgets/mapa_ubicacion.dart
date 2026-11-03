import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Mapa embebido (Google Maps, sin API key) que muestra la ubicación de la
/// sucursal. Recibe la dirección o las coordenadas a buscar.
class MapaUbicacion extends StatelessWidget {
  final String consulta;
  final double alto;

  const MapaUbicacion({super.key, required this.consulta, this.alto = 320});

  static final Set<String> _registrados = {};

  @override
  Widget build(BuildContext context) {
    final viewType = 'mapa-${consulta.hashCode}';
    if (_registrados.add(viewType)) {
      final url = 'https://maps.google.com/maps?q=${Uri.encodeComponent(consulta)}'
          '&z=17&output=embed';
      ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
        return web.HTMLIFrameElement()
          ..src = url
          ..title = 'Mapa de ubicación'
          ..style.border = '0'
          ..style.width = '100%'
          ..style.height = '100%'
          ..loading = 'lazy'
          ..referrerPolicy = 'no-referrer-when-downgrade';
      });
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: alto,
        width: double.infinity,
        child: HtmlElementView(viewType: viewType),
      ),
    );
  }
}
