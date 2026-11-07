import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../api_service.dart';
import '../config.dart';
import '../models.dart';
import 'admin_ui.dart';
import 'portada_extra.dart';

// =====================================================================
// Piezas comunes (Configuración y Usuarios)
// =====================================================================

const Map<String, IconData> kIconoPermiso = {
  'dashboard': Icons.insights_outlined,
  'catalogo': Icons.grid_view_outlined,
  'reservas': Icons.event_note_outlined,
  'stock': Icons.inventory_2_outlined,
  'usuarios': Icons.people_outline,
  'configuracion': Icons.settings_outlined,
};

const Map<String, String> kEtiquetaPermiso = {
  'dashboard': 'Analítica',
  'catalogo': 'Catálogo',
  'reservas': 'Reservas',
  'stock': 'Stock',
  'usuarios': 'Usuarios',
  'configuracion': 'Configuración',
};

const Map<String, String> kDescripcionPermiso = {
  'dashboard': 'Ve los indicadores y gráficos de analítica.',
  'catalogo': 'Consulta el catálogo de productos.',
  'reservas': 'Atiende y cambia el estado de las reservas.',
  'stock': 'Edita precios y existencias del inventario.',
  'usuarios': 'Crea y edita usuarios y roles del panel.',
  'configuracion': 'Cambia el contenido del sitio y las notificaciones.',
};

const Map<String, List<Color>> kColorPermiso = {
  'dashboard': AdminColores.violeta,
  'catalogo': AdminColores.azul,
  'reservas': AdminColores.ambar,
  'stock': AdminColores.verde,
  'usuarios': AdminColores.rojo,
  'configuracion': AdminColores.gris,
};

IconData _iconoPermiso(String p) => kIconoPermiso[p] ?? Icons.key_outlined;
String _etiquetaPermiso(String p) => kEtiquetaPermiso[p] ?? kNombrePermiso[p] ?? p;
List<Color> _colorPermiso(String p) => kColorPermiso[p] ?? AdminColores.gris;

/// Distribuye hijos en 1..[maxColumnas] columnas según el ancho disponible.
class CfgCuadricula extends StatelessWidget {
  final List<Widget> children;
  final double minAncho;
  final int maxColumnas;
  final double espacio;
  const CfgCuadricula({
    super.key,
    required this.children,
    this.minAncho = 300,
    this.maxColumnas = 5,
    this.espacio = 16,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final cols = ((w + espacio) / (minAncho + espacio)).floor().clamp(1, maxColumnas);
      final ancho = (w - espacio * (cols - 1)) / cols;
      return Wrap(
        spacing: espacio,
        runSpacing: espacio,
        children: [for (final h in children) SizedBox(width: ancho, child: h)],
      );
    });
  }
}

/// Fila de campos que se apila en una sola columna cuando no caben.
class CfgFila extends StatelessWidget {
  final List<Widget> children;
  final List<int>? flex;
  final double minAncho;
  const CfgFila({super.key, required this.children, this.flex, this.minAncho = 230});

  @override
  Widget build(BuildContext context) {
    const gap = 14.0;
    return LayoutBuilder(builder: (context, c) {
      final n = children.length;
      if (c.maxWidth >= minAncho * n + gap * (n - 1)) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            Expanded(flex: flex != null && i < flex!.length ? flex![i] : 1, child: children[i]),
          ],
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          children[i],
        ],
      ]);
    });
  }
}

/// Dos columnas (formulario + vista previa) en pantallas anchas.
class CfgDosColumnas extends StatelessWidget {
  final Widget izquierda;
  final Widget derecha;
  const CfgDosColumnas({super.key, required this.izquierda, required this.derecha});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 1000) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: izquierda),
          const SizedBox(width: 18),
          Expanded(flex: 2, child: derecha),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        izquierda,
        const SizedBox(height: 18),
        derecha,
      ]);
    });
  }
}

class CfgAviso extends StatelessWidget {
  final String texto;
  final Color color;
  final IconData icono;
  final Widget? accion;
  const CfgAviso({super.key, required this.texto, required this.color, required this.icono, this.accion});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icono, size: 19, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(texto, style: const TextStyle(fontSize: 12.8, height: 1.45, color: AppColors.char)),
          ),
        ),
        if (accion != null) accion!,
      ]),
    );
  }
}

class CfgSpinner extends StatelessWidget {
  const CfgSpinner({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white));
}

/// Campo de texto con etiqueta, ayuda breve y, opcionalmente, ícono.
class CfgCampo extends StatelessWidget {
  final TextEditingController controller;
  final String etiqueta;
  final String? ayuda;
  final String? hint;
  final IconData? icono;
  final int maxLines;
  final int? minLines;
  final TextInputType? teclado;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final int? maxLength;
  const CfgCampo({
    super.key,
    required this.controller,
    required this.etiqueta,
    this.ayuda,
    this.hint,
    this.icono,
    this.maxLines = 1,
    this.minLines,
    this.teclado,
    this.errorText,
    this.onChanged,
    this.autofocus = false,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      autofocus: autofocus,
      keyboardType: teclado ?? (maxLines > 1 ? TextInputType.multiline : null),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: etiqueta,
        helperText: ayuda,
        helperMaxLines: 3,
        hintText: hint,
        errorText: errorText,
        errorMaxLines: 2,
        prefixIcon: icono == null || maxLines > 1 ? null : Icon(icono, size: 20),
      ),
    );
  }
}

/// Subtítulo pequeño dentro de un panel o diálogo.
class CfgEtiquetaSeccion extends StatelessWidget {
  final String texto;
  final IconData icono;
  final Widget? derecha;
  const CfgEtiquetaSeccion(this.texto, this.icono, {super.key, this.derecha});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icono, size: 17, color: AppColors.red),
      const SizedBox(width: 8),
      Expanded(
        child: Text(texto.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 1.1, color: AppColors.steel)),
      ),
      if (derecha != null) derecha!,
    ]);
  }
}

/// Estructura común de los diálogos del panel: cabecera con ícono, cuerpo
/// desplazable y pie de acciones.
class CfgDialogo extends StatelessWidget {
  final IconData icono;
  final List<Color> colores;
  final String titulo;
  final String? subtitulo;
  final Widget child;
  final Widget? pie;
  final double ancho;
  const CfgDialogo({
    super.key,
    required this.icono,
    required this.titulo,
    required this.child,
    this.subtitulo,
    this.pie,
    this.colores = AdminColores.rojo,
    this.ancho = 560,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ancho),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 18),
            decoration: BoxDecoration(
              color: AppColors.paper.withValues(alpha: 0.7),
              border: const Border(bottom: BorderSide(color: AdminColores.borde)),
            ),
            child: Row(children: [
              InsigniaIcono(icono: icono, tam: 48, colores: colores),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titulo,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: AppColors.char)),
                  if (subtitulo != null)
                    Text(subtitulo!, style: const TextStyle(fontSize: 12.5, color: AppColors.steel)),
                ]),
              ),
              IconButton(
                tooltip: 'Cerrar',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          Flexible(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 20, 24, 12), child: child)),
          if (pie != null)
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AdminColores.borde))),
              child: pie,
            ),
        ]),
      ),
    );
  }
}

class CfgPieDialogo extends StatelessWidget {
  final VoidCallback? onGuardar;
  final bool guardando;
  final String etiquetaGuardar;
  final IconData iconoGuardar;
  final String? error;
  final Widget? izquierda;
  const CfgPieDialogo({
    super.key,
    required this.onGuardar,
    this.guardando = false,
    this.etiquetaGuardar = 'Guardar',
    this.iconoGuardar = Icons.check,
    this.error,
    this.izquierda,
  });

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (error != null) ...[
        CfgAviso(texto: error!, color: AppColors.bad, icono: Icons.error_outline),
        const SizedBox(height: 12),
      ],
      LayoutBuilder(builder: (context, c) {
        final botones = Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
          TextButton(
            onPressed: guardando ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: guardando ? null : onGuardar,
            icon: guardando ? const CfgSpinner() : Icon(iconoGuardar, size: 18),
            label: Text(etiquetaGuardar),
          ),
        ]);
        if (c.maxWidth < 480) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (izquierda != null) ...[izquierda!, const SizedBox(height: 10)],
            botones,
          ]);
        }
        return Row(children: [
          if (izquierda != null)
            Expanded(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: izquierda!))
          else
            const Spacer(),
          botones,
        ]);
      }),
    ]);
  }
}

/// Confirmación de borrado con el mismo estilo que el resto de diálogos.
Future<bool> mostrarConfirmacionEliminar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String? detalle,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => CfgDialogo(
      icono: Icons.delete_outline,
      colores: AdminColores.rojo,
      titulo: titulo,
      subtitulo: 'Esta acción no se puede deshacer',
      ancho: 460,
      pie: Row(children: [
        const Spacer(),
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.bad),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Eliminar'),
        ),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(mensaje, style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.char)),
        if (detalle != null) ...[
          const SizedBox(height: 8),
          Text(detalle, style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.steel)),
        ],
        const SizedBox(height: 8),
      ]),
    ),
  );
  return r == true;
}

// =====================================================================
// Configuración: navegación, barra de guardado y listas editables
// =====================================================================

class CfgSeccionInfo {
  final String clave;
  final String etiqueta;
  final String resumen;
  final IconData icono;
  const CfgSeccionInfo(this.clave, this.etiqueta, this.resumen, this.icono);
}

bool cfgJsonIgual(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

class CfgNavegacion extends StatelessWidget {
  final List<CfgSeccionInfo> secciones;
  final String activa;
  final Set<String> modificadas;
  final ValueChanged<String> onSeleccionar;
  final bool horizontal;
  const CfgNavegacion({
    super.key,
    required this.secciones,
    required this.activa,
    required this.modificadas,
    required this.onSeleccionar,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    if (horizontal) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          for (final s in secciones)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: s.clave == activa,
                onSelected: (_) => onSeleccionar(s.clave),
                avatar: Icon(s.icono, size: 17, color: s.clave == activa ? Colors.white : AppColors.steel),
                label: Text(s.etiqueta + (modificadas.contains(s.clave) ? ' •' : '')),
                labelStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: s.clave == activa ? Colors.white : AppColors.char),
                selectedColor: AppColors.red,
                showCheckmark: false,
              ),
            ),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AdminColores.borde),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: Column(children: [
        for (final s in secciones) _item(s),
      ]),
    );
  }

  Widget _item(CfgSeccionInfo s) {
    final sel = s.clave == activa;
    final cambiada = modificadas.contains(s.clave);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onSeleccionar(s.clave),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: sel ? AppColors.red.withValues(alpha: 0.09) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sel ? AppColors.red.withValues(alpha: 0.35) : Colors.transparent),
            ),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: sel ? const LinearGradient(colors: AdminColores.rojo) : null,
                  color: sel ? null : AppColors.paper,
                ),
                child: Icon(s.icono, size: 18, color: sel ? Colors.white : AppColors.steel),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.etiqueta,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: sel ? FontWeight.w900 : FontWeight.w700,
                          color: AppColors.char)),
                  Text(s.resumen,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.steel)),
                ]),
              ),
              if (cambiada)
                Tooltip(
                  message: 'Cambios sin guardar',
                  child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(color: AppColors.warn, shape: BoxShape.circle)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Barra superior fija de Configuración: estado de cambios y acciones.
class CfgBarraGuardar extends StatelessWidget {
  final bool hayCambios;
  final bool guardando;
  final int seccionesModificadas;
  final String? mensaje;
  final bool mensajeEsError;
  final VoidCallback onGuardar;
  final VoidCallback onDescartar;
  const CfgBarraGuardar({
    super.key,
    required this.hayCambios,
    required this.guardando,
    required this.seccionesModificadas,
    required this.mensaje,
    required this.mensajeEsError,
    required this.onGuardar,
    required this.onDescartar,
  });

  @override
  Widget build(BuildContext context) {
    final mostrarMensaje = mensaje != null && !hayCambios;
    final estado = Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      hayCambios
          ? PillEstado(
              seccionesModificadas > 1
                  ? 'Cambios sin guardar en $seccionesModificadas secciones'
                  : 'Cambios sin guardar',
              AppColors.warn,
              icono: Icons.edit_note)
          : const PillEstado('Todo guardado', AppColors.ok, icono: Icons.check_circle_outline),
      if (mostrarMensaje)
        Text(mensaje!,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: mensajeEsError ? AppColors.bad : AppColors.ok)),
      if (mensaje != null && hayCambios && mensajeEsError)
        Text(mensaje!, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.bad)),
    ]);
    final botones = Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, runSpacing: 8, children: [
      OutlinedButton.icon(
        onPressed: hayCambios && !guardando ? onDescartar : null,
        icon: const Icon(Icons.undo, size: 18),
        label: const Text('Descartar'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      ElevatedButton.icon(
        onPressed: hayCambios && !guardando ? onGuardar : null,
        icon: guardando ? const CfgSpinner() : const Icon(Icons.save_outlined, size: 18),
        label: const Text('Guardar cambios'),
      ),
    ]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: AdminColores.borde)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 760) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            estado,
            const SizedBox(height: 10),
            botones,
          ]);
        }
        return Row(children: [Expanded(child: estado), const SizedBox(width: 12), botones]);
      }),
    );
  }
}

/// Fila de una lista editable (fichas, servicios, secciones legales).
class CfgItemLista extends StatelessWidget {
  final IconData icono;
  final List<Color> colores;
  final String titulo;
  final String? subtitulo;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;
  const CfgItemLista({
    super.key,
    required this.icono,
    required this.titulo,
    required this.onEditar,
    required this.onEliminar,
    this.subtitulo,
    this.colores = AdminColores.azul,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.paper.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColores.borde),
      ),
      child: Row(children: [
        InsigniaIcono(icono: icono, tam: 38, colores: colores),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.char)),
            if (subtitulo != null && subtitulo!.isNotEmpty)
              Text(subtitulo!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.steel, height: 1.35)),
          ]),
        ),
        IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined, size: 19), onPressed: onEditar),
        IconButton(
          tooltip: 'Quitar',
          icon: const Icon(Icons.delete_outline, size: 19, color: AppColors.bad),
          onPressed: onEliminar,
        ),
      ]),
    );
  }
}

class CfgListaVacia extends StatelessWidget {
  final String texto;
  final IconData icono;
  const CfgListaVacia(this.texto, {super.key, this.icono = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColores.borde),
      ),
      child: Column(children: [
        Icon(icono, size: 30, color: AppColors.red.withValues(alpha: 0.35)),
        const SizedBox(height: 8),
        Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.steel)),
      ]),
    );
  }
}

class CfgVistaPrevia extends StatelessWidget {
  final Widget child;
  final String? ayuda;
  const CfgVistaPrevia({super.key, required this.child, this.ayuda});

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      titulo: 'Vista previa',
      subtitulo: ayuda ?? 'Así se verá en el sitio público',
      icono: Icons.visibility_outlined,
      colores: AdminColores.violeta,
      child: child,
    );
  }
}

class CfgPreviewHero extends StatelessWidget {
  final TextEditingController nombre;
  final TextEditingController titulo;
  final TextEditingController subtitulo;
  final TextEditingController botonCatalogo;
  final TextEditingController botonContacto;
  final TextEditingController productosEtiqueta;
  final TextEditingController marcasValor;
  final TextEditingController marcasEtiqueta;
  final TextEditingController categoriasValor;
  final TextEditingController categoriasEtiqueta;
  const CfgPreviewHero({
    super.key,
    required this.nombre,
    required this.titulo,
    required this.subtitulo,
    required this.botonCatalogo,
    required this.botonContacto,
    required this.productosEtiqueta,
    required this.marcasValor,
    required this.marcasEtiqueta,
    required this.categoriasValor,
    required this.categoriasEtiqueta,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        nombre, titulo, subtitulo, botonCatalogo, botonContacto, productosEtiqueta,
        marcasValor, marcasEtiqueta, categoriasValor, categoriasEtiqueta,
      ]),
      builder: (context, _) {
        String t(TextEditingController c, String vacio) => c.text.trim().isEmpty ? vacio : c.text.trim();
        Widget stat(String valor, String etiqueta) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(valor, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              Text(etiqueta, style: const TextStyle(color: Colors.white60, fontSize: 10.5)),
            ]);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
                colors: [Color(0xFF1A1A1C), Color(0xFF5A0F16)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t(nombre, 'Nombre del negocio').toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: AppColors.yellow, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.6)),
            const SizedBox(height: 8),
            Text(t(titulo, 'Título principal'),
                style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900, height: 1.1)),
            const SizedBox(height: 10),
            Text(t(subtitulo, 'Subtítulo de la portada'),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.45)),
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 8, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(color: AppColors.red, borderRadius: BorderRadius.circular(10)),
                child: Text(t(botonCatalogo, 'Botón 1'),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white54)),
                child: Text(t(botonContacto, 'Botón 2'),
                    style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 18),
            Wrap(spacing: 26, runSpacing: 10, children: [
              stat('···', t(productosEtiqueta, 'Productos')),
              stat(t(marcasValor, '0'), t(marcasEtiqueta, 'Marcas')),
              stat(t(categoriasValor, '0'), t(categoriasEtiqueta, 'Categorías')),
            ]),
          ]),
        );
      },
    );
  }
}

class CfgPreviewContacto extends StatelessWidget {
  final TextEditingController horario;
  final TextEditingController direccion;
  final TextEditingController whatsapp;
  final TextEditingController email;
  const CfgPreviewContacto({
    super.key,
    required this.horario,
    required this.direccion,
    required this.whatsapp,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([horario, direccion, whatsapp, email]),
      builder: (context, _) {
        Widget fila(IconData i, String t, String vacio) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(i, size: 18, color: AppColors.red),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(t.trim().isEmpty ? vacio : t.trim(),
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: t.trim().isEmpty ? AppColors.steel : AppColors.char)),
                ),
              ]),
            );
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.paper.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AdminColores.borde),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            fila(Icons.schedule, horario.text, 'Horario de atención'),
            fila(Icons.place_outlined, direccion.text, 'Dirección'),
            fila(Icons.phone_outlined, whatsapp.text.trim().isEmpty ? '' : '+${whatsapp.text.trim()}', 'WhatsApp'),
            fila(Icons.mail_outline, email.text, 'Correo de contacto'),
          ]),
        );
      },
    );
  }
}

class CfgPreviewPie extends StatelessWidget {
  final TextEditingController derechos;
  final TextEditingController nombre;
  const CfgPreviewPie({super.key, required this.derechos, required this.nombre});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([derechos, nombre]),
      builder: (context, _) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(color: AppColors.char, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Text(nombre.text.trim().isEmpty ? 'Nombre del negocio' : nombre.text.trim(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text('© ${DateTime.now().year} ${derechos.text.trim()}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
      ),
    );
  }
}

// =====================================================================
// Configuración: diálogos de fichas, servicios y secciones legales
// =====================================================================

Future<FichaHistoria?> mostrarDialogoFicha(BuildContext context, {FichaHistoria? existente}) =>
    showDialog<FichaHistoria>(context: context, builder: (_) => _CfgFichaDialog(existente: existente));

Future<ServicioItem?> mostrarDialogoServicio(BuildContext context, {ServicioItem? existente}) =>
    showDialog<ServicioItem>(context: context, builder: (_) => _CfgServicioDialog(existente: existente));

Future<SeccionLegal?> mostrarDialogoSeccionLegal(BuildContext context, {SeccionLegal? existente}) =>
    showDialog<SeccionLegal>(context: context, builder: (_) => _CfgLegalDialog(existente: existente));

class _CfgFichaDialog extends StatefulWidget {
  final FichaHistoria? existente;
  const _CfgFichaDialog({this.existente});

  @override
  State<_CfgFichaDialog> createState() => _CfgFichaDialogState();
}

class _CfgFichaDialogState extends State<_CfgFichaDialog> {
  late final _etiquetaCtrl = TextEditingController(text: widget.existente?.etiqueta ?? '');
  late final _valorCtrl = TextEditingController(text: widget.existente?.valor ?? '');
  bool _intento = false;

  @override
  void dispose() {
    _etiquetaCtrl.dispose();
    _valorCtrl.dispose();
    super.dispose();
  }

  void _guardar() {
    setState(() => _intento = true);
    if (_etiquetaCtrl.text.trim().isEmpty || _valorCtrl.text.trim().isEmpty) return;
    Navigator.of(context).pop(FichaHistoria(etiqueta: _etiquetaCtrl.text.trim(), valor: _valorCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    String? err(TextEditingController c) => _intento && c.text.trim().isEmpty ? 'Este campo es obligatorio.' : null;
    return CfgDialogo(
      icono: Icons.badge_outlined,
      colores: AdminColores.azul,
      titulo: widget.existente == null ? 'Nueva ficha' : 'Editar ficha',
      subtitulo: 'Dato destacado de la sección «Historia»',
      ancho: 500,
      pie: CfgPieDialogo(onGuardar: _guardar),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CfgFila(children: [
          CfgCampo(
            controller: _etiquetaCtrl,
            etiqueta: 'Etiqueta',
            hint: 'Ej.: Ubicación',
            ayuda: 'El título pequeño del dato.',
            icono: Icons.label_outline,
            autofocus: true,
            errorText: err(_etiquetaCtrl),
            onChanged: (_) => setState(() {}),
          ),
          CfgCampo(
            controller: _valorCtrl,
            etiqueta: 'Valor',
            hint: 'Ej.: Calama',
            ayuda: 'Lo que se muestra destacado.',
            icono: Icons.short_text,
            errorText: err(_valorCtrl),
            onChanged: (_) => setState(() {}),
          ),
        ]),
        const SizedBox(height: 18),
        const CfgEtiquetaSeccion('Vista previa', Icons.visibility_outlined),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.paper.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AdminColores.borde),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_etiquetaCtrl.text.trim().isEmpty ? 'ETIQUETA' : _etiquetaCtrl.text.trim().toUpperCase(),
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: AppColors.red)),
            const SizedBox(height: 4),
            Text(_valorCtrl.text.trim().isEmpty ? 'Valor' : _valorCtrl.text.trim(),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.char)),
          ]),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _CfgServicioDialog extends StatefulWidget {
  final ServicioItem? existente;
  const _CfgServicioDialog({this.existente});

  @override
  State<_CfgServicioDialog> createState() => _CfgServicioDialogState();
}

class _CfgServicioDialogState extends State<_CfgServicioDialog> {
  late final _tituloCtrl = TextEditingController(text: widget.existente?.titulo ?? '');
  late final _descripcionCtrl = TextEditingController(text: widget.existente?.descripcion ?? '');
  bool _intento = false;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _descripcionCtrl.dispose();
    super.dispose();
  }

  void _guardar() {
    setState(() => _intento = true);
    if (_tituloCtrl.text.trim().isEmpty) return;
    Navigator.of(context)
        .pop(ServicioItem(titulo: _tituloCtrl.text.trim(), descripcion: _descripcionCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return CfgDialogo(
      icono: Icons.build_circle_outlined,
      colores: AdminColores.verde,
      titulo: widget.existente == null ? 'Nuevo servicio' : 'Editar servicio',
      subtitulo: 'Tarjeta de la sección «Servicios»',
      ancho: 540,
      pie: CfgPieDialogo(onGuardar: _guardar),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CfgCampo(
          controller: _tituloCtrl,
          etiqueta: 'Título',
          hint: 'Ej.: Asesoría técnica',
          ayuda: 'Nombre corto del servicio.',
          icono: Icons.title,
          autofocus: true,
          errorText: _intento && _tituloCtrl.text.trim().isEmpty ? 'El título es obligatorio.' : null,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        CfgCampo(
          controller: _descripcionCtrl,
          etiqueta: 'Descripción',
          ayuda: 'Una o dos frases que expliquen el servicio.',
          maxLines: 4,
          minLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),
        const CfgEtiquetaSeccion('Vista previa', Icons.visibility_outlined),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.paper.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AdminColores.borde),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const InsigniaIcono(icono: Icons.build_outlined, tam: 40, colores: AdminColores.verde),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_tituloCtrl.text.trim().isEmpty ? 'Título del servicio' : _tituloCtrl.text.trim(),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.char)),
                const SizedBox(height: 4),
                Text(_descripcionCtrl.text.trim().isEmpty ? 'Descripción del servicio' : _descripcionCtrl.text.trim(),
                    style: const TextStyle(fontSize: 12.5, height: 1.45, color: AppColors.steel)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _CfgLegalDialog extends StatefulWidget {
  final SeccionLegal? existente;
  const _CfgLegalDialog({this.existente});

  @override
  State<_CfgLegalDialog> createState() => _CfgLegalDialogState();
}

class _CfgLegalDialogState extends State<_CfgLegalDialog> {
  late final _tituloCtrl = TextEditingController(text: widget.existente?.titulo ?? '');
  late final _textoCtrl = TextEditingController(text: widget.existente?.texto ?? '');
  late final _itemsCtrl = TextEditingController(text: (widget.existente?.items ?? []).join('\n'));
  bool _intento = false;

  @override
  void dispose() {
    _tituloCtrl.dispose();
    _textoCtrl.dispose();
    _itemsCtrl.dispose();
    super.dispose();
  }

  List<String> get _items =>
      _itemsCtrl.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  void _guardar() {
    setState(() => _intento = true);
    if (_tituloCtrl.text.trim().isEmpty) return;
    Navigator.of(context).pop(SeccionLegal(
      titulo: _tituloCtrl.text.trim(),
      texto: _textoCtrl.text.trim(),
      items: _items,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return CfgDialogo(
      icono: Icons.gavel_outlined,
      colores: AdminColores.violeta,
      titulo: widget.existente == null ? 'Nueva sección' : 'Editar sección',
      subtitulo: 'Apartado del aviso legal',
      ancho: 620,
      pie: CfgPieDialogo(onGuardar: _guardar),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CfgCampo(
          controller: _tituloCtrl,
          etiqueta: 'Título',
          hint: 'Ej.: 4. Uso del sitio',
          ayuda: 'Incluye el número si quieres que aparezca ordenado.',
          icono: Icons.title,
          autofocus: true,
          errorText: _intento && _tituloCtrl.text.trim().isEmpty ? 'El título es obligatorio.' : null,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        CfgCampo(
          controller: _textoCtrl,
          etiqueta: 'Texto',
          ayuda: 'Párrafo principal de la sección.',
          maxLines: 6,
          minLines: 4,
        ),
        const SizedBox(height: 14),
        CfgCampo(
          controller: _itemsCtrl,
          etiqueta: 'Puntos en lista (opcional)',
          ayuda: 'Escribe un punto por línea. Puntos detectados: ${_items.length}.',
          maxLines: 6,
          minLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}

// =====================================================================
// Usuarios y roles
// =====================================================================

List<Color> usrColoresPara(String texto) {
  const paleta = [
    AdminColores.azul,
    AdminColores.verde,
    AdminColores.ambar,
    AdminColores.violeta,
    AdminColores.rojo,
  ];
  final suma = texto.codeUnits.fold<int>(0, (a, b) => a + b);
  return paleta[suma % paleta.length];
}

class UsrAvatar extends StatelessWidget {
  final String texto;
  final double tam;
  final List<Color> colores;
  const UsrAvatar({super.key, required this.texto, this.tam = 52, this.colores = AdminColores.azul});

  @override
  Widget build(BuildContext context) {
    final t = texto.trim();
    return Container(
      width: tam,
      height: tam,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tam * 0.32),
        gradient: LinearGradient(colors: colores, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: colores.first.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5))],
      ),
      child: Text(t.isEmpty ? '?' : t.characters.first.toUpperCase(),
          style: TextStyle(color: Colors.white, fontSize: tam * 0.42, fontWeight: FontWeight.w900)),
    );
  }
}

/// Estadística compacta para el encabezado de Usuarios.
class UsrMiniStat extends StatelessWidget {
  final String valor;
  final String etiqueta;
  const UsrMiniStat(this.valor, this.etiqueta, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(valor, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, height: 1.1)),
          Text(etiqueta, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
        ]),
      );
}

class _UsrChipPermiso extends StatelessWidget {
  final String permiso;
  const _UsrChipPermiso(this.permiso);

  @override
  Widget build(BuildContext context) {
    final color = _colorPermiso(permiso).last;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_iconoPermiso(permiso), size: 14, color: color),
        const SizedBox(width: 5),
        Text(_etiquetaPermiso(permiso),
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }
}

class UsrTarjetaRol extends StatefulWidget {
  final Rol rol;
  final int usuarios;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;
  const UsrTarjetaRol({
    super.key,
    required this.rol,
    required this.usuarios,
    required this.onEditar,
    required this.onEliminar,
  });

  @override
  State<UsrTarjetaRol> createState() => _UsrTarjetaRolState();
}

class _UsrTarjetaRolState extends State<UsrTarjetaRol> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final rol = widget.rol;
    final colores = rol.id == 1 ? AdminColores.rojo : usrColoresPara(rol.nombre);
    final total = kPermisosDisponibles.length;
    final tiene = rol.permisos.length;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _hover ? colores.first.withValues(alpha: 0.5) : AdminColores.borde),
          boxShadow: [
            BoxShadow(
                color: colores.first.withValues(alpha: _hover ? 0.18 : 0.07),
                blurRadius: _hover ? 24 : 14,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            InsigniaIcono(
                icono: rol.id == 1 ? Icons.verified_user_outlined : Icons.shield_outlined, tam: 46, colores: colores),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(rol.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.char)),
                Text(
                    widget.usuarios == 0
                        ? 'Sin usuarios asignados'
                        : '${widget.usuarios} ${widget.usuarios == 1 ? 'usuario' : 'usuarios'}',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.steel)),
              ]),
            ),
            IconButton(tooltip: 'Editar rol', icon: const Icon(Icons.edit_outlined, size: 19), onPressed: widget.onEditar),
            IconButton(
              tooltip: rol.id == 1 ? 'Este rol no se puede eliminar' : 'Eliminar rol',
              icon: Icon(Icons.delete_outline, size: 19, color: rol.id == 1 ? AppColors.steel : AppColors.bad),
              onPressed: rol.id == 1 ? null : widget.onEliminar,
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            const Text('Permisos',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.steel)),
            const Spacer(),
            Text('$tiene de $total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: colores.last)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (tiene / total).clamp(0, 1).toDouble(),
              minHeight: 7,
              backgroundColor: colores.first.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(colores.first),
            ),
          ),
          const SizedBox(height: 12),
          if (rol.permisos.isEmpty)
            const Text('Sin permisos: solo ve la pantalla de Inicio.',
                style: TextStyle(fontSize: 12.5, color: AppColors.steel))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [for (final p in rol.permisos) _UsrChipPermiso(p)]),
        ]),
      ),
    );
  }
}

class UsrTarjetaUsuario extends StatefulWidget {
  final UsuarioAdmin usuario;
  final String rolNombre;
  final bool esActual;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;
  final Future<void> Function(bool activo) onActivo;
  const UsrTarjetaUsuario({
    super.key,
    required this.usuario,
    required this.rolNombre,
    required this.esActual,
    required this.onEditar,
    required this.onEliminar,
    required this.onActivo,
  });

  @override
  State<UsrTarjetaUsuario> createState() => _UsrTarjetaUsuarioState();
}

class _UsrTarjetaUsuarioState extends State<UsrTarjetaUsuario> {
  bool _hover = false;
  bool _ocupado = false;

  Future<void> _cambiar(bool v) async {
    setState(() => _ocupado = true);
    try {
      await widget.onActivo(v);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.usuario;
    final nombre = u.nombre.trim().isEmpty ? u.usuario : u.nombre.trim();
    final colores = u.activo ? usrColoresPara(u.usuario) : AdminColores.gris;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
        padding: const EdgeInsets.fromLTRB(18, 18, 10, 10),
        decoration: BoxDecoration(
          color: u.activo ? Colors.white : const Color(0xFFFAF9F7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _hover ? colores.first.withValues(alpha: 0.5) : AdminColores.borde),
          boxShadow: [
            BoxShadow(
                color: colores.first.withValues(alpha: _hover ? 0.18 : 0.07),
                blurRadius: _hover ? 24 : 14,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              UsrAvatar(texto: nombre, colores: colores, tam: 54),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                              color: u.activo ? AppColors.char : AppColors.steel)),
                    ),
                    if (widget.esActual) ...[
                      const SizedBox(width: 8),
                      const PillEstado('Tú', AppColors.red),
                    ],
                  ]),
                  Text('@${u.usuario}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.steel)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              PillEstado(widget.rolNombre, AdminColores.azul.last, icono: Icons.shield_outlined),
              PillEstado(u.activo ? 'Activo' : 'Inactivo', u.activo ? AppColors.ok : AppColors.steel,
                  icono: u.activo ? Icons.check_circle_outline : Icons.pause_circle_outline),
            ]),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          Row(children: [
            Tooltip(
              message: widget.esActual ? 'No puedes desactivar tu propia cuenta' : 'Activar o suspender el acceso',
              child: _ocupado
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)))
                  : Switch(
                      value: u.activo,
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.ok,
                      onChanged: widget.esActual ? null : _cambiar,
                    ),
            ),
            Expanded(
              child: Text(u.activo ? 'Acceso activo' : 'Acceso suspendido',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: u.activo ? AppColors.ok : AppColors.steel)),
            ),
            IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined, size: 19), onPressed: widget.onEditar),
            IconButton(
              tooltip: widget.esActual ? 'No puedes eliminar tu propia cuenta' : 'Eliminar',
              icon: Icon(Icons.delete_outline, size: 19, color: widget.esActual ? AppColors.steel : AppColors.bad),
              onPressed: widget.esActual ? null : widget.onEliminar,
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Búsqueda, filtros y cuadrícula de tarjetas de usuarios.
class UsrListaUsuarios extends StatefulWidget {
  final List<UsuarioAdmin> usuarios;
  final List<Rol> roles;
  final String usuarioActual;
  final void Function(UsuarioAdmin) onEditar;
  final void Function(UsuarioAdmin) onEliminar;
  final Future<void> Function(UsuarioAdmin, bool) onActivo;
  final VoidCallback? onNuevo;
  const UsrListaUsuarios({
    super.key,
    required this.usuarios,
    required this.roles,
    required this.usuarioActual,
    required this.onEditar,
    required this.onEliminar,
    required this.onActivo,
    required this.onNuevo,
  });

  @override
  State<UsrListaUsuarios> createState() => _UsrListaUsuariosState();
}

class _UsrListaUsuariosState extends State<UsrListaUsuarios> {
  String _busqueda = '';
  String _estado = 'todos';
  int? _rolId;

  String _nombreRol(int id) {
    final r = widget.roles.where((x) => x.id == id);
    return r.isEmpty ? 'Rol eliminado' : r.first.nombre;
  }

  @override
  Widget build(BuildContext context) {
    final q = _busqueda.trim().toLowerCase();
    final lista = widget.usuarios.where((u) {
      if (_estado == 'activos' && !u.activo) return false;
      if (_estado == 'inactivos' && u.activo) return false;
      if (_rolId != null && u.rolId != _rolId) return false;
      if (q.isEmpty) return true;
      return u.usuario.toLowerCase().contains(q) || u.nombre.toLowerCase().contains(q);
    }).toList();

    if (widget.usuarios.isEmpty) {
      return AdminPanel(
        child: VacioAdmin(
          icono: Icons.group_add_outlined,
          titulo: 'Aún no has creado usuarios adicionales',
          texto: widget.roles.isEmpty
              ? 'Primero crea un rol y luego asígnalo a las personas de tu equipo.'
              : 'Crea una cuenta para cada persona que necesite entrar al panel.',
          accion: widget.onNuevo == null
              ? null
              : ElevatedButton.icon(
                  onPressed: widget.onNuevo,
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: const Text('Nuevo usuario')),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 290,
          child: TextField(
            onChanged: (v) => setState(() => _busqueda = v),
            decoration: const InputDecoration(
              hintText: 'Buscar por nombre o usuario',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
          ),
        ),
        for (final e in const [('todos', 'Todos'), ('activos', 'Activos'), ('inactivos', 'Inactivos')])
          ChoiceChip(
            label: Text(e.$2),
            selected: _estado == e.$1,
            showCheckmark: false,
            selectedColor: AppColors.red,
            labelStyle: TextStyle(
                fontWeight: FontWeight.w700, color: _estado == e.$1 ? Colors.white : AppColors.char),
            onSelected: (_) => setState(() => _estado = e.$1),
          ),
        if (widget.roles.length > 1) ...[
          const SizedBox(width: 6),
          for (final r in widget.roles)
            FilterChip(
              avatar: const Icon(Icons.shield_outlined, size: 16),
              label: Text(r.nombre),
              selected: _rolId == r.id,
              onSelected: (v) => setState(() => _rolId = v ? r.id : null),
            ),
        ],
      ]),
      const SizedBox(height: 16),
      if (lista.isEmpty)
        const AdminPanel(
            child: VacioAdmin(
                icono: Icons.search_off, titulo: 'Sin resultados', texto: 'Prueba con otro nombre o quita los filtros.'))
      else
        CfgCuadricula(
          minAncho: 330,
          maxColumnas: 5,
          children: [
            for (final u in lista)
              UsrTarjetaUsuario(
                key: ValueKey('usuario-${u.id}'),
                usuario: u,
                rolNombre: _nombreRol(u.rolId),
                esActual: u.usuario == widget.usuarioActual,
                onEditar: () => widget.onEditar(u),
                onEliminar: () => widget.onEliminar(u),
                onActivo: (v) => widget.onActivo(u, v),
              ),
          ],
        ),
    ]);
  }
}

// ---------- Fortaleza de contraseña ----------

int usrPuntajeClave(String c) {
  var p = 0;
  if (c.length >= 8) p++;
  if (RegExp(r'[A-Za-z]').hasMatch(c) && RegExp(r'\d').hasMatch(c)) p++;
  if (RegExp(r'[a-z]').hasMatch(c) && RegExp(r'[A-Z]').hasMatch(c)) p++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(c) || c.length >= 12) p++;
  return p;
}

/// Misma política mínima que valida el servidor.
String? usrErrorClave(String c) {
  if (c.length < 8) return 'La contraseña debe tener al menos 8 caracteres.';
  if (c.length > 72) return 'La contraseña no puede superar los 72 caracteres.';
  if (!RegExp(r'[A-Za-z]').hasMatch(c) || !RegExp(r'\d').hasMatch(c)) {
    return 'La contraseña debe combinar letras y números.';
  }
  return null;
}

class UsrFortaleza extends StatelessWidget {
  final String clave;
  const UsrFortaleza({super.key, required this.clave});

  @override
  Widget build(BuildContext context) {
    final p = usrPuntajeClave(clave);
    final vacia = clave.isEmpty;
    const etiquetas = ['Muy débil', 'Débil', 'Aceptable', 'Buena', 'Fuerte'];
    final colores = [AppColors.bad, AppColors.bad, AppColors.warn, const Color(0xFF5B9A3A), AppColors.ok];
    final color = vacia ? AppColors.steel : colores[p];
    Widget req(bool ok, String t) => Padding(
          padding: const EdgeInsets.only(right: 14, top: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 14, color: ok ? AppColors.ok : AppColors.steel),
            const SizedBox(width: 5),
            Text(t, style: TextStyle(fontSize: 11.8, color: ok ? AppColors.char : AppColors.steel)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 6,
              margin: EdgeInsets.only(right: i < 3 ? 5 : 0),
              decoration: BoxDecoration(
                color: !vacia && i < max(p, 1) ? color : AdminColores.borde,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        const SizedBox(width: 12),
        SizedBox(
          width: 78,
          child: Text(vacia ? 'Sin clave' : etiquetas[p],
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: color)),
        ),
      ]),
      const SizedBox(height: 4),
      Wrap(children: [
        req(clave.length >= 8, '8 o más caracteres'),
        req(RegExp(r'[A-Za-z]').hasMatch(clave) && RegExp(r'\d').hasMatch(clave), 'Letras y números'),
        req(RegExp(r'[a-z]').hasMatch(clave) && RegExp(r'[A-Z]').hasMatch(clave), 'Mayúsculas y minúsculas'),
        req(RegExp(r'[^A-Za-z0-9]').hasMatch(clave) || clave.length >= 12, 'Un símbolo o 12+ caracteres'),
      ]),
    ]);
  }
}

String usrGenerarClave() {
  const letras = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ';
  const numeros = '23456789';
  const simbolos = '!@#\$%&*?';
  final r = Random.secure();
  final chars = <String>[
    for (var i = 0; i < 9; i++) letras[r.nextInt(letras.length)],
    for (var i = 0; i < 3; i++) numeros[r.nextInt(numeros.length)],
    simbolos[r.nextInt(simbolos.length)],
  ]..shuffle(r);
  return chars.join();
}

// ---------- Diálogo de rol ----------

Future<void> mostrarDialogoRol(BuildContext context,
        {Rol? rol, required Future<void> Function() alGuardar}) =>
    showDialog<void>(context: context, builder: (_) => _UsrRolDialog(rol: rol, alGuardar: alGuardar));

class _UsrRolDialog extends StatefulWidget {
  final Rol? rol;
  final Future<void> Function() alGuardar;
  const _UsrRolDialog({this.rol, required this.alGuardar});

  @override
  State<_UsrRolDialog> createState() => _UsrRolDialogState();
}

class _UsrRolDialogState extends State<_UsrRolDialog> {
  late final _nombreCtrl = TextEditingController(text: widget.rol?.nombre ?? '');
  late final Set<String> _permisos = {...(widget.rol?.permisos ?? [])};
  String? _error;
  bool _guardando = false;
  bool _intento = false;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _intento = true);
    final nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      if (widget.rol == null) {
        await ApiService.instance.crearRol(nombre, _permisos.toList());
      } else {
        await ApiService.instance.actualizarRol(widget.rol!.id, nombre, _permisos.toList());
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.alGuardar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final esNuevo = widget.rol == null;
    return CfgDialogo(
      icono: Icons.shield_outlined,
      colores: AdminColores.violeta,
      titulo: esNuevo ? 'Nuevo rol' : 'Editar rol',
      subtitulo: 'Define qué secciones del panel puede usar',
      ancho: 680,
      pie: CfgPieDialogo(
        onGuardar: _guardar,
        guardando: _guardando,
        error: _error,
        etiquetaGuardar: esNuevo ? 'Crear rol' : 'Guardar cambios',
        izquierda: Align(
          alignment: Alignment.centerLeft,
          child: PillEstado('${_permisos.length} de ${kPermisosDisponibles.length} permisos', AdminColores.violeta.last,
              icono: Icons.key_outlined),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const CfgEtiquetaSeccion('Identificación', Icons.badge_outlined),
        const SizedBox(height: 12),
        CfgCampo(
          controller: _nombreCtrl,
          etiqueta: 'Nombre del rol',
          hint: 'Ej.: Vendedor, Bodeguero',
          ayuda: 'Un nombre corto que describa la función de la persona.',
          icono: Icons.shield_outlined,
          autofocus: true,
          errorText: _intento && _nombreCtrl.text.trim().isEmpty ? 'El nombre es obligatorio.' : null,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 22),
        CfgEtiquetaSeccion(
          'Permisos',
          Icons.toggle_on_outlined,
          derecha: Wrap(spacing: 4, children: [
            TextButton(
              onPressed: () => setState(() => _permisos.addAll(kPermisosDisponibles)),
              child: const Text('Todos'),
            ),
            TextButton(
              onPressed: () => setState(_permisos.clear),
              child: const Text('Ninguno'),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        CfgCuadricula(
          minAncho: 280,
          maxColumnas: 2,
          espacio: 12,
          children: [
            for (final p in kPermisosDisponibles)
              _UsrPermisoSwitch(
                permiso: p,
                activo: _permisos.contains(p),
                onCambio: (v) => setState(() => v ? _permisos.add(p) : _permisos.remove(p)),
              ),
          ],
        ),
        if (_permisos.isEmpty) ...[
          const SizedBox(height: 12),
          const CfgAviso(
            texto: 'Sin permisos, las personas con este rol solo verán la pantalla de Inicio.',
            color: AppColors.warn,
            icono: Icons.info_outline,
          ),
        ],
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _UsrPermisoSwitch extends StatelessWidget {
  final String permiso;
  final bool activo;
  final ValueChanged<bool> onCambio;
  const _UsrPermisoSwitch({required this.permiso, required this.activo, required this.onCambio});

  @override
  Widget build(BuildContext context) {
    final colores = _colorPermiso(permiso);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onCambio(!activo),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            color: activo ? colores.first.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: activo ? colores.first.withValues(alpha: 0.55) : AdminColores.borde, width: 1.3),
          ),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: activo ? LinearGradient(colors: colores) : null,
                color: activo ? null : AppColors.paper,
              ),
              child: Icon(_iconoPermiso(permiso), size: 19, color: activo ? Colors.white : AppColors.steel),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_etiquetaPermiso(permiso),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: AppColors.char)),
                Text(kDescripcionPermiso[permiso] ?? kNombrePermiso[permiso] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, height: 1.3, color: AppColors.steel)),
              ]),
            ),
            Switch(
              value: activo,
              activeThumbColor: Colors.white,
              activeTrackColor: colores.last,
              onChanged: onCambio,
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------- Diálogo de usuario ----------

Future<void> mostrarDialogoUsuario(
  BuildContext context, {
  UsuarioAdmin? usuario,
  required List<Rol> roles,
  required Future<void> Function() alGuardar,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _UsrUsuarioDialog(usuario: usuario, roles: roles, alGuardar: alGuardar),
    );

class _UsrUsuarioDialog extends StatefulWidget {
  final UsuarioAdmin? usuario;
  final List<Rol> roles;
  final Future<void> Function() alGuardar;
  const _UsrUsuarioDialog({this.usuario, required this.roles, required this.alGuardar});

  @override
  State<_UsrUsuarioDialog> createState() => _UsrUsuarioDialogState();
}

class _UsrUsuarioDialogState extends State<_UsrUsuarioDialog> {
  late final _usuarioCtrl = TextEditingController(text: widget.usuario?.usuario ?? '');
  late final _nombreCtrl = TextEditingController(text: widget.usuario?.nombre ?? '');
  final _passwordCtrl = TextEditingController();
  late int? _rolId = widget.usuario?.rolId ?? (widget.roles.isNotEmpty ? widget.roles.first.id : null);
  late bool _activo = widget.usuario?.activo ?? true;
  bool _verClave = false;
  String? _error;
  bool _guardando = false;
  bool _intento = false;

  bool get _esNuevo => widget.usuario == null;

  @override
  void dispose() {
    _usuarioCtrl.dispose();
    _nombreCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String? get _errUsuario => _intento && _usuarioCtrl.text.trim().isEmpty ? 'El usuario es obligatorio.' : null;

  String? get _errClave {
    final c = _passwordCtrl.text;
    if (_esNuevo && c.isEmpty) return _intento ? 'La contraseña es obligatoria.' : null;
    if (c.isEmpty) return null;
    return _intento ? usrErrorClave(c) : null;
  }

  Future<void> _guardar() async {
    setState(() => _intento = true);
    if (_usuarioCtrl.text.trim().isEmpty) return;
    if (_esNuevo && _passwordCtrl.text.isEmpty) return;
    if (_passwordCtrl.text.isNotEmpty && usrErrorClave(_passwordCtrl.text) != null) return;
    if (_rolId == null) {
      setState(() => _error = 'Debes seleccionar un rol.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final u = widget.usuario;
      if (u == null) {
        await ApiService.instance.crearUsuarioAdmin(
          usuario: _usuarioCtrl.text.trim(),
          password: _passwordCtrl.text,
          rolId: _rolId!,
          nombre: _nombreCtrl.text.trim(),
        );
      } else {
        await ApiService.instance.actualizarUsuarioAdmin(
          u.id,
          nombre: _nombreCtrl.text.trim(),
          rolId: _rolId,
          password: _passwordCtrl.text,
          activo: _activo,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.alGuardar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombreAvatar = _nombreCtrl.text.trim().isNotEmpty ? _nombreCtrl.text : _usuarioCtrl.text;
    return CfgDialogo(
      icono: _esNuevo ? Icons.person_add_alt_1_outlined : Icons.manage_accounts_outlined,
      colores: AdminColores.azul,
      titulo: _esNuevo ? 'Nuevo usuario' : 'Editar usuario',
      subtitulo: _esNuevo ? 'Crea una cuenta para entrar al panel' : '@${widget.usuario!.usuario}',
      ancho: 640,
      pie: CfgPieDialogo(
        onGuardar: _guardar,
        guardando: _guardando,
        error: _error,
        etiquetaGuardar: _esNuevo ? 'Crear usuario' : 'Guardar cambios',
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const CfgEtiquetaSeccion('Cuenta', Icons.person_outline),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 14),
            child: UsrAvatar(
                texto: nombreAvatar, tam: 56, colores: usrColoresPara(_usuarioCtrl.text.isEmpty ? 'u' : _usuarioCtrl.text)),
          ),
          Expanded(
            child: Column(children: [
              CfgCampo(
                controller: _usuarioCtrl,
                etiqueta: 'Nombre de usuario',
                ayuda: _esNuevo ? 'Con este nombre inicia sesión. No se puede cambiar después.' : 'No se puede cambiar.',
                icono: Icons.alternate_email,
                autofocus: _esNuevo,
                errorText: _errUsuario,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              CfgCampo(
                controller: _nombreCtrl,
                etiqueta: 'Nombre completo (opcional)',
                ayuda: 'Se muestra en el panel en lugar del usuario.',
                icono: Icons.badge_outlined,
                onChanged: (_) => setState(() {}),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 22),
        CfgEtiquetaSeccion(_esNuevo ?  'Contraseña' : 'Cambiar contraseña', Icons.lock_outline),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordCtrl,
          obscureText: !_verClave,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: _esNuevo ? 'Contraseña' : 'Nueva contraseña (opcional)',
            helperText: _esNuevo ? null : 'Déjala vacía para mantener la actual.',
            errorText: _errClave,
            errorMaxLines: 2,
            prefixIcon: const Icon(Icons.password, size: 20),
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Generar contraseña segura',
                icon: const Icon(Icons.auto_fix_high, size: 20),
                onPressed: () => setState(() {
                  _passwordCtrl.text = usrGenerarClave();
                  _verClave = true;
                }),
              ),
              IconButton(
                tooltip: _verClave ? 'Ocultar' : 'Mostrar',
                icon: Icon(_verClave ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                onPressed: () => setState(() => _verClave = !_verClave),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        UsrFortaleza(clave: _passwordCtrl.text),
        const SizedBox(height: 22),
        const CfgEtiquetaSeccion('Rol y permisos', Icons.shield_outlined),
        const SizedBox(height: 12),
        if (widget.roles.isEmpty)
          const CfgAviso(
              texto: 'Aún no hay roles. Crea uno primero para poder asignarlo.',
              color: AppColors.warn,
              icono: Icons.info_outline)
        else
          CfgCuadricula(
            minAncho: 270,
            maxColumnas: 2,
            espacio: 12,
            children: [
              for (final r in widget.roles)
                _UsrRolOpcion(rol: r, seleccionado: _rolId == r.id, onTap: () => setState(() => _rolId = r.id)),
            ],
          ),
        if (!_esNuevo) ...[
          const SizedBox(height: 22),
          const CfgEtiquetaSeccion('Estado', Icons.toggle_on_outlined),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
            decoration: BoxDecoration(
              color: (_activo ? AppColors.ok : AppColors.steel).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: (_activo ? AppColors.ok : AppColors.steel).withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Icon(_activo ? Icons.check_circle_outline : Icons.pause_circle_outline,
                  color: _activo ? AppColors.ok : AppColors.steel),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_activo ? 'Usuario activo' : 'Usuario inactivo',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: AppColors.char)),
                  Text(_activo ? 'Puede iniciar sesión en el panel.' : 'No podrá iniciar sesión hasta que lo actives.',
                      style: const TextStyle(fontSize: 12, color: AppColors.steel)),
                ]),
              ),
              Switch(
                value: _activo,
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.ok,
                onChanged: (v) => setState(() => _activo = v),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _UsrRolOpcion extends StatelessWidget {
  final Rol rol;
  final bool seleccionado;
  final VoidCallback onTap;
  const _UsrRolOpcion({required this.rol, required this.seleccionado, required this.onTap});

  String get _descripcion {
    if (rol.permisos.isEmpty) return 'Sin permisos: solo ve el Inicio.';
    if (kPermisosDisponibles.every(rol.permisos.contains)) return 'Acceso total al panel.';
    return rol.permisos.map(_etiquetaPermiso).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final color = seleccionado ? AppColors.red : AppColors.steel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: seleccionado ? AppColors.red.withValues(alpha: 0.06) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: seleccionado ? AppColors.red : AdminColores.borde, width: seleccionado ? 1.6 : 1.2),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(seleccionado ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(rol.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: AppColors.char)),
                const SizedBox(height: 3),
                Text(_descripcion,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.8, height: 1.35, color: AppColors.steel)),
                if (rol.permisos.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 5, runSpacing: 5, children: [
                    for (final p in rol.permisos)
                      Tooltip(
                        message: _etiquetaPermiso(p),
                        child: Icon(_iconoPermiso(p), size: 16, color: _colorPermiso(p).last),
                      ),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
