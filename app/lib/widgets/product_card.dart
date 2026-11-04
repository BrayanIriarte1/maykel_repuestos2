import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import 'efectos.dart';

/// Tarjeta de producto del catálogo público: encabezado con degradado e ícono
/// de la categoría, SKU, insignia de estado, nombre, marca/modelo y botón.
class ProductCard extends StatelessWidget {
  final Repuesto producto;
  final VoidCallback onReservar;

  const ProductCard({
    super.key,
    required this.producto,
    required this.onReservar,
  });

  @override
  Widget build(BuildContext context) {
    final stock = producto.stock;
    final agotado = stock <= 0;

    return HoverLift(
      builder: (context, hover) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: hover ? AppColors.red.withOpacity(0.5) : AppColors.paper2),
          boxShadow: [
            BoxShadow(
              color: hover ? const Color(0x33D91E2B) : const Color(0x14000000),
              blurRadius: hover ? 22 : 10,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 104,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: agotado
                      ? const [Color(0xFF3A3A3D), Color(0xFF1A1A1C)]
                      : const [Color(0xFF4A0F14), Color(0xFF1A1A1C)],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Text(
                      producto.sku,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                  Positioned(right: 0, top: 0, child: _StockBadge(stock: stock)),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 180),
                      scale: hover ? 1.15 : 1,
                      child: Icon(iconoCategoria(producto.categoria),
                          color: Colors.white.withOpacity(0.35), size: 44),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    producto.categoria.isEmpty ? 'General' : producto.categoria,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.red,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 40,
                    child: Text(
                      producto.nombre,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.char,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 16,
                    child: Text(
                      producto.marca.isEmpty
                          ? ''
                          : (producto.modelo.isNotEmpty
                              ? '${producto.marca} · ${producto.modelo}'
                              : producto.marca),
                      style: const TextStyle(fontSize: 12, color: AppColors.steel),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: agotado ? null : onReservar,
                      icon: Icon(agotado ? Icons.block : Icons.event_available, size: 16),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        textStyle: const TextStyle(fontSize: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      label: Text(agotado ? 'Agotado' : 'Reservar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockBadge extends StatelessWidget {
  final num stock;
  const _StockBadge({required this.stock});

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String texto;
    if (stock <= 0) {
      color = AppColors.bad;
      texto = 'Agotado';
    } else if (stock <= 3) {
      color = AppColors.warn;
      texto = 'Últimas $stock';
    } else {
      color = AppColors.ok;
      texto = 'Disponible';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
