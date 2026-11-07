import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_service.dart';
import '../config.dart';
import 'admin_config_widgets.dart';
import 'admin_ui.dart';
import 'portada_extra.dart';

String _txt(Object? v) => (v ?? '').toString();

List<String> _lista(Object? v) =>
    v is List ? v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() : <String>[];

String _fmtFechaSync(String iso) {
  final f = DateTime.tryParse(iso)?.toLocal();
  if (f == null) return iso;
  String d2(int n) => n.toString().padLeft(2, '0');
  return '${d2(f.day)}/${d2(f.month)}/${f.year} ${d2(f.hour)}:${d2(f.minute)}';
}

String _hace(String iso) {
  final f = DateTime.tryParse(iso)?.toLocal();
  if (f == null) return '';
  final d = DateTime.now().difference(f);
  if (d.inMinutes < 1) return 'hace un momento';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  return 'hace ${d.inDays} ${d.inDays == 1 ? 'día' : 'días'}';
}

/// Color y texto para el estado que guarda el servidor en cada sincronización.
(Color, String, IconData) _estadoSync(String estado) {
  final e = estado.toUpperCase();
  if (e == 'EXITOSO') return (AppColors.ok, 'Exitoso', Icons.check_circle_outline);
  if (e == 'RECHAZADO') return (AppColors.bad, 'Rechazado', Icons.block);
  if (e.contains('ERROR') || e.contains('FALL')) return (AppColors.bad, 'Con error', Icons.error_outline);
  if (e.contains('CURSO')) return (const Color(0xFF1B4F8A), 'En curso', Icons.sync);
  return (AppColors.warn, estado.isEmpty ? 'Sin estado' : estado, Icons.info_outline);
}

/// Sección «Notificaciones y sincronización» de Configuración: estado de los
/// canales de aviso (correo / WhatsApp), pruebas de envío y sincronización
/// manual con el sistema del cliente. Es autónoma: llama directo a ApiService.
class NotificacionesSyncPanel extends StatefulWidget {
  /// Estado, pruebas de envío y guía de correo (permiso «configuracion»).
  final bool verNotificaciones;

  /// Sincronización con el sistema del cliente (permiso «stock»).
  final bool verSincronizacion;
  const NotificacionesSyncPanel({super.key, this.verNotificaciones = true, this.verSincronizacion = true});

  @override
  State<NotificacionesSyncPanel> createState() => _NotificacionesSyncPanelState();
}

class _NotificacionesSyncPanelState extends State<NotificacionesSyncPanel> {
  Map<String, dynamic>? _estado;
  String? _errorEstado;
  bool _cargandoEstado = true;

  final _destinoCtrl = TextEditingController();
  bool _probandoCorreo = false;
  bool _probandoWa = false;
  Map<String, dynamic>? _resCorreo;
  Map<String, dynamic>? _resWa;

  bool? _guiaAbierta;

  bool _cargandoHist = true;
  bool _enCurso = false;
  List<Map<String, dynamic>> _items = [];
  String? _errorHist;
  bool _iniciando = false;
  String? _msgSync;
  bool _msgSyncError = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.verNotificaciones) _cargarEstado();
    if (widget.verSincronizacion) _cargarHistorial();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _destinoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarEstado() async {
    setState(() {
      _cargandoEstado = true;
      _errorEstado = null;
    });
    try {
      final e = await ApiService.instance.getEstadoNotificaciones();
      if (!mounted) return;
      setState(() {
        _estado = e;
        _cargandoEstado = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorEstado = '$e';
        _cargandoEstado = false;
      });
    }
  }

  Future<void> _cargarHistorial() async {
    try {
      final h = await ApiService.instance.getHistorialSync();
      if (!mounted) return;
      setState(() {
        _items = h.items;
        _enCurso = h.enCurso;
        _errorHist = null;
        _cargandoHist = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorHist = '$e';
        _cargandoHist = false;
      });
    }
    _programarRefresco();
  }

  /// Mientras haya una sincronización en curso se vuelve a consultar cada 5 s.
  void _programarRefresco() {
    _timer?.cancel();
    if (!mounted || !_enCurso) return;
    _timer = Timer(const Duration(seconds: 5), _cargarHistorial);
  }

  Future<void> _sincronizar() async {
    setState(() {
      _iniciando = true;
      _msgSync = null;
    });
    try {
      final msg = await ApiService.instance.ejecutarSincronizacion();
      if (!mounted) return;
      setState(() {
        _msgSync = msg;
        _msgSyncError = false;
        _enCurso = true;
      });
      _programarRefresco();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msgSync = '$e';
        _msgSyncError = true;
      });
    } finally {
      if (mounted) setState(() => _iniciando = false);
    }
  }

  Future<void> _probar(String canal) async {
    final esCorreo = canal == 'correo';
    final destino = _destinoCtrl.text.trim();
    if (esCorreo && destino.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(destino)) {
      setState(() => _resCorreo = {'ok': false, 'error': 'El correo de destino no es válido.'});
      return;
    }
    setState(() {
      if (esCorreo) {
        _probandoCorreo = true;
        _resCorreo = null;
      } else {
        _probandoWa = true;
        _resWa = null;
      }
    });
    Map<String, dynamic> res;
    try {
      res = await ApiService.instance.probarNotificacion(canal, destino: esCorreo ? destino : null);
    } catch (e) {
      res = {'ok': false, 'error': '$e'};
    }
    if (!mounted) return;
    setState(() {
      if (esCorreo) {
        _probandoCorreo = false;
        _resCorreo = res;
      } else {
        _probandoWa = false;
        _resWa = res;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final correo = (_estado?['correo'] as Map?)?.cast<String, dynamic>();
    final wa = (_estado?['whatsapp'] as Map?)?.cast<String, dynamic>();
    final correoOk = correo?['configurado'] == true;
    final guiaAbierta = _guiaAbierta ?? (_estado != null && !correoOk);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.verNotificaciones)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: CfgAviso(
              texto: 'Tu rol no tiene permiso para ver ni probar las notificaciones.',
              color: AppColors.warn,
              icono: Icons.lock_outline,
            ),
          ),
        if (widget.verNotificaciones) ..._bloqueNotificaciones(correo, wa, guiaAbierta),
        if (widget.verSincronizacion)
          _panelSync()
        else
          const CfgAviso(
            texto: 'Tu rol no tiene permiso para sincronizar con el sistema del cliente (requiere acceso a Stock).',
            color: AppColors.warn,
            icono: Icons.lock_outline,
          ),
      ],
    );
  }

  List<Widget> _bloqueNotificaciones(Map<String, dynamic>? correo, Map<String, dynamic>? wa, bool guiaAbierta) {
    return [
        if (_errorEstado != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: CfgAviso(
              texto: _errorEstado!,
              color: AppColors.bad,
              icono: Icons.error_outline,
              accion: TextButton(onPressed: _cargarEstado, child: const Text('Reintentar')),
            ),
          ),
        CfgCuadricula(
          minAncho: 460,
          maxColumnas: 2,
          espacio: 18,
          children: [
            _tarjetaCorreo(correo),
            _tarjetaWhatsapp(wa),
          ],
        ),
        const SizedBox(height: 18),
        AdminPanel(
          titulo: 'Cómo obtener la contraseña de aplicación de Google',
          subtitulo: 'Necesaria para que el servidor envíe correos con Gmail (SMTP_PASS)',
          icono: Icons.vpn_key_outlined,
          colores: AdminColores.ambar,
          accion: TextButton.icon(
            onPressed: () => setState(() => _guiaAbierta = !guiaAbierta),
            icon: Icon(guiaAbierta ? Icons.expand_less : Icons.expand_more, size: 20),
            label: Text(guiaAbierta ? 'Ocultar guía' : 'Ver guía'),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: guiaAbierta ? const _GuiaGoogle() : const SizedBox(width: double.infinity),
          ),
        ),
        const SizedBox(height: 18),
    ];
  }

  // ---------------------------------------------------------------
  // Tarjetas de estado
  // ---------------------------------------------------------------

  Widget _tarjetaCorreo(Map<String, dynamic>? c) {
    final destinatarios = _lista(c?['destinatarios']);
    return _TarjetaCanal(
      logo: const InsigniaIcono(icono: Icons.mail_outline, tam: 46, colores: AdminColores.azul),
      titulo: 'Correo electrónico',
      subtitulo: 'Avisa al equipo cuando entra una reserva',
      cargando: _cargandoEstado && c == null,
      configurado: c == null ? null : c['configurado'] == true,
      faltantes: _lista(c?['faltantes']),
      datos: [
        if (c != null) ...[
          ('Servidor', _txt(c['servidor']).isEmpty ? '—' : '${_txt(c['servidor'])}:${_txt(c['puerto'])}'),
          ('Usuario', _txt(c['usuario']).isEmpty ? '—' : _txt(c['usuario'])),
        ],
      ],
      extra: c == null
          ? null
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Destinatarios',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.steel)),
              const SizedBox(height: 6),
              if (destinatarios.isEmpty)
                const Text('Sin destinatarios (EMAIL_DESTINO vacío).',
                    style: TextStyle(fontSize: 12.5, color: AppColors.bad))
              else
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final d in destinatarios) PillEstado(d, AdminColores.azul.last, icono: Icons.alternate_email),
                ]),
            ]),
      pruebas: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _destinoCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Correo de destino (opcional)',
            helperText: 'Si lo dejas vacío se envía a los destinatarios configurados.',
            helperMaxLines: 2,
            prefixIcon: Icon(Icons.alternate_email, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _probandoCorreo ? null : () => _probar('correo'),
          icon: _probandoCorreo ? const CfgSpinner() : const Icon(Icons.send_outlined, size: 18),
          label: Text(_probandoCorreo ? 'Enviando…' : 'Enviar correo de prueba'),
        ),
        if (_resCorreo != null) ...[const SizedBox(height: 12), _ResultadoPrueba(res: _resCorreo!, canal: 'correo')],
      ]),
    );
  }

  Widget _tarjetaWhatsapp(Map<String, dynamic>? w) {
    return _TarjetaCanal(
      logo: const SizedBox(width: 46, height: 46, child: Center(child: LogoWhatsapp(size: 42))),
      titulo: 'WhatsApp',
      subtitulo: 'Aviso inmediato al teléfono del negocio',
      cargando: _cargandoEstado && w == null,
      configurado: w == null ? null : w['configurado'] == true,
      faltantes: _lista(w?['faltantes']),
      datos: [
        if (w != null) ('Número de destino', _txt(w['destino']).isEmpty ? '—' : _txt(w['destino'])),
      ],
      pruebas: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const CfgAviso(
          texto: 'La prueba envía un mensaje corto al número configurado en WHATSAPP_DESTINO.',
          color: AppColors.steel,
          icono: Icons.info_outline,
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _probandoWa ? null : () => _probar('whatsapp'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1FA855)),
          icon: _probandoWa ? const CfgSpinner() : const Icon(Icons.send_outlined, size: 18),
          label: Text(_probandoWa ? 'Enviando…' : 'Enviar WhatsApp de prueba'),
        ),
        if (_resWa != null) ...[const SizedBox(height: 12), _ResultadoPrueba(res: _resWa!, canal: 'whatsapp')],
      ]),
    );
  }

  // ---------------------------------------------------------------
  // Sincronización
  // ---------------------------------------------------------------

  Widget _panelSync() {
    final ultima = _items.isEmpty ? null : _items.first;
    final ultimaOk = _items.where((i) => _txt(i['estado']).toUpperCase() == 'EXITOSO').firstOrNull;

    return AdminPanel(
      titulo: 'Sincronización con el sistema del cliente',
      subtitulo: 'Actualiza stock, agotados y productos nuevos desde el sistema de inventario',
      icono: Icons.sync_alt,
      colores: AdminColores.verde,
      accion: IconButton(
        tooltip: 'Actualizar historial',
        onPressed: _cargarHistorial,
        icon: const Icon(Icons.refresh),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _resumenSync(ultima, ultimaOk),
        const SizedBox(height: 16),
        Wrap(spacing: 14, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ElevatedButton.icon(
            onPressed: (_iniciando || _enCurso) ? null : _sincronizar,
            icon: (_iniciando || _enCurso) ? const CfgSpinner() : const Icon(Icons.sync, size: 20),
            label: Text(_enCurso ? 'Sincronizando…' : 'Sincronizar ahora'),
          ),
          if (_enCurso)
            const Text('Actualizando el historial cada 5 segundos…',
                style: TextStyle(fontSize: 12.5, color: AppColors.steel)),
          if (_msgSync != null)
            Text(_msgSync!,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _msgSyncError ? AppColors.bad : AppColors.ok)),
        ]),
        const SizedBox(height: 22),
        const Text('Historial reciente',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: AppColors.char)),
        const SizedBox(height: 10),
        if (_cargandoHist)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (_errorHist != null)
          CfgAviso(
            texto: _errorHist!,
            color: AppColors.bad,
            icono: Icons.error_outline,
            accion: TextButton(onPressed: _cargarHistorial, child: const Text('Reintentar')),
          )
        else if (_items.isEmpty)
          const VacioAdmin(
            icono: Icons.history,
            titulo: 'Aún no hay sincronizaciones',
            texto: 'Presiona «Sincronizar ahora» para traer los datos del sistema del cliente.',
          )
        else
          for (var i = 0; i < _items.length; i++)
            _FilaHistorial(item: _items[i], primero: i == 0, ultimo: i == _items.length - 1),
      ]),
    );
  }

  Widget _resumenSync(Map<String, dynamic>? ultima, Map<String, dynamic>? ultimaOk) {
    if (ultima == null) {
      return const CfgAviso(
        texto: 'Todavía no se ha registrado ninguna sincronización.',
        color: AppColors.steel,
        icono: Icons.hourglass_empty,
      );
    }
    final (color, etiqueta, icono) = _estadoSync(_txt(ultima['estado']));
    final fechaOk = ultimaOk == null ? null : _txt(ultimaOk['fecha']);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Wrap(spacing: 28, runSpacing: 14, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('Último estado',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.steel)),
          const SizedBox(height: 6),
          PillEstado(etiqueta, color, icono: icono),
          const SizedBox(height: 6),
          Text('${_fmtFechaSync(_txt(ultima['fecha']))} · ${_hace(_txt(ultima['fecha']))}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.char)),
        ]),
        _metrica('Procesados', _txt(ultima['procesados']), Icons.inventory_2_outlined, AdminColores.azul.last),
        _metrica('Agotados', _txt(ultima['agotados']), Icons.remove_shopping_cart_outlined, AppColors.bad),
        _metrica('Nuevos pendientes', _txt(ultima['nuevos']), Icons.fiber_new_outlined, AppColors.warn),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('Última exitosa',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.steel)),
          const SizedBox(height: 6),
          Text(fechaOk == null ? 'Ninguna en el historial' : _hace(fechaOk),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: fechaOk == null ? AppColors.bad : AppColors.ok)),
        ]),
      ]),
    );
  }

  Widget _metrica(String etiqueta, String valor, IconData icono, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icono, size: 20, color: color),
      ),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(valor.isEmpty ? '0' : valor,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.char, height: 1.1)),
        Text(etiqueta, style: const TextStyle(fontSize: 11.5, color: AppColors.steel)),
      ]),
    ]);
  }
}

// =====================================================================
// Piezas internas
// =====================================================================

class _TarjetaCanal extends StatelessWidget {
  final Widget logo;
  final String titulo;
  final String subtitulo;
  final bool cargando;
  final bool? configurado;
  final List<(String, String)> datos;
  final List<String> faltantes;
  final Widget? extra;
  final Widget pruebas;
  const _TarjetaCanal({
    required this.logo,
    required this.titulo,
    required this.subtitulo,
    required this.cargando,
    required this.configurado,
    required this.datos,
    required this.faltantes,
    required this.pruebas,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final ok = configurado == true;
    final color = configurado == null ? AppColors.steel : (ok ? AppColors.ok : AppColors.bad);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.4),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          logo,
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.char)),
              Text(subtitulo, style: const TextStyle(fontSize: 12.5, color: AppColors.steel)),
            ]),
          ),
          _Semaforo(color: color, cargando: cargando),
        ]),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: cargando
              ? const PillEstado('Consultando…', AppColors.steel, icono: Icons.hourglass_top)
              : PillEstado(
                  ok ? 'Configurado y listo' : 'Sin configurar',
                  color,
                  icono: ok ? Icons.check_circle_outline : Icons.cancel_outlined,
                ),
        ),
        if (datos.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final d in datos)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                SizedBox(
                    width: 130,
                    child: Text(d.$1,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.steel))),
                Expanded(
                    child: Text(d.$2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppColors.char))),
              ]),
            ),
        ],
        if (extra != null) ...[const SizedBox(height: 8), extra!],
        if (faltantes.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bad.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.bad.withValues(alpha: 0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.bad),
                SizedBox(width: 8),
                Text('Faltan estas variables en el .env del servidor',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.bad)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in faltantes)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.bad.withValues(alpha: 0.35))),
                    child: Text(f,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.bad)),
                  ),
              ]),
            ]),
          ),
        ],
        const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
        pruebas,
      ]),
    );
  }
}

class _Semaforo extends StatelessWidget {
  final Color color;
  final bool cargando;
  const _Semaforo({required this.color, required this.cargando});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12)),
      alignment: Alignment.center,
      child: cargando
          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: color))
          : Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 12, spreadRadius: 1)],
              ),
            ),
    );
  }
}

class _ResultadoPrueba extends StatelessWidget {
  final Map<String, dynamic> res;
  final String canal;
  const _ResultadoPrueba({required this.res, required this.canal});

  String? _consejo(String error) {
    final e = error.toLowerCase();
    if (e.contains('faltan variables')) {
      return 'Completa esas variables en el archivo .env del servidor y reinicia el servicio (ver la guía).';
    }
    if (e.contains('535') || e.contains('authentication') || e.contains('username and password') || e.contains('auth')) {
      return 'Google rechazó el acceso. Usa una contraseña de aplicación de 16 letras (no tu contraseña normal) '
          'y verifica que SMTP_USER sea el mismo correo que la generó.';
    }
    if (e.contains('timeout') || e.contains('timed out') || e.contains('socket') || e.contains('connection')) {
      return 'No se pudo conectar. Revisa SMTP_HOST (smtp.gmail.com), SMTP_PORT (587) y que el servidor tenga salida a internet.';
    }
    if (e.contains('token') || e.contains('190') || e.contains('oauth')) {
      return 'El token de WhatsApp parece vencido o inválido. Genera uno nuevo en Meta for Developers.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ok = res['ok'] == true;
    final color = ok ? AppColors.ok : AppColors.bad;
    final ms = res['ms'];
    final error = _txt(res['error']);
    final consejo = ok ? null : _consejo(error);
    final nombre = canal == 'correo' ? 'Correo' : 'WhatsApp';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ok ? Icons.check_circle : Icons.error, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ok ? '$nombre de prueba enviado correctamente' : 'No se pudo enviar la prueba de ${nombre.toLowerCase()}',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: color)),
            if (ok && ms != null)
              Text('Respuesta del servidor en $ms ms. Revisa tu bandeja o teléfono.',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.char)),
            if (!ok && error.isNotEmpty) ...[
              const SizedBox(height: 4),
              SelectableText(error, style: const TextStyle(fontSize: 12.5, color: AppColors.char, height: 1.4)),
            ],
            if (consejo != null) ...[
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.warn),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(consejo,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.char, height: 1.4))),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _FilaHistorial extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool primero;
  final bool ultimo;
  const _FilaHistorial({required this.item, required this.primero, required this.ultimo});

  @override
  Widget build(BuildContext context) {
    final (color, etiqueta, icono) = _estadoSync(_txt(item['estado']));
    final detalle = _txt(item['detalle']);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 26,
          child: Column(children: [
            Container(width: 2, height: 8, color: primero ? Colors.transparent : AdminColores.borde),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)],
              ),
            ),
            Expanded(child: Container(width: 2, color: ultimo ? Colors.transparent : AdminColores.borde)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.paper.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminColores.borde),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(_fmtFechaSync(_txt(item['fecha'])),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.char)),
                PillEstado(etiqueta, color, icono: icono),
                _dato(Icons.inventory_2_outlined, '${_txt(item['procesados'])} procesados'),
                _dato(Icons.remove_shopping_cart_outlined, '${_txt(item['agotados'])} agotados'),
                _dato(Icons.fiber_new_outlined, '${_txt(item['nuevos'])} nuevos'),
              ]),
              if (detalle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(detalle, style: const TextStyle(fontSize: 12.5, color: AppColors.steel, height: 1.4)),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _dato(IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 15, color: AppColors.steel),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 12.5, color: AppColors.char)),
      ]);
}

// =====================================================================
// Guía ilustrada: contraseña de aplicación de Google
// =====================================================================

class _GuiaGoogle extends StatelessWidget {
  const _GuiaGoogle();

  @override
  Widget build(BuildContext context) {
    const claves = 'SMTP_HOST=smtp.gmail.com\n'
        'SMTP_PORT=587\n'
        'SMTP_USER=tu_correo@gmail.com\n'
        'SMTP_PASS=clave_de_16_letras\n'
        'EMAIL_DESTINO=correo1@ejemplo.com,correo2@ejemplo.com';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      CfgCuadricula(
        minAncho: 380,
        maxColumnas: 3,
        espacio: 16,
        children: [
          _Paso(
            n: 1,
            titulo: 'Entra a tu Cuenta de Google → Seguridad',
            texto: 'Abre myaccount.google.com con el mismo correo que usará la tienda y elige «Seguridad» '
                'en el menú de la izquierda.',
            ilustracion: const _MockMenuGoogle(),
          ),
          _Paso(
            n: 2,
            titulo: 'Activa la «Verificación en 2 pasos»',
            texto: 'Es obligatoria para poder crear contraseñas de aplicación. Si ya dice «Activada», sigue al paso 3.',
            ilustracion: const _MockDosPasos(),
          ),
          _Paso(
            n: 3,
            titulo: 'Abre «Contraseñas de aplicaciones»',
            texto: 'Búscala con la lupa de la cuenta de Google o entra directo a '
                'myaccount.google.com/apppasswords.',
            ilustracion: const _MockBuscador(),
          ),
          _Paso(
            n: 4,
            titulo: 'Crea una llamada «Maykel»',
            texto: 'Escribe «Maykel» como nombre de la aplicación y presiona «Crear».',
            ilustracion: const _MockCrear(),
          ),
          _Paso(
            n: 5,
            titulo: 'Copia la clave de 16 letras',
            texto: 'Google la muestra una sola vez, en grupos de cuatro. Cópiala sin espacios; '
                'esa es tu SMTP_PASS.',
            ilustracion: const _MockClave(),
          ),
          _Paso(
            n: 6,
            titulo: 'Pégala en el archivo .env del servidor',
            texto: 'Edita el .env del backend con estos valores (SMTP_USER es tu correo y EMAIL_DESTINO '
                'los correos del equipo, separados por coma).',
            ilustracion: const _Codigo(texto: claves),
          ),
          _Paso(
            n: 7,
            titulo: 'Reinicia el servicio',
            texto: 'En el servidor ejecuta este comando para que lea la nueva configuración.',
            ilustracion: const _Codigo(texto: 'sudo systemctl restart maykel', prefijo: r'$ '),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const CfgAviso(
        texto: 'Listo: vuelve a esta pantalla, actualiza el estado y presiona «Enviar correo de prueba». '
            'Nunca compartas la clave de 16 letras ni la pegues en el sitio: solo va en el .env del servidor.',
        color: AppColors.ok,
        icono: Icons.task_alt,
      ),
    ]);
  }
}

class _Paso extends StatelessWidget {
  final int n;
  final String titulo;
  final String texto;
  final Widget ilustracion;
  const _Paso({required this.n, required this.titulo, required this.texto, required this.ilustracion});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.paper.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminColores.borde),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: AdminColores.rojo),
            ),
            child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(titulo,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w900, color: AppColors.char, height: 1.25)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(texto, style: const TextStyle(fontSize: 12.5, color: AppColors.steel, height: 1.45)),
        const SizedBox(height: 12),
        ilustracion,
      ]),
    );
  }
}

/// Marco tipo ventana de navegador para las ilustraciones de la guía.
class _Ventana extends StatelessWidget {
  final String url;
  final Widget child;
  const _Ventana({required this.url, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AdminColores.borde),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          color: const Color(0xFFEFEFF1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(children: [
            for (final c in const [Color(0xFFFF5F57), Color(0xFFFEBC2E), Color(0xFF28C840)])
              Container(
                  width: 8, height: 8, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.lock_outline, size: 11, color: AppColors.steel),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(url,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: AppColors.steel))),
                ]),
              ),
            ),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(12), child: child),
      ]),
    );
  }
}

class _MockMenuGoogle extends StatelessWidget {
  const _MockMenuGoogle();

  @override
  Widget build(BuildContext context) {
    Widget item(IconData i, String t, {bool activo = false}) => Container(
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: activo ? const Color(0xFFD3E3FD) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: activo ? Border.all(color: AppColors.red, width: 1.6) : null,
          ),
          child: Row(children: [
            Icon(i, size: 15, color: activo ? const Color(0xFF0B57D0) : AppColors.steel),
            const SizedBox(width: 8),
            Text(t,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: activo ? FontWeight.w800 : FontWeight.w500,
                    color: activo ? const Color(0xFF0B57D0) : AppColors.char)),
          ]),
        );
    return _Ventana(
      url: 'myaccount.google.com',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CircleAvatar(radius: 12, backgroundColor: Color(0xFF1B4F8A), child: Text('M', style: TextStyle(fontSize: 11, color: Colors.white))),
          const SizedBox(width: 8),
          const Text('Cuenta de Google', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        item(Icons.home_outlined, 'Inicio'),
        item(Icons.person_outline, 'Información personal'),
        item(Icons.shield_outlined, 'Seguridad', activo: true),
        item(Icons.people_outline, 'Contactos'),
      ]),
    );
  }
}

class _MockDosPasos extends StatelessWidget {
  const _MockDosPasos();

  @override
  Widget build(BuildContext context) {
    return _Ventana(
      url: 'myaccount.google.com/security',
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.red, width: 1.6),
        ),
        child: Row(children: [
          const Icon(Icons.phonelink_lock_outlined, color: Color(0xFF0B57D0)),
          const SizedBox(width: 10),
          const Expanded(
              child: Text('Verificación en 2 pasos',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
          PillEstado('Activada', AppColors.ok, icono: Icons.check),
        ]),
      ),
    );
  }
}

class _MockBuscador extends StatelessWidget {
  const _MockBuscador();

  @override
  Widget build(BuildContext context) {
    return _Ventana(
      url: 'myaccount.google.com/apppasswords',
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(color: const Color(0xFFF1F3F4), borderRadius: BorderRadius.circular(20)),
          child: const Row(children: [
            Icon(Icons.search, size: 16, color: AppColors.steel),
            SizedBox(width: 6),
            Text('Contraseñas de aplicaciones', style: TextStyle(fontSize: 11.5)),
          ]),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.red, width: 1.6),
          ),
          child: const Row(children: [
            Icon(Icons.key_outlined, size: 16, color: Color(0xFF0B57D0)),
            SizedBox(width: 8),
            Text('Contraseñas de aplicaciones', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            Spacer(),
            Icon(Icons.chevron_right, size: 16, color: AppColors.steel),
          ]),
        ),
      ]),
    );
  }
}

class _MockCrear extends StatelessWidget {
  const _MockCrear();

  @override
  Widget build(BuildContext context) {
    return _Ventana(
      url: 'myaccount.google.com/apppasswords',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Nombre de la aplicación', style: TextStyle(fontSize: 10.5, color: AppColors.steel)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF0B57D0), width: 1.6),
          ),
          child: const Row(children: [
            Text('Maykel', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            SizedBox(width: 2),
            SizedBox(height: 14, child: VerticalDivider(width: 2, thickness: 1.4, color: Color(0xFF0B57D0))),
          ]),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF0B57D0),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.red, width: 1.6),
            ),
            child: const Text('Crear', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}

class _MockClave extends StatelessWidget {
  const _MockClave();

  @override
  Widget build(BuildContext context) {
    return _Ventana(
      url: 'myaccount.google.com/apppasswords',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Tu contraseña de aplicación', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4C2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.red, width: 1.6),
          ),
          child: const Text('abcd efgh ijkl mnop',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        ),
        const SizedBox(height: 6),
        const Text('16 letras · se muestra una sola vez',
            style: TextStyle(fontSize: 10.5, color: AppColors.steel)),
      ]),
    );
  }
}

class _Codigo extends StatelessWidget {
  final String texto;
  final String prefijo;
  const _Codigo({required this.texto, this.prefijo = ''});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(color: const Color(0xFF1E1F24), borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: SelectableText(
            '$prefijo$texto',
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 11.5, height: 1.55, color: Color(0xFFB7F0C4)),
          ),
        ),
        IconButton(
          tooltip: 'Copiar',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.copy_rounded, size: 17, color: Colors.white70),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: texto));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copiado al portapapeles'), duration: Duration(seconds: 2)),
            );
          },
        ),
      ]),
    );
  }
}
