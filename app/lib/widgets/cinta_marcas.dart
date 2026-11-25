import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../config.dart';
import 'diseno.dart' show logoDeMarca;
import 'efectos.dart' show enPantalla;

/// Cinta de logos que se desplaza sola de lado a lado (estilo "marcas que nos respaldan").
/// Se pausa al pasar el mouse y cada logo se puede tocar para filtrar el catálogo.
///
/// Pensada para ser liviana en celulares: solo se mueve cuando está en pantalla,
/// se redibuja aislada del resto (RepaintBoundary) y el difuminado de los bordes
/// es un degradado encima, no una máscara (que obligaría a recomponer cada cuadro).
class CintaMarcas extends StatefulWidget {
  final List<String> marcas;
  final void Function(String marca) onTap;
  final bool haciaLaDerecha;
  final double altoLogo;
  final double anchoItem;
  final Color fondo;

  /// Píxeles por segundo.
  final double velocidad;

  const CintaMarcas({
    super.key,
    required this.marcas,
    required this.onTap,
    this.haciaLaDerecha = false,
    this.altoLogo = 80,
    this.anchoItem = 220,
    this.velocidad = 45,
    this.fondo = Colors.white,
  });

  @override
  State<CintaMarcas> createState() => _CintaMarcasState();
}

class _CintaMarcasState extends State<CintaMarcas> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _desplazamiento = ValueNotifier<double>(0);
  Duration _ultimo = Duration.zero;
  bool _pausada = false;

  double get _anchoTira => widget.marcas.length * widget.anchoItem;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((t) {
      final dt = (t - _ultimo).inMicroseconds / 1e6;
      _ultimo = t;
      if (_pausada || _anchoTira <= 0 || !enPantalla(context)) return;
      _desplazamiento.value =
          (_desplazamiento.value + widget.velocidad * dt.clamp(0, 0.1)) % _anchoTira;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _desplazamiento.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.marcas.isEmpty) return const SizedBox.shrink();
    final alto = widget.altoLogo + 40;
    final tira = Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final m in widget.marcas) _item(m)],
    );
    Widget borde(Alignment inicio) => IgnorePointer(
          child: Container(
            width: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: inicio,
                end: -inicio,
                colors: [widget.fondo, widget.fondo.withValues(alpha: 0)],
              ),
            ),
          ),
        );

    return MouseRegion(
      onEnter: (_) => _pausada = true,
      onExit: (_) => _pausada = false,
      child: SizedBox(
        height: alto,
        child: LayoutBuilder(builder: (context, c) {
          // Se repite la tira las veces necesarias para cubrir pantallas anchas sin huecos.
          final copias = (c.maxWidth / _anchoTira).ceil() + 1;
          return Stack(children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: ValueListenableBuilder<double>(
                      valueListenable: _desplazamiento,
                      builder: (_, d, child) {
                        final x = widget.haciaLaDerecha ? d - _anchoTira : -d;
                        return Transform.translate(offset: Offset(x, 0), child: child);
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [for (var i = 0; i < copias; i++) tira],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(left: 0, top: 0, bottom: 0, child: borde(Alignment.centerLeft)),
            Positioned(right: 0, top: 0, bottom: 0, child: borde(Alignment.centerRight)),
          ]);
        }),
      ),
    );
  }

  Widget _item(String marca) {
    return SizedBox(
      width: widget.anchoItem,
      child: Center(
        child: _LogoCinta(
          nombre: marca,
          logo: logoDeMarca(marca),
          alto: widget.altoLogo,
          ancho: widget.anchoItem - 50,
          onTap: () => widget.onTap(marca),
        ),
      ),
    );
  }
}

class _LogoCinta extends StatefulWidget {
  final String nombre;
  final String? logo;
  final double alto;
  final double ancho;
  final VoidCallback onTap;
  const _LogoCinta({
    required this.nombre,
    required this.logo,
    required this.alto,
    required this.ancho,
    required this.onTap,
  });

  @override
  State<_LogoCinta> createState() => _LogoCintaState();
}

class _LogoCintaState extends State<_LogoCinta> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final texto = Text(
      widget.nombre.toUpperCase(),
      textAlign: TextAlign.center,
      maxLines: 1,
      style: TextStyle(
        fontSize: widget.alto * 0.32,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
        color: AppColors.char,
      ),
    );
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return Tooltip(
      message: 'Ver repuestos ${widget.nombre.toUpperCase()}',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hover ? 1.12 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: SizedBox(
              width: widget.ancho,
              height: widget.alto,
              child: widget.logo == null
                  ? Center(child: FittedBox(fit: BoxFit.scaleDown, child: texto))
                  : Image.asset(
                      widget.logo!,
                      fit: BoxFit.contain,
                      // Decodifica el logo al tamaño en que se muestra (menos memoria).
                      cacheHeight: (widget.alto * ratio).round(),
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, __, ___) =>
                          Center(child: FittedBox(fit: BoxFit.scaleDown, child: texto)),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
