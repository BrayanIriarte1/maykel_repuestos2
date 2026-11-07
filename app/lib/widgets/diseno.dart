import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../config.dart';
import '../models.dart';
import 'efectos.dart';

// ---------------------------------------------------------------------------
// Fotos referenciales por tipo de repuesto
// ---------------------------------------------------------------------------

String _norm(String s) => s
    .toLowerCase()
    .replaceAll('á', 'a')
    .replaceAll('é', 'e')
    .replaceAll('í', 'i')
    .replaceAll('ó', 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ñ', 'n');

// El orden importa: las reglas más específicas van primero.
const List<(List<String>, String)> _reglasImagen = [
  (['filtro aceite', 'filtro de aceite'], 'filtro_aceite'),
  (['filtro aire', 'filtro de aire'], 'filtro_aire'),
  (['polen', 'cabina'], 'filtro_polen'),
  (['combustible'], 'combustible'),
  (['filtro'], 'filtro_aire'),
  (['pastilla', 'freno', 'balata', 'zapata'], 'frenos'),
  (['embrague'], 'embrague'),
  (['amortigu', 'bieleta', 'espiral', 'resorte', 'suspens'], 'amortiguador'),
  (['bater'], 'bateria'),
  (['aceite', 'lubric'], 'aceites'),
  (['bulbo', 'farol', 'neblinero', 'optico', 'ampolleta', 'luz', 'foco', 'faro'], 'luces'),
  (['espejo'], 'espejos'),
  (['terminal', 'direccion', 'rotula', 'axial', 'homocinet', 'cremallera', 'bandeja', 'maza', 'rodamiento'], 'direccion'),
  (['bobina', 'bujia', 'encendido'], 'encendido'),
  (['distribucion', 'correa', 'polea', 'tensor'], 'distribucion'),
  (['radiador', 'termostato', 'bomba agua', 'manguera', 'deposito agua', 'refriger', 'ventilador'], 'radiador'),
  (['empaquet', 'culata'], 'empaquetadura'),
];

/// Foto referencial según la categoría o el nombre del repuesto (null si no hay una adecuada).
String? imagenReferencial(String categoria, String nombre) {
  for (final texto in [_norm(categoria), _norm(nombre)]) {
    for (final r in _reglasImagen) {
      if (r.$1.any(texto.contains)) return 'assets/images/repuestos/${r.$2}.jpg';
    }
  }
  return null;
}

/// Foto a mostrar para un repuesto: la propia (si ya la subieron) o una referencial.
ImageProvider? fotoDe(Repuesto p) {
  final propia = p.imagenAbsoluta;
  if (propia != null) return NetworkImage(propia);
  final ref = imagenReferencial(p.categoria, p.nombre);
  return ref == null ? null : AssetImage(ref);
}

bool esFotoReferencial(Repuesto p) =>
    p.imagenAbsoluta == null && imagenReferencial(p.categoria, p.nombre) != null;

// ---------------------------------------------------------------------------
// Aparición suave al hacer scroll
// ---------------------------------------------------------------------------

/// Muestra el contenido con un fundido y un leve desplazamiento la primera vez
/// que entra en pantalla.
class Revelar extends StatefulWidget {
  final Widget child;
  final int retrasoMs;
  const Revelar({super.key, required this.child, this.retrasoMs = 0});

  @override
  State<Revelar> createState() => _RevelarState();
}

class _RevelarState extends State<Revelar> {
  bool _visible = false;
  ScrollPosition? _pos;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pos?.removeListener(_revisar);
    _pos = Scrollable.maybeOf(context)?.position;
    _pos?.addListener(_revisar);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisar());
  }

  @override
  void dispose() {
    _pos?.removeListener(_revisar);
    super.dispose();
  }

  void _revisar() {
    if (_visible || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final arriba = box.localToGlobal(Offset.zero).dy;
    if (arriba < MediaQuery.of(context).size.height * 0.92) {
      _pos?.removeListener(_revisar);
      Future.delayed(Duration(milliseconds: widget.retrasoMs), () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.05),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Marquesina (cinta de avisos que se desplaza sola)
// ---------------------------------------------------------------------------

class Marquesina extends StatefulWidget {
  final List<Widget> items;
  final double alto;
  final double velocidad; // píxeles por segundo
  final Color fondo;
  const Marquesina({
    super.key,
    required this.items,
    this.alto = 44,
    this.velocidad = 45,
    this.fondo = AppColors.char,
  });

  @override
  State<Marquesina> createState() => _MarquesinaState();
}

class _MarquesinaState extends State<Marquesina> with SingleTickerProviderStateMixin {
  final _ctrl = ScrollController();
  late final Ticker _ticker;
  Duration _ultimo = Duration.zero;
  bool _pausa = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((t) {
      final dt = (t - _ultimo).inMicroseconds / 1e6;
      _ultimo = t;
      if (_pausa || !_ctrl.hasClients || !_ctrl.position.hasContentDimensions) return;
      _ctrl.jumpTo(_ctrl.offset + widget.velocidad * dt.clamp(0, 0.1));
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return MouseRegion(
      onEnter: (_) => _pausa = true,
      onExit: (_) => _pausa = false,
      child: Container(
        height: widget.alto,
        color: widget.fondo,
        child: ListView.builder(
          controller: _ctrl,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (_, i) => Center(child: widget.items[i % widget.items.length]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de marca (estilo "wordmark")
// ---------------------------------------------------------------------------

class TarjetaMarca extends StatelessWidget {
  final String nombre;
  final int total;
  final VoidCallback onTap;
  final bool seleccionada;
  const TarjetaMarca({
    super.key,
    required this.nombre,
    required this.total,
    required this.onTap,
    this.seleccionada = false,
  });

  @override
  Widget build(BuildContext context) {
    return HoverLift(
      onTap: onTap,
      builder: (_, hover) {
        final activa = hover || seleccionada;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 112,
          height: 112,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: activa ? AppColors.red : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: activa ? AppColors.red : AppColors.red.withValues(alpha: 0.35), width: 1.6),
            boxShadow: [
              BoxShadow(
                color: (activa ? AppColors.red : Colors.black).withValues(alpha: activa ? 0.28 : 0.05),
                blurRadius: activa ? 20 : 8,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.directions_car_filled_rounded,
                  size: 22, color: activa ? Colors.white70 : AppColors.red.withValues(alpha: 0.55)),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    nombre.toUpperCase(),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                      color: activa ? Colors.white : AppColors.red,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text('$total productos',
                  style: TextStyle(
                      fontSize: 10.5, color: activa ? Colors.white70 : AppColors.steel)),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta de categoría con foto
// ---------------------------------------------------------------------------

class TarjetaCategoria extends StatelessWidget {
  final String nombre;
  final int total;
  final VoidCallback onTap;
  final double alto;
  const TarjetaCategoria({
    super.key,
    required this.nombre,
    required this.total,
    required this.onTap,
    this.alto = 170,
  });

  @override
  Widget build(BuildContext context) {
    final foto = imagenReferencial(nombre, '');
    return HoverLift(
      onTap: onTap,
      builder: (_, hover) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: alto,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (foto != null)
                AnimatedScale(
                  scale: hover ? 1.1 : 1,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeOut,
                  child: Image.asset(foto, fit: BoxFit.cover),
                )
              else
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4A0F14), AppColors.char]),
                  ),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Icon(iconoCategoria(nombre),
                          size: 64, color: Colors.white.withValues(alpha: 0.12)),
                    ),
                  ),
                ),
              // Tratamiento común (oscuro con tono rojo) para que fotos de distintos
              // orígenes se vean como una sola colección.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.red.withValues(alpha: hover ? 0.10 : 0.22),
                      AppColors.char.withValues(alpha: 0.92),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            height: 1.15)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(
                        child: Text('$total disponibles',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: hover ? AppColors.red : Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_forward, size: 14, color: Colors.white),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjeta informativa (fila de accesos de la portada)
// ---------------------------------------------------------------------------

class TarjetaInfo extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String texto;
  final String boton;
  final VoidCallback onTap;
  const TarjetaInfo({
    super.key,
    required this.icono,
    required this.titulo,
    required this.texto,
    required this.boton,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverLift(
      onTap: onTap,
      builder: (_, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: hover ? AppColors.red : AppColors.paper2, width: 1.4),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: hover ? 0.12 : 0.05),
                blurRadius: hover ? 22 : 10,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.red, AppColors.redDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icono, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 16),
            Text(titulo,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.char)),
            const SizedBox(height: 6),
            Text(texto,
                style: const TextStyle(color: AppColors.steel, fontSize: 13, height: 1.5)),
            const SizedBox(height: 14),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(boton,
                  style: const TextStyle(
                      color: AppColors.red, fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(width: 4),
              AnimatedSlide(
                offset: hover ? const Offset(0.3, 0) : Offset.zero,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.arrow_forward, size: 15, color: AppColors.red),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Paso numerado ("Cómo reservar")
// ---------------------------------------------------------------------------

class PasoReserva extends StatelessWidget {
  final int numero;
  final IconData icono;
  final String titulo;
  final String texto;
  const PasoReserva({
    super.key,
    required this.numero,
    required this.icono,
    required this.titulo,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -4,
            top: -18,
            child: Text('$numero',
                style: TextStyle(
                    fontSize: 110,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withValues(alpha: 0.06),
                    height: 1)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration:
                    BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(14)),
                child: Icon(icono, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 16),
              Text(titulo,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(texto,
                  style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
            ],
          ),
        ],
      ),
    );
  }
}
