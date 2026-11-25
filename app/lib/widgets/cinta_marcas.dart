import 'package:flutter/material.dart';

import '../config.dart';
import 'diseno.dart' show logoDeMarca;

/// Cinta de logos que se desplaza sola de lado a lado (estilo "marcas que nos respaldan").
/// Se pausa al pasar el mouse y cada logo se puede tocar para filtrar el catálogo.
class CintaMarcas extends StatefulWidget {
  final List<String> marcas;
  final void Function(String marca) onTap;
  final bool haciaLaDerecha;
  final double altoLogo;
  final double anchoItem;

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
  });

  @override
  State<CintaMarcas> createState() => _CintaMarcasState();
}

class _CintaMarcasState extends State<CintaMarcas> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _pausada = false;

  double get _anchoTira => widget.marcas.length * widget.anchoItem;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _duracion())..repeat();
  }

  Duration _duracion() {
    final ms = (_anchoTira / widget.velocidad * 1000).round();
    return Duration(milliseconds: ms < 1000 ? 1000 : ms);
  }

  @override
  void didUpdateWidget(covariant CintaMarcas old) {
    super.didUpdateWidget(old);
    if (old.marcas.length != widget.marcas.length || old.anchoItem != widget.anchoItem) {
      _ctrl.duration = _duracion();
      if (!_pausada) _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _pausar(bool p) {
    if (p == _pausada) return;
    _pausada = p;
    p ? _ctrl.stop() : _ctrl.repeat();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.marcas.isEmpty) return const SizedBox.shrink();
    final alto = widget.altoLogo + 40;
    // Se repite la tira las veces necesarias para cubrir pantallas anchas sin huecos.
    final tira = Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final m in widget.marcas) _item(m)],
    );
    return MouseRegion(
      onEnter: (_) => _pausar(true),
      onExit: (_) => _pausar(false),
      child: SizedBox(
        height: alto,
        child: LayoutBuilder(builder: (context, c) {
          final copias = (c.maxWidth / _anchoTira).ceil() + 1;
          return ShaderMask(
            // Difumina los bordes para que los logos entren y salgan suavemente.
            shaderCallback: (r) => const LinearGradient(
              colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
              stops: [0, 0.07, 0.93, 1],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, child) {
                    final t = widget.haciaLaDerecha ? 1 - _ctrl.value : _ctrl.value;
                    return Transform.translate(offset: Offset(-t * _anchoTira, 0), child: child);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [for (var i = 0; i < copias; i++) tira],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _item(String marca) {
    final logo = logoDeMarca(marca);
    return SizedBox(
      width: widget.anchoItem,
      child: Center(
        child: _LogoCinta(
          nombre: marca,
          logo: logo,
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
