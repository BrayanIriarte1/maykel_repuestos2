import 'package:flutter/material.dart';

import '../config.dart';

/// Ancho máximo del contenido para que no se estire en pantallas grandes.
const double kAnchoMaximo = 1480;

/// Centra el contenido y limita su ancho.
class Centrado extends StatelessWidget {
  final Widget child;
  const Centrado({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kAnchoMaximo),
          child: child,
        ),
      );
}

/// Eleva y agranda levemente el hijo al pasar el mouse.
class HoverLift extends StatefulWidget {
  final Widget Function(BuildContext, bool hover) builder;
  final VoidCallback? onTap;
  const HoverLift({super.key, required this.builder, this.onTap});

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;
  ScrollPosition? _pos;

  // Al desplazarse la página el mouse queda quieto pero el elemento se mueve:
  // Flutter no avisa que salió, así que se apaga el efecto para que no quede «pegado».
  void _alScroll() {
    if (_hover && mounted) setState(() => _hover = false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pos?.removeListener(_alScroll);
    _pos = Scrollable.maybeOf(context)?.position;
    _pos?.addListener(_alScroll);
  }

  @override
  void dispose() {
    _pos?.removeListener(_alScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          offset: _hover ? const Offset(0, -0.025) : Offset.zero,
          child: widget.builder(context, _hover),
        ),
      ),
    );
  }
}

/// Encabezado de sección: kicker rojo, título y una línea de acento.
class TituloSeccion extends StatelessWidget {
  final String kicker;
  final String titulo;
  final bool oscuro;
  const TituloSeccion({
    super.key,
    required this.kicker,
    required this.titulo,
    this.oscuro = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(kicker.toUpperCase(),
            style: TextStyle(
                color: oscuro ? AppColors.yellow : AppColors.red,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 1.8)),
        const SizedBox(height: 8),
        Text(titulo,
            style: TextStyle(
                fontSize: 38,
                height: 1.15,
                fontWeight: FontWeight.w900,
                color: oscuro ? Colors.white : AppColors.char)),
        const SizedBox(height: 14),
        Container(
          width: 76,
          height: 5,
          decoration: BoxDecoration(
              color: AppColors.red, borderRadius: BorderRadius.circular(4)),
        ),
      ],
    );
  }
}

/// Enlace del menú superior: ícono + texto, con subrayado rojo animado al pasar el mouse.
class EnlaceNav extends StatefulWidget {
  final String texto;
  final IconData icono;
  final VoidCallback onTap;
  const EnlaceNav(this.texto, this.icono, this.onTap, {super.key});

  @override
  State<EnlaceNav> createState() => _EnlaceNavState();
}

class _EnlaceNavState extends State<EnlaceNav> {
  bool _hover = false;
  bool _desmontado = false;

  @override
  void dispose() {
    _desmontado = true;
    super.dispose();
  }

  void _poner(bool v) {
    if (!_desmontado && _hover != v) setState(() => _hover = v);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _poner(true),
      onExit: (_) => _poner(false),
      child: GestureDetector(
        onTap: () {
          _poner(false);
          widget.onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _hover ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(widget.icono, size: 18, color: _hover ? AppColors.red : Colors.white54),
                const SizedBox(width: 8),
                Text(widget.texto,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _hover ? Colors.white : Colors.white70)),
              ]),
              const SizedBox(height: 4),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                height: 3,
                width: _hover ? 34 : 0,
                decoration: BoxDecoration(
                    color: AppColors.red, borderRadius: BorderRadius.circular(3)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ícono según la categoría del producto.
IconData iconoCategoria(String categoria) {
  final c = categoria.toLowerCase();
  if (c.contains('filtro')) return Icons.filter_alt_outlined;
  if (c.contains('freno')) return Icons.album_outlined;
  if (c.contains('minero') || c.contains('faena')) return Icons.engineering_outlined;
  if (c.contains('motor') || c.contains('distrib')) return Icons.settings_suggest_outlined;
  if (c.contains('suspens') || c.contains('direcc')) return Icons.swap_vert_circle_outlined;
  if (c.contains('electr')) return Icons.bolt_outlined;
  return Icons.build_circle_outlined;
}
