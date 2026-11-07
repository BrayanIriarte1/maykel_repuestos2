import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool descargarBytes(Uint8List bytes, String nombre, String mime) {
  try {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
    final url = web.URL.createObjectURL(blob);
    final a = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = nombre;
    web.document.body!.append(a);
    a.click();
    a.remove();
    web.URL.revokeObjectURL(url);
    return true;
  } catch (_) {
    return false;
  }
}
