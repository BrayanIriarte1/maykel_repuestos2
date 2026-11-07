import 'package:flutter/foundation.dart';

import '../models.dart';

typedef LineaReserva = ({Repuesto producto, int cantidad});

/// Lista de reserva del cliente (HU-03). Vive solo en memoria: no se guarda
/// nada en el almacenamiento del navegador.
class CarritoReserva extends ChangeNotifier {
  CarritoReserva._();
  static final CarritoReserva instance = CarritoReserva._();

  final Map<int, LineaReserva> _lineas = {};

  List<LineaReserva> get lineas => _lineas.values.toList();
  bool get vacio => _lineas.isEmpty;
  int get totalUnidades => _lineas.values.fold(0, (s, l) => s + l.cantidad);

  int _tope(Repuesto p) => p.stock.toInt().clamp(1, 999);

  /// Suma [cantidad] al producto (sin superar el stock). Devuelve false si ya
  /// estaba en el máximo disponible.
  bool agregar(Repuesto p, {int cantidad = 1}) {
    final actual = _lineas[p.id]?.cantidad ?? 0;
    final nueva = (actual + cantidad).clamp(1, _tope(p));
    if (nueva == actual) return false;
    _lineas[p.id] = (producto: p, cantidad: nueva);
    notifyListeners();
    return true;
  }

  void cambiarCantidad(int id, int cantidad) {
    final l = _lineas[id];
    if (l == null) return;
    _lineas[id] = (producto: l.producto, cantidad: cantidad.clamp(1, _tope(l.producto)));
    notifyListeners();
  }

  void quitar(int id) {
    if (_lineas.remove(id) != null) notifyListeners();
  }

  void limpiar() {
    if (_lineas.isEmpty) return;
    _lineas.clear();
    notifyListeners();
  }
}
