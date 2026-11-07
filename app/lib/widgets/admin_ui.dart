import 'package:flutter/material.dart';

import '../config.dart';
import 'portada_extra.dart';

/// Paleta y piezas visuales compartidas por todo el panel de administración.
class AdminColores {
  static const azul = [Color(0xFF3B82C4), Color(0xFF1B4F8A)];
  static const verde = [Color(0xFF2EB88A), Color(0xFF14785C)];
  static const ambar = [Color(0xFFFFC145), Color(0xFFF08A00)];
  static const violeta = [Color(0xFF9B6BD8), Color(0xFF5A2FA0)];
  static const rojo = [Color(0xFFE53945), Color(0xFF9E1119)];
  static const gris = [Color(0xFF6B7585), Color(0xFF38404D)];

  static const fondo = Color(0xFFF4F1EC);
  static const borde = Color(0xFFE9E4DA);
}

/// Limita el ancho del contenido en pantallas muy anchas y lo centra.
class AdminAncho extends StatelessWidget {
  final Widget child;
  final double max;
  const AdminAncho({super.key, required this.child, this.max = 1680});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child),
      );
}

/// Tarjeta blanca con cabecera (ícono, título, acción) para agrupar contenido.
class AdminPanel extends StatelessWidget {
  final String? titulo;
  final String? subtitulo;
  final IconData? icono;
  final List<Color> colores;
  final Widget? accion;
  final Widget child;
  final EdgeInsets padding;
  const AdminPanel({
    super.key,
    this.titulo,
    this.subtitulo,
    this.icono,
    this.colores = AdminColores.rojo,
    this.accion,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AdminColores.borde),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (titulo != null) ...[
            Row(children: [
              if (icono != null) ...[
                InsigniaIcono(icono: icono, tam: 40, colores: colores),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titulo!,
                      style: const TextStyle(
                          fontSize: 16.5, fontWeight: FontWeight.w900, color: AppColors.char)),
                  if (subtitulo != null)
                    Text(subtitulo!,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.steel)),
                ]),
              ),
              if (accion != null) accion!,
            ]),
            const SizedBox(height: 18),
          ],
          child,
        ],
      ),
    );
  }
}

/// Indicador grande con ícono en degradado y valor destacado.
class KpiTile extends StatelessWidget {
  final String valor;
  final String etiqueta;
  final IconData icono;
  final List<Color> colores;
  final String? nota;
  final VoidCallback? onTap;
  const KpiTile({
    super.key,
    required this.valor,
    required this.etiqueta,
    required this.icono,
    this.colores = AdminColores.rojo,
    this.nota,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.hardEdge,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AdminColores.borde),
            boxShadow: [
              BoxShadow(color: colores.first.withValues(alpha: 0.12), blurRadius: 22, offset: const Offset(0, 10)),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -22,
                bottom: -26,
                child: Icon(icono, size: 110, color: colores.first.withValues(alpha: 0.07)),
              ),
              Row(children: [
                InsigniaIcono(icono: icono, tam: 54, colores: colores),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(valor,
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.char, height: 1.05)),
                    ),
                    const SizedBox(height: 2),
                    Text(etiqueta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.steel, height: 1.25)),
                    if (nota != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(nota!,
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800, color: colores.last)),
                      ),
                  ]),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Etiqueta de estado (Disponible, Pendiente, etc.).
class PillEstado extends StatelessWidget {
  final String texto;
  final Color color;
  final IconData? icono;
  const PillEstado(this.texto, this.color, {super.key, this.icono});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icono != null) ...[Icon(icono, size: 13, color: color), const SizedBox(width: 5)],
          Text(texto, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
        ]),
      );
}

/// Banner de bienvenida o de sección con degradado oscuro y círculos decorativos.
class AdminHero extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final IconData icono;
  final Widget? derecha;
  final List<Color> colores;
  const AdminHero({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    this.derecha,
    this.colores = const [Color(0xFF1A1A1C), Color(0xFF5A0F16)],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(colors: colores, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 26, offset: Offset(0, 12))],
      ),
      child: Stack(
        children: [
          Positioned(
              right: -40,
              top: -60,
              child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)))),
          Positioned(
              right: 120,
              bottom: -90,
              child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.red.withValues(alpha: 0.18)))),
          Row(children: [
            InsigniaIcono(icono: icono, tam: 62),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, height: 1.15)),
                const SizedBox(height: 4),
                Text(subtitulo, style: const TextStyle(color: Colors.white70, fontSize: 14.5)),
              ]),
            ),
            if (derecha != null) derecha!,
          ]),
        ],
      ),
    );
  }
}

/// Mensaje cuando no hay datos.
class VacioAdmin extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String? texto;
  final Widget? accion;
  const VacioAdmin({super.key, required this.icono, required this.titulo, this.texto, this.accion});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icono, size: 52, color: AppColors.red.withValues(alpha: 0.35)),
            const SizedBox(height: 12),
            Text(titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.char)),
            if (texto != null) ...[
              const SizedBox(height: 6),
              Text(texto!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.steel)),
            ],
            if (accion != null) ...[const SizedBox(height: 16), accion!],
          ]),
        ),
      );
}

/// Barra horizontal de progreso con etiqueta (para distribuciones).
class BarraProgreso extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final double fraccion;
  final Color color;
  const BarraProgreso(
      {super.key, required this.etiqueta, required this.valor, required this.fraccion, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Text(etiqueta,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.char))),
            Text(valor, style: const TextStyle(fontSize: 13, color: AppColors.steel, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraccion.clamp(0, 1).toDouble()),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                minHeight: 9,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ]),
      );
}
