import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import 'diseno.dart';
import 'efectos.dart';
import 'product_card.dart';

/// Carrusel horizontal de productos con flechas y desplazamiento automático
/// que se detiene mientras el mouse está encima.
class CarruselProductos extends StatefulWidget {
  final List<Repuesto> productos;
  final void Function(Repuesto) onReservar;
  final bool autoplay;

  const CarruselProductos({
    super.key,
    required this.productos,
    required this.onReservar,
    this.autoplay = true,
  });

  @override
  State<CarruselProductos> createState() => _CarruselProductosState();
}

class _CarruselProductosState extends State<CarruselProductos> {
  static const double _ancho = 260;
  static const double _gap = 16;

  final _ctrl = ScrollController();
  Timer? _timer;
  bool _pausa = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) {
      _timer = Timer.periodic(const Duration(seconds: 4), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (!_pausa) _mover(1, ciclico: true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _mover(int dir, {bool ciclico = false}) {
    if (!_ctrl.hasClients || !_ctrl.position.hasContentDimensions) return;
    final paso = (_ancho + _gap) * (MediaQuery.of(context).size.width < 760 ? 1 : 2);
    final max = _ctrl.position.maxScrollExtent;
    var destino = _ctrl.offset + dir * paso;
    if (ciclico && _ctrl.offset >= max - 4 && dir > 0) destino = 0;
    _ctrl.animateTo(destino.clamp(0, max),
        duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
  }

  Widget _flecha(IconData icono, VoidCallback onTap) => Material(
        color: Colors.white,
        elevation: 3,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icono, color: AppColors.char),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _pausa = true,
      onExit: (_) => _pausa = false,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            height: 300,
            child: ListView.separated(
              controller: _ctrl,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: widget.productos.length,
              separatorBuilder: (_, __) => const SizedBox(width: _gap),
              itemBuilder: (_, i) => Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: _ancho,
                  child: ProductCard(
                    producto: widget.productos[i],
                    onReservar: () => widget.onReservar(widget.productos[i]),
                  ),
                ),
              ),
            ),
          ),
          Positioned(left: -14, child: _flecha(Icons.chevron_left, () => _mover(-1))),
          Positioned(right: -14, child: _flecha(Icons.chevron_right, () => _mover(1))),
        ],
      ),
    );
  }
}

/// Bloque con título + carrusel (se oculta si no hay productos).
class SeccionCarrusel extends StatelessWidget {
  final String kicker;
  final String titulo;
  final List<Repuesto> productos;
  final void Function(Repuesto) onReservar;
  final bool oscuro;
  final Widget? lateral;

  const SeccionCarrusel({
    super.key,
    required this.kicker,
    required this.titulo,
    required this.productos,
    required this.onReservar,
    this.oscuro = false,
    this.lateral,
  });

  @override
  Widget build(BuildContext context) {
    if (productos.isEmpty) return const SizedBox.shrink();
    final esAngosto = MediaQuery.of(context).size.width < 760;
    return Container(
      width: double.infinity,
      color: oscuro ? AppColors.char : AppColors.paper,
      padding: EdgeInsets.symmetric(
          horizontal: esAngosto ? 28 : 60, vertical: esAngosto ? 36 : 56),
      child: Centrado(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TituloSeccion(kicker: kicker, titulo: titulo, oscuro: oscuro),
            const SizedBox(height: 24),
            if (lateral == null)
              CarruselProductos(productos: productos, onReservar: onReservar)
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 300, child: lateral),
                  const SizedBox(width: 32),
                  Expanded(
                    child: CarruselProductos(productos: productos, onReservar: onReservar),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Carrusel principal de la portada: una diapositiva grande por producto.
class HeroCarrusel extends StatefulWidget {
  final List<Repuesto> productos;
  final void Function(Repuesto) onReservar;
  const HeroCarrusel({super.key, required this.productos, required this.onReservar});

  @override
  State<HeroCarrusel> createState() => _HeroCarruselState();
}

class _HeroCarruselState extends State<HeroCarrusel> {
  final _ctrl = PageController();
  Timer? _timer;
  int _actual = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (!_ctrl.hasClients || widget.productos.isEmpty) return;
      final sig = (_actual + 1) % widget.productos.length;
      _ctrl.animateToPage(sig,
          duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lista = widget.productos;
    if (lista.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white12),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 14)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: PageView.builder(
            controller: _ctrl,
            onPageChanged: (i) => setState(() => _actual = i),
            itemCount: lista.length,
            itemBuilder: (_, i) => _Diapositiva(
              producto: lista[i],
              onReservar: () => widget.onReservar(lista[i]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            lista.length,
            (i) => GestureDetector(
              onTap: () => _ctrl.animateToPage(i,
                  duration: const Duration(milliseconds: 400), curve: Curves.easeInOut),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _actual ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _actual ? AppColors.red : Colors.white30,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Diapositiva extends StatelessWidget {
  final Repuesto producto;
  final VoidCallback onReservar;
  const _Diapositiva({required this.producto, required this.onReservar});

  @override
  Widget build(BuildContext context) {
    final foto = fotoDe(producto);
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A0D11), Color(0xFF1A1A1C)],
        ),
      ),
      padding: const EdgeInsets.all(26),
      child: Stack(
        children: [
          if (foto != null)
            Positioned(
              right: -26,
              top: -26,
              bottom: -26,
              width: 260,
              child: ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.transparent, Colors.black],
                  stops: [0, 0.55],
                ).createShader(r),
                blendMode: BlendMode.dstIn,
                child: Image(
                  image: foto,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            )
          else
            Positioned(
              right: -20,
              bottom: -30,
              child: Icon(iconoCategoria(producto.categoria),
                  size: 190, color: Colors.white.withValues(alpha: 0.06)),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: AppColors.red, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  producto.categoria.isEmpty ? 'Destacado' : producto.categoria,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              Text(producto.nombre,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.2)),
              const SizedBox(height: 6),
              Text(
                [producto.marca, producto.modelo].where((e) => e.isNotEmpty).join(' · '),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: producto.stock > 0 ? onReservar : null,
                    icon: const Icon(Icons.event_available, size: 18),
                    label: const Text('Agregar a reserva'),
                  ),
                  const SizedBox(width: 12),
                  Text(producto.sku,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11, fontFamily: 'monospace')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
