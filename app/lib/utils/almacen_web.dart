import 'package:web/web.dart' as web;

String? leerAlmacen(String clave) {
  try {
    return web.window.sessionStorage.getItem(clave);
  } catch (_) {
    return null;
  }
}

void guardarAlmacen(String clave, String valor) {
  try {
    web.window.sessionStorage.setItem(clave, valor);
  } catch (_) {
    // Modo privado o almacenamiento bloqueado: la sesión dura solo hasta recargar.
  }
}

void borrarAlmacen(String clave) {
  try {
    web.window.sessionStorage.removeItem(clave);
  } catch (_) {}
}
