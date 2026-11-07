import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:web/web.dart' as web;

/// Mapa embebido (Google Maps, sin API key) que muestra la ubicación de la
/// sucursal. Mientras no se haga clic, una capa transparente deja que la rueda del
/// mouse siga desplazando la página; al hacer clic el mapa se activa (zoom y arrastre)
/// y se desactiva al sacar el mouse.
class MapaUbicacion extends StatefulWidget {
  final String consulta;
  final double alto;

  const MapaUbicacion({super.key, required this.consulta, this.alto = 320});

  static final Set<String> _registrados = {};

  @override
  State<MapaUbicacion> createState() => _MapaUbicacionState();
}

class _MapaUbicacionState extends State<MapaUbicacion> {
  bool _activo = false;

  @override
  Widget build(BuildContext context) {
    final viewType = 'mapa-${widget.consulta.hashCode}';
    if (MapaUbicacion._registrados.add(viewType)) {
      final url = 'https://maps.google.com/maps?q=${Uri.encodeComponent(widget.consulta)}'
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
      child: MouseRegion(
        onExit: (_) {
          if (_activo) setState(() => _activo = false);
        },
        child: SizedBox(
          height: widget.alto,
          width: double.infinity,
          child: Stack(
            children: [
              Positioned.fill(child: HtmlElementView(viewType: viewType)),
              if (!_activo)
                Positioned.fill(
                  child: PointerInterceptor(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _activo = true),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.touch_app_outlined, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text('Haz clic para mover o acercar el mapa',
                                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
