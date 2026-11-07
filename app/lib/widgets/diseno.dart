import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../config.dart';
import '../models.dart';
import 'efectos.dart';
import 'portada_extra.dart';

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
  // Se decodifican reducidas (600 px) para que las listas largas no pesen ni se traben.
  final propia = p.imagenAbsoluta;
  if (propia != null) return ResizeImage.resizeIfNeeded(600, null, NetworkImage(propia));
  final ref = imagenReferencial(p.categoria, p.nombre);
  return ref == null ? null : ResizeImage.resizeIfNeeded(600, null, AssetImage(ref));
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
// Tarjeta de marca con logo (se vuelve a color y sube al pasar el mouse)
// ---------------------------------------------------------------------------

const Map<String, String> _logosMarca = {
  'CHERY': 'chery',
  'GREAT WALL': 'great-wall',
  'CHANGAN': 'changan',
  'JAC': 'jac',
  'MAXUS': 'maxus',
  'MG': 'mg',
  'GEELY': 'geely',
  'BRILLIANCE': 'brilliance',
  'BYD': 'byd',
  'LIFAN': 'lifan',
  'BAIC': 'baic-motor',
  'MAHINDRA': 'mahindra',
  'JMC': 'jmc',
  'HAVAL': 'haval',
  'FOTON': 'foton',
  'HYUNDAI': 'hyundai',
  'HAIMA': 'haima',
  'ZOTYE': 'zotye',
  'CHEVROLET': 'chevrolet',
  'NISSAN': 'nissan',
  'FAW': 'faw',
  'TOYOTA': 'toyota',
  'HAFEI': 'hafei',
  'SSANGYONG': 'ssangyong',
  'DONGFENG': 'dongfeng',
  'JETOUR': 'jetour',
};

/// Ruta del logo de la marca (assets/images/marcas) o null si no hay.
String? logoDeMarca(String nombre) {
  final slug = _logosMarca[nombre.trim().toUpperCase()];
  return slug == null ? null : 'assets/images/marcas/$slug.png';
}

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

  static const _gris = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final logo = logoDeMarca(nombre);
    return HoverLift(
      onTap: onTap,
      builder: (_, hover) {
        final activa = hover || seleccionada;
        final inicial = nombre.isEmpty ? '?' : nombre.trim()[0].toUpperCase();
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 168,
          height: 168,
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: activa ? AppColors.red : AppColors.paper2, width: activa ? 2 : 1.4),
            boxShadow: [
              BoxShadow(
                color: (activa ? AppColors.red : Colors.black).withValues(alpha: activa ? 0.22 : 0.05),
                blurRadius: activa ? 26 : 10,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 70,
                child: AnimatedScale(
                  scale: activa ? 1.12 : 1,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: logo == null
                      ? Container(
                          width: 64,
                          height: 64,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                                colors: [AppColors.red, AppColors.redDark],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight),
                          ),
                          child: Text(inicial,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                        )
                      : AnimatedOpacity(
                          opacity: activa ? 1 : 0.8,
                          duration: const Duration(milliseconds: 220),
                          child: ColorFiltered(
                            colorFilter: activa ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : _gris,
                            child: Image.asset(logo,
                                height: 70,
                                width: 110,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.medium,
                                errorBuilder: (_, __, ___) => const Icon(Icons.directions_car_filled_rounded,
                                    size: 40, color: AppColors.red)),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    nombre.toUpperCase(),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                      color: activa ? AppColors.red : AppColors.char,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text('$total productos',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.steel)),
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

const List<List<Color>> _paleta = [
  [Color(0xFFC0392B), Color(0xFF6A1B14)],
  [Color(0xFF2B6CB0), Color(0xFF14315A)],
  [Color(0xFF1E8E78), Color(0xFF0B3D34)],
  [Color(0xFFD98A0B), Color(0xFF6B3E04)],
  [Color(0xFF7B4BB5), Color(0xFF331B58)],
  [Color(0xFF4F6D7A), Color(0xFF1B2A31)],
];

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
                  child: Image.asset(foto, fit: BoxFit.cover, cacheWidth: 700),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _paleta[nombre.hashCode.abs() % _paleta.length]),
                  ),
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: AnimatedScale(
                        scale: hover ? 1.15 : 1,
                        duration: const Duration(milliseconds: 300),
                        child: Icon(iconoCategoria(nombre),
                            size: 84, color: Colors.white.withValues(alpha: 0.28)),
                      ),
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
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: hover ? AppColors.red : AppColors.paper2, width: 1.6),
          boxShadow: [
            BoxShadow(
                color: (hover ? AppColors.red : Colors.black).withValues(alpha: hover ? 0.16 : 0.06),
                blurRadius: hover ? 30 : 14,
                offset: const Offset(0, 10)),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              right: -18,
              bottom: -22,
              child: Icon(icono, size: 130, color: AppColors.red.withValues(alpha: hover ? 0.10 : 0.05)),
            ),
            Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: hover ? 1.08 : 1,
              duration: const Duration(milliseconds: 220),
              child: InsigniaIcono(icono: icono, tam: 72),
            ),
            const SizedBox(height: 22),
            Text(titulo,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.char)),
            const SizedBox(height: 8),
            Text(texto,
                style: const TextStyle(color: AppColors.steel, fontSize: 15, height: 1.55)),
            const SizedBox(height: 18),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(boton,
                  style: const TextStyle(
                      color: AppColors.red, fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(width: 6),
              AnimatedSlide(
                offset: hover ? const Offset(0.4, 0) : Offset.zero,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.arrow_forward, size: 18, color: AppColors.red),
              ),
            ]),
          ],
        ),
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
      padding: const EdgeInsets.all(34),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white24),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -4,
            top: -26,
            child: Text('$numero',
                style: TextStyle(
                    fontSize: 150,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withValues(alpha: 0.07),
                    height: 1)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  InsigniaIcono(icono: icono, tam: 76),
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: Color(0xFFFFC145), shape: BoxShape.circle),
                      child: Text('$numero',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, color: AppColors.char, fontSize: 15)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(titulo,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(texto,
                  style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.55)),
            ],
          ),
        ],
      ),
    );
  }
}
