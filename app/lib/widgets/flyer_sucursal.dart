import 'package:flutter/material.dart';

import '../config.dart';

const _rutaFlyer = 'assets/images/flyer_sucursal.jpg';
bool _yaMostrado = false;

/// Muestra el flyer de la casa matriz al abrir la página (una vez por visita).
/// Se cierra con la X, tocando fuera de la imagen o con Esc.
void mostrarFlyerSucursal(BuildContext context) {
  if (_yaMostrado) return;
  _yaMostrado = true;
  showGeneralDialog(
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

class _FlyerSucursal extends StatelessWidget {
  const _FlyerSucursal();

  @override
  Widget build(BuildContext context) {
    final tam = MediaQuery.sizeOf(context);
    // Proporción del flyer: 1236 x 1600.
    const proporcion = 1236 / 1600;
    final alto = (tam.height * 0.9).clamp(200.0, 900.0);
    final ancho = (alto * proporcion).clamp(0.0, tam.width * 0.92);

    return Center(
      child: SizedBox(
        width: ancho,
        child: AspectRatio(
          aspectRatio: proporcion,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(_rutaFlyer, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
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
      ),
    );
  }
}
