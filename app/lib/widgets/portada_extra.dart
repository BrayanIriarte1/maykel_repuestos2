import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config.dart';
import '../models.dart';
import 'diseno.dart';

/// Logo de una red o servicio (assets/images/iconos/<nombre>.svg) pintado de [color].
class IconoMarca extends StatelessWidget {
  final String nombre;
  final double size;
  final Color color;
  const IconoMarca(this.nombre, {super.key, this.size = 22, this.color = Colors.white});

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/images/iconos/$nombre.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}

/// Logo de WhatsApp: círculo verde con el ícono oficial en blanco.
class LogoWhatsapp extends StatelessWidget {
  final double size;
  const LogoWhatsapp({super.key, this.size = 30});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: Color(0xFF25D366), shape: BoxShape.circle),
        child: IconoMarca('whatsapp', size: size * 0.62),
      );
}

/// Ícono dentro de un círculo con degradado, anillo y brillo.
class InsigniaIcono extends StatelessWidget {
  final IconData? icono;
  final Widget? hijo;
  final double tam;
  final List<Color> colores;
  const InsigniaIcono({
    super.key,
    this.icono,
    this.hijo,
    this.tam = 64,
    this.colores = const [AppColors.red, AppColors.redDark],
  });

  @override
  Widget build(BuildContext context) => Container(
        width: tam,
        height: tam,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
              colors: colores, begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 2.5),
          boxShadow: [
            BoxShadow(
                color: colores.first.withValues(alpha: 0.45),
                blurRadius: 18,
                offset: const Offset(0, 8)),
          ],
        ),
        child: hijo ?? Icon(icono, color: Colors.white, size: tam * 0.48),
      );
}

/// Número que sube de 0 al valor cuando entra en pantalla.
class ContadorAnimado extends StatefulWidget {
  final int valor;
  final String sufijo;
  final TextStyle estilo;
  const ContadorAnimado(
      {super.key, required this.valor, this.sufijo = '', required this.estilo});

  @override
  State<ContadorAnimado> createState() => _ContadorAnimadoState();
}

class _ContadorAnimadoState extends State<ContadorAnimado> {
  bool _activo = false;
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
    if (_activo || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    if (box.localToGlobal(Offset.zero).dy < MediaQuery.of(context).size.height * 0.95) {
      _pos?.removeListener(_revisar);
      setState(() => _activo = true);
    }
  }

  static String _miles(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: _activo ? widget.valor.toDouble() : 0),
        duration: const Duration(milliseconds: 1500),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text('${_miles(v.round())}${widget.sufijo}', style: widget.estilo),
      );
}

/// Paginador numérico: « 1 2 3 … 12 ».
class Paginador extends StatelessWidget {
  final int pagina;
  final int total;
  final ValueChanged<int> onPagina;
  const Paginador({super.key, required this.pagina, required this.total, required this.onPagina});

  Widget _boton(String texto, {int? destino, bool activo = false, IconData? icono}) {
    final habilitado = destino != null && destino != pagina;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: habilitado ? () => onPagina(destino) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: activo ? AppColors.red : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: activo ? AppColors.red : AppColors.paper2),
            boxShadow: activo
                ? [BoxShadow(color: AppColors.red.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))]
                : null,
          ),
          child: icono != null
              ? Icon(icono, size: 20, color: destino == null ? AppColors.paper2 : AppColors.char)
              : Text(texto,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: activo ? Colors.white : AppColors.char)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (total <= 1) return const SizedBox.shrink();
    final paginas = <int>{1, total, pagina - 1, pagina, pagina + 1}
        .where((p) => p >= 1 && p <= total)
        .toList()
      ..sort();
    final hijos = <Widget>[
      _boton('', icono: Icons.chevron_left, destino: pagina > 1 ? pagina - 1 : null),
    ];
    for (var i = 0; i < paginas.length; i++) {
      if (i > 0 && paginas[i] - paginas[i - 1] > 1) {
        hijos.add(const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('…', style: TextStyle(color: AppColors.steel, fontWeight: FontWeight.w800))));
      }
      hijos.add(_boton('${paginas[i]}', destino: paginas[i], activo: paginas[i] == pagina));
    }
    hijos.add(_boton('', icono: Icons.chevron_right, destino: pagina < total ? pagina + 1 : null));
    return Wrap(alignment: WrapAlignment.center, runSpacing: 8, children: hijos);
  }
}

/// Estado del local según el horario publicado (zona horaria de Chile).
class EstadoHorario {
  final bool abierto;
  final String detalle;
  const EstadoHorario(this.abierto, this.detalle);

  static EstadoHorario? de(String horario, {DateTime? ahora}) {
    final tramos = RegExp(r'(\d{1,2}):(\d{2})\s*[–-]\s*(\d{1,2}):(\d{2})').allMatches(horario).toList();
    if (tramos.isEmpty) return null;
    final utc = (ahora ?? DateTime.now()).toUtc();
    // Chile: UTC-3 en horario de verano (sept-abril) y UTC-4 el resto.
    final chile = utc.subtract(Duration(hours: (utc.month >= 5 && utc.month <= 8) ? 4 : 3));
    int minutos(RegExpMatch m, int h, int mi) => int.parse(m.group(h)!) * 60 + int.parse(m.group(mi)!);
    RegExpMatch? tramo;
    if (chile.weekday <= 5) tramo = tramos.first;
    if (chile.weekday == 6 && tramos.length > 1) tramo = tramos[1];
    if (tramo == null) return const EstadoHorario(false, 'Domingo cerrado');
    final ahoraMin = chile.hour * 60 + chile.minute;
    final abre = minutos(tramo, 1, 2);
    final cierra = minutos(tramo, 3, 4);
    final hh = '${tramo.group(3)}:${tramo.group(4)}';
    if (ahoraMin >= abre && ahoraMin < cierra) return EstadoHorario(true, 'Cerramos a las $hh');
    return EstadoHorario(false, ahoraMin < abre ? 'Abrimos a las ${tramo.group(1)}:${tramo.group(2)}' : 'Abrimos mañana');
  }
}

/// Cinta de horario y datos de la sucursal que se desplaza sola (barra superior).
class HorarioMarquesina extends StatelessWidget {
  const HorarioMarquesina({super.key});

  @override
  Widget build(BuildContext context) {
    final c = SiteContent.actual;
    final estado = EstadoHorario.de(c.contactoHorario);
    final lineas = c.contactoHorario.split(RegExp(r'[\n;]')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    Widget chip(IconData i, String t, {Color color = Colors.white70, FontWeight peso = FontWeight.w600}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 16, color: AppColors.yellow),
            const SizedBox(width: 8),
            Text(t, style: TextStyle(color: color, fontSize: 14, fontWeight: peso)),
          ]),
        );
    final items = <Widget>[
      if (estado != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: (estado.abierto ? AppColors.ok : AppColors.bad).withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: (estado.abierto ? const Color(0xFF58D68D) : const Color(0xFFFF7B7B))),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 10, color: estado.abierto ? const Color(0xFF58D68D) : const Color(0xFFFF7B7B)),
              const SizedBox(width: 8),
              Text('${estado.abierto ? 'ABIERTO AHORA' : 'CERRADO AHORA'} · ${estado.detalle}',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      for (final l in lineas) chip(Icons.schedule, l),
      chip(Icons.place_outlined, c.contactoDireccion),
      chip(Icons.event_available_outlined, 'Reserva online y retira en tienda'),
      chip(Icons.chat_bubble_outline, 'WhatsApp +${c.contactoWhatsapp}'),
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(30),
        ),
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
            stops: [0, 0.06, 0.94, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: Marquesina(items: items, alto: 46, velocidad: 38, fondo: Colors.transparent),
        ),
      ),
    );
  }
}
