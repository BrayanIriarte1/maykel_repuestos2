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
  static const double _gap = 18;

  final _ctrl = ScrollController();
  Timer? _timer;
  // Se pausa solo mientras el mouse se mueve encima; si queda quieto (o salió sin aviso) reanuda.
  DateTime _ultimoHover = DateTime.fromMillisecondsSinceEpoch(0);
  bool get _pausa => DateTime.now().difference(_ultimoHover) < const Duration(milliseconds: 1500);
  double _paso = 280;

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
    final max = _ctrl.position.maxScrollExtent;
    var destino = _ctrl.offset + dir * _paso;
    if (ciclico && _ctrl.offset >= max - 4 && dir > 0) destino = 0;
    _ctrl.animateTo(destino.clamp(0, max),
        duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
  }

  Widget _flecha(IconData icono, VoidCallback onTap) => Material(
        color: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icono, color: AppColors.char),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      // Las tarjetas se reparten todo el ancho disponible (más grandes en pantallas amplias).
      final n = c.maxWidth >= 1300 ? 5 : (c.maxWidth >= 980 ? 4 : (c.maxWidth >= 680 ? 3 : (c.maxWidth >= 460 ? 2 : 1)));
      final ancho = (c.maxWidth - _gap * (n - 1)) / n;
      _paso = (ancho + _gap) * (n > 2 ? n - 1 : 1);
      return MouseRegion(
        onHover: (_) => _ultimoHover = DateTime.now(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              height: 330,
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
                    width: ancho,
                    child: ProductCard(
                      producto: widget.productos[i],
                      onReservar: () => widget.onReservar(widget.productos[i]),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(left: -18, child: _flecha(Icons.chevron_left, () => _mover(-1))),
            Positioned(right: -18, child: _flecha(Icons.chevron_right, () => _mover(1))),
          ],
        ),
      );
    });
  }
}

/// Bloque con título + carrusel (se oculta si no hay productos).
class SeccionCarrusel extends StatelessWidget {
  final String kicker;
  final String titulo;
  final List<Repuesto> productos;
  final void Function(Repuesto) onReservar;
  final bool oscuro;
  final bool rojo;
  final Widget? lateral;
  final Widget? accion;

  const SeccionCarrusel({
    super.key,
    required this.kicker,
    required this.titulo,
    required this.productos,
    required this.onReservar,
    this.oscuro = false,
    this.rojo = false,
    this.lateral,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    if (productos.isEmpty) return const SizedBox.shrink();
    final esAngosto = MediaQuery.of(context).size.width < 760;
    final sobreOscuro = oscuro || rojo;
    final fondo = rojo
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF8E1520), Color(0xFF4A0C12), Color(0xFF1F0608)])
        : oscuro
            ? const LinearGradient(colors: [AppColors.char, AppColors.char])
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, AppColors.paper]);
    final cabecera = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: TituloSeccion(kicker: kicker, titulo: titulo, oscuro: sobreOscuro)),
        if (accion != null && !esAngosto) accion!,
      ],
    );
    return Container(
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(gradient: fondo),
      child: Stack(
        children: [
          Positioned(
            right: -140,
            top: -140,
            child: Container(
              width: 420,
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (sobreOscuro ? Colors.white : AppColors.red).withValues(alpha: sobreOscuro ? 0.05 : 0.06),
              ),
            ),
          ),
          Positioned(
            left: -100,
            bottom: -160,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (sobreOscuro ? Colors.black : AppColors.red).withValues(alpha: sobreOscuro ? 0.18 : 0.04),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: esAngosto ? 28 : 60, vertical: esAngosto ? 36 : 84),
            child: Centrado(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cabecera,
                  const SizedBox(height: 40),
                  if (lateral == null)
                    CarruselProductos(productos: productos, onReservar: onReservar)
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 340, child: lateral),
                        const SizedBox(width: 36),
                        Expanded(
                          child: CarruselProductos(productos: productos, onReservar: onReservar),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Carrusel principal de la portada: una diapositiva grande por producto.
class HeroCarrusel extends StatefulWidget {
  final List<Repuesto> productos;
  final void Function(Repuesto) onReservar;
  final double alto;
  const HeroCarrusel(
      {super.key, required this.productos, required this.onReservar, this.alto = 300});

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
          height: widget.alto,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white12),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 36, offset: Offset(0, 18)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: PageView.builder(
            controller: _ctrl,
            onPageChanged: (i) => setState(() => _actual = i),
            itemCount: lista.length,
            itemBuilder: (_, i) => _Diapositiva(
              producto: lista[i],
              grande: widget.alto > 340,
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
  final bool grande;
  const _Diapositiva(
      {required this.producto, required this.onReservar, this.grande = false});

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
      padding: EdgeInsets.all(grande ? 36 : 26),
      child: Stack(
        children: [
          if (foto != null)
            Positioned(
              right: -26,
              top: -26,
              bottom: -26,
              width: grande ? 460 : 260,
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
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: grande ? 32 : 22,
                      fontWeight: FontWeight.w800,
                      height: 1.2)),
              const SizedBox(height: 6),
              Text(
                [producto.marca, producto.modelo].where((e) => e.isNotEmpty).join(' · '),
                style: TextStyle(color: Colors.white70, fontSize: grande ? 16 : 13),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: producto.stock > 0 ? onReservar : null,
                    style: grande
                        ? ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
                            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                          )
                        : null,
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
