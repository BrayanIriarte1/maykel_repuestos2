/// Almacenamiento de la sesión del administrador.
/// En el navegador usa sessionStorage (sobrevive a recargar la página pero se
/// borra al cerrar la pestaña); fuera del navegador es solo memoria.
export 'almacen_memoria.dart' if (dart.library.js_interop) 'almacen_web.dart';
