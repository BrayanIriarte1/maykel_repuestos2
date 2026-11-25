import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import 'portada_extra.dart' show LogoWhatsapp;

const _rutaFlyer = 'assets/images/flyer_sucursal.jpg';

/// WhatsApp de la casa matriz (Vargas #2228), el que aparece en el flyer.
const _whatsappCasaMatriz = '56973877811';
const _mensajeWhatsapp = 'Hola Maykel Repuestos, quiero cotizar un repuesto.';

bool _yaMostrado = false;

/// Muestra el flyer de la casa matriz al abrir la página (una vez por visita).
/// Se cierra con la X, tocando fuera de la imagen o con Esc.
/// Espera a que la imagen esté descargada para no mostrar un marco vacío.
Future<void> mostrarFlyerSucursal(BuildContext context) async {
  if (_yaMostrado) return;
  _yaMostrado = true;
  try {
    await precacheImage(const AssetImage(_rutaFlyer), context);
  } catch (_) {
    return; // Si la imagen no carga, mejor no mostrar nada.
  }
  if (!context.mounted) return;
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar',
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, __) => const _FlyerSucursal(),
    transitionBuilder: (_, anim, __, child) {
      final c = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(c), child: child),
      );
    },
  );
}

void _abrirWhatsapp() {
  launchUrl(
    Uri.parse('https://wa.me/$_whatsappCasaMatriz?text=${Uri.encodeComponent(_mensajeWhatsapp)}'),
    mode: LaunchMode.externalApplication,
  );
}

class _FlyerSucursal extends StatelessWidget {
  const _FlyerSucursal();

  // Proporción del flyer: 1236 x 1600.
  static const _proporcion = 1236 / 1600;
  static const _altoPanel = 132.0;

  @override
  Widget build(BuildContext context) {
    final tam = MediaQuery.sizeOf(context);
    final altoImagen = (tam.height * 0.92 - _altoPanel).clamp(220.0, 820.0);
    final ancho = (altoImagen * _proporcion).clamp(0.0, tam.width * 0.92);

    return Center(
      child: SizedBox(
        width: ancho,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: Colors.white,
              elevation: 12,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: _proporcion,
                    child: LayoutBuilder(builder: (_, c) {
                      return Stack(children: [
                        Positioned.fill(
                          child: Image.asset(_rutaFlyer,
                              fit: BoxFit.cover, filterQuality: FilterQuality.medium),
                        ),
                        // El "¡COTIZA AQUÍ!" impreso en el flyer también abre WhatsApp.
                        Positioned(
                          left: c.maxWidth * 0.04,
                          top: c.maxHeight * 0.87,
                          width: c.maxWidth * 0.44,
                          height: c.maxHeight * 0.095,
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: _abrirWhatsapp,
                              child: const Tooltip(
                                message: 'Cotizar por WhatsApp',
                                child: SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                      ]);
                    }),
                  ),
                  const _PanelInferior(alto: _altoPanel),
                ],
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 6,
                child: IconButton(
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close_rounded, color: AppColors.char),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Franja bajo el flyer: aclara que se trabajan más marcas y el botón a WhatsApp.
class _PanelInferior extends StatelessWidget {
  final double alto;
  const _PanelInferior({required this.alto});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: alto,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.red, AppColors.redDark]),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '¡Y muchas marcas más!',
              style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
            ),
          ),
          const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Jeep, Dodge, Fiat, Volkswagen, Samsung y muchas otras.',
              style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _abrirWhatsapp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  DecoratedBox(
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Padding(padding: EdgeInsets.all(2), child: LogoWhatsapp(size: 24)),
                  ),
                  SizedBox(width: 10),
                  Text('Cotiza aquí: +56 9 7387 7811',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
