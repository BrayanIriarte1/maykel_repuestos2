final Map<String, String> _datos = {};

String? leerAlmacen(String clave) => _datos[clave];

void guardarAlmacen(String clave, String valor) => _datos[clave] = valor;

void borrarAlmacen(String clave) => _datos.remove(clave);
