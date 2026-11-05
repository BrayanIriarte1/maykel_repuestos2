import 'package:flutter/material.dart';

import 'api_service.dart';
import 'config.dart';
import 'screens/admin_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Si el administrador recarga la página, su sesión se recupera (y se valida
  // con el servidor) antes de dibujar la primera pantalla.
  await ApiService.instance.restaurarSesion();
  runApp(const MaykelRepuestosApp());
}

class MaykelRepuestosApp extends StatefulWidget {
  const MaykelRepuestosApp({super.key});

  @override
  State<MaykelRepuestosApp> createState() => _MaykelRepuestosAppState();
}

class _MaykelRepuestosAppState extends State<MaykelRepuestosApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    ApiService.instance.sesionCerrada.addListener(_alCerrarSesion);
  }

  @override
  void dispose() {
    ApiService.instance.sesionCerrada.removeListener(_alCerrarSesion);
    super.dispose();
  }

  /// El servidor rechazó la sesión (venció o el usuario fue desactivado).
  void _alCerrarSesion() {
    _navigatorKey.currentState?.popUntil((r) => r.isFirst);
    _messengerKey.currentState?.showSnackBar(const SnackBar(
      content: Text('Tu sesión expiró. Inicia sesión nuevamente para continuar.'),
      duration: Duration(seconds: 5),
    ));
  }

  Route<dynamic> _ruta(String nombre) {
    final admin = nombre == '/admin';
    return MaterialPageRoute<void>(
      settings: RouteSettings(name: nombre),
      builder: (_) => admin ? const AdminScreen() : const HomeScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maykel Repuestos',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      // La dirección del navegador refleja dónde estás (#/admin), así que
      // recargar la página te deja en el mismo lugar si la sesión sigue activa.
      onGenerateInitialRoutes: (inicial) => [
        _ruta('/'),
        if (inicial.startsWith('/admin') && ApiService.instance.sesionAdminActiva)
          _ruta('/admin'),
      ],
      onGenerateRoute: (settings) {
        final destino = settings.name ?? '/';
        if (destino.startsWith('/admin') && ApiService.instance.sesionAdminActiva) {
          return _ruta('/admin');
        }
        return _ruta('/');
      },
    );
  }
}
