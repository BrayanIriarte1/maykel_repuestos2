import 'package:flutter/material.dart';

import '../api_service.dart';
import '../config.dart';

/// Muestra el diálogo de acceso al panel admin. Devuelve `true` si el login
/// fue exitoso, `false`/`null` en caso contrario.
Future<bool?> mostrarLoginAdmin(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _AdminLoginDialog(),
  );
}

class _AdminLoginDialog extends StatefulWidget {
  const _AdminLoginDialog();

  @override
  State<_AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<_AdminLoginDialog> {
  final _usuarioCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _verificando = false;
  bool _error = false;
  bool _ocultar = true;
  String? _mensajeError;

  @override
  void dispose() {
    _usuarioCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    final usuario = _usuarioCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (usuario.isEmpty || password.isEmpty) {
      setState(() => _error = true);
      return;
    }
    setState(() {
      _verificando = true;
      _error = false;
    });

    bool ok = false;
    try {
      ok = await ApiService.instance.loginAdmin(usuario, password);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _verificando = false;
        _error = true;
        _mensajeError = e.mensaje;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _verificando = false);

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _error = true;
        _mensajeError = null;
      });
    }
  }

  Widget _formulario() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Bienvenido',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900, color: AppColors.char),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
        const Text('Ingresa para gestionar stock, reservas y ventas.',
            style: TextStyle(color: AppColors.steel, fontSize: 13)),
        const SizedBox(height: 22),
        TextField(
          controller: _usuarioCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Usuario',
            prefixIcon: Icon(Icons.person_outline),
          ),
          onSubmitted: (_) => _entrar(),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passwordCtrl,
          decoration: InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_ocultar ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _ocultar = !_ocultar),
            ),
          ),
          obscureText: _ocultar,
          onSubmitted: (_) => _entrar(),
        ),
        if (_error) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.bad.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(Icons.error_outline, size: 18, color: AppColors.bad),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _mensajeError ?? 'Usuario o contraseña incorrectos.',
                  style: TextStyle(color: AppColors.bad, fontSize: 12.5),
                ),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 22),
        ElevatedButton(
          onPressed: _verificando ? null : _entrar,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          ),
          child: _verificando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Entrar al panel'),
        ),
      ],
    );
  }

  Widget _panelMarca() {
    const items = [
      (Icons.inventory_2_outlined, 'Control de stock en tiempo real'),
      (Icons.event_available_outlined, 'Gestión de reservas online'),
      (Icons.point_of_sale_outlined, 'Registro rápido de ventas'),
    ];
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A1C), Color(0xFF2B1013), AppColors.red],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/images/logo_maykel.jpg', fit: BoxFit.contain),
          ),
          const SizedBox(height: 28),
          const Text('Panel de administración',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Icon(it.$1, color: AppColors.yellow, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(it.$2,
                        style: const TextStyle(color: Colors.white70, fontSize: 13))),
              ]),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final ancha = ancho >= 720;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ancha ? 760 : 400),
        child: ancha
            ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: _panelMarca()),
                    Expanded(
                      flex: 6,
                      child: Padding(padding: const EdgeInsets.all(28), child: _formulario()),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                child: Padding(padding: const EdgeInsets.all(24), child: _formulario()),
              ),
      ),
    );
  }
}
