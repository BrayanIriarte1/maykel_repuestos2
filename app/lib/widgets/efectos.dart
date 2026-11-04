import 'package:flutter/material.dart';

import '../config.dart';

/// Ancho máximo del contenido para que no se estire en pantallas grandes.
const double kAnchoMaximo = 1200;

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
                fontSize: 12,
                letterSpacing: 1.6)),
        const SizedBox(height: 8),
        Text(titulo,
            style: TextStyle(
                fontSize: 30,
                height: 1.15,
                fontWeight: FontWeight.w900,
                color: oscuro ? Colors.white : AppColors.char)),
        const SizedBox(height: 12),
        Container(
          width: 56,
          height: 4,
          decoration: BoxDecoration(
              color: AppColors.red, borderRadius: BorderRadius.circular(4)),
        ),
      ],
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
