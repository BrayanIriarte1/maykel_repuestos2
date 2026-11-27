// Página "no encontrada" (404) con la marca Maykel Repuestos 2.
//
// La ve quien abre en el navegador una dirección que no existe (por ejemplo
// /api/docs en producción o /hola). La API sigue respondiendo JSON: esta
// página solo se usa cuando el navegador pide HTML (cabecera Accept).
//
// Es HTML autocontenido (sin fuentes ni scripts externos) para que cargue al
// instante. Los datos de contacto salen de Configuración del panel.

const _escapes = {'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'};

String _e(String s) => s.replaceAllMapped(RegExp('[&<>"\']'), (m) => _escapes[m[0]]!);

/// "56989552407" -> "+56 9 8955 2407" (si no calza el formato, se deja tal cual).
String _telefonoLegible(String numero) {
  final d = numero.replaceAll(RegExp(r'\D'), '');
  if (d.length == 11 && d.startsWith('569')) {
    return '+56 9 ${d.substring(3, 7)} ${d.substring(7)}';
  }
  return numero;
}

const _logoWhatsapp =
    '<svg viewBox="0 0 32 32" aria-hidden="true"><path fill="currentColor" d="M16 3C8.8 3 3 8.7 3 15.8c0 2.5.7 4.9 2 7L3 29l6.4-2c2 1.1 4.3 1.7 6.6 1.7 7.2 0 13-5.7 13-12.8S23.2 3 16 3zm0 23.4c-2.1 0-4.1-.6-5.9-1.6l-.4-.3-3.8 1.2 1.2-3.7-.3-.4c-1.2-1.8-1.8-3.8-1.8-5.9C5 9.9 9.9 5.1 16 5.1s11 4.8 11 10.7-4.9 10.6-11 10.6zm6-7.9c-.3-.2-1.9-1-2.2-1.1-.3-.1-.5-.2-.7.2-.2.3-.8 1-1 1.2-.2.2-.4.2-.7.1-.3-.2-1.4-.5-2.6-1.6-1-.9-1.6-1.9-1.8-2.2-.2-.3 0-.5.1-.7l.5-.6c.2-.2.2-.3.3-.6.1-.2 0-.4 0-.6l-1-2.4c-.3-.6-.5-.5-.7-.5h-.6c-.2 0-.6.1-.9.4-.3.3-1.2 1.1-1.2 2.8s1.2 3.2 1.4 3.5c.2.2 2.4 3.6 5.8 5 .8.4 1.4.6 1.9.7.8.3 1.6.2 2.2.1.7-.1 1.9-.8 2.2-1.5.3-.7.3-1.4.2-1.5-.1-.2-.3-.3-.6-.4z"/></svg>';

/// Neumático que hace de "0" en el 404.
const _neumatico = '''
<svg class="rueda" viewBox="0 0 120 120" aria-hidden="true">
  <circle cx="60" cy="60" r="56" fill="#1A1A1C"/>
  <circle cx="60" cy="60" r="56" fill="none" stroke="#3a3a3f" stroke-width="6" stroke-dasharray="6 7"/>
  <circle cx="60" cy="60" r="34" fill="#D91E2B"/>
  <circle cx="60" cy="60" r="34" fill="none" stroke="#9E1119" stroke-width="3"/>
  <g fill="#F2EFE9">
    <circle cx="60" cy="60" r="8"/>
    <circle cx="60" cy="38" r="4"/><circle cx="81" cy="53" r="4"/><circle cx="73" cy="78" r="4"/>
    <circle cx="47" cy="78" r="4"/><circle cx="39" cy="53" r="4"/>
  </g>
</svg>''';

String paginaNoEncontrada({
  String nombre = 'Maykel Repuestos 2',
  String direccion = 'Vargas #2275, Calama, Región de Antofagasta',
  String email = '',
  String whatsapp = '',
  String horario = '',
}) {
  final wa = whatsapp.replaceAll(RegExp(r'\D'), '');
  final enlaceWa = wa.isEmpty
      ? ''
      : 'https://wa.me/$wa?text=${Uri.encodeComponent('Hola $nombre, busco un repuesto.')}';
  final horarioHtml = _e(horario).replaceAll('\n', '<br>');

  return '''<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Página no encontrada | ${_e(nombre)}</title>
<link rel="icon" type="image/png" href="/favicon.png">
<style>
  :root { --rojo:#D91E2B; --rojo2:#9E1119; --carbon:#1A1A1C; --carbon2:#242427; --papel:#F2EFE9; --acero:#767B84; }
  * { box-sizing: border-box; }
  html, body { margin: 0; }
  body { min-height: 100vh; display: flex; flex-direction: column; background: var(--papel);
         color: var(--carbon); font-family: "Segoe UI", Roboto, Arial, sans-serif; }
  a { color: inherit; }

  header { background: var(--carbon); border-bottom: 4px solid var(--rojo); }
  .barra { max-width: 1200px; margin: 0 auto; padding: 14px 24px; display: flex;
           align-items: center; justify-content: space-between; gap: 18px; }
  .logo img { height: 58px; display: block; border-radius: 10px; }
  nav { display: flex; gap: 6px; flex-wrap: wrap; }
  nav a { color: #fff; text-decoration: none; font-weight: 700; padding: 9px 14px; border-radius: 10px; }
  nav a:hover { background: rgba(255,255,255,.1); }

  main { flex: 1; display: flex; align-items: center; justify-content: center; padding: 56px 20px;
         background: radial-gradient(circle at 50% 35%, #fff 0, var(--papel) 60%); }
  .caja { text-align: center; max-width: 640px; }
  .etiqueta { display: inline-block; color: var(--rojo); background: rgba(217,30,43,.08);
              border: 1px solid rgba(217,30,43,.25); padding: 6px 14px; border-radius: 99px;
              font-size: 13px; font-weight: 800; letter-spacing: .12em; }
  .numero { display: flex; align-items: center; justify-content: center; gap: 10px; margin: 22px 0 8px;
            font-size: clamp(96px, 20vw, 170px); font-weight: 900; line-height: 1; color: var(--carbon); }
  .rueda { width: .88em; height: .88em; animation: girar 6s linear infinite;
           filter: drop-shadow(0 12px 18px rgba(0,0,0,.25)); }
  @keyframes girar { to { transform: rotate(360deg); } }
  @media (prefers-reduced-motion: reduce) { .rueda { animation: none; } }
  h1 { font-size: clamp(24px, 4vw, 34px); margin: 10px 0 10px; }
  p.texto { color: #55585f; font-size: 17px; line-height: 1.55; margin: 0 auto 30px; max-width: 520px; }
  .botones { display: flex; gap: 12px; justify-content: center; flex-wrap: wrap; }
  .boton { display: inline-flex; align-items: center; gap: 10px; padding: 14px 24px; border-radius: 14px;
           font-weight: 800; font-size: 16px; text-decoration: none; transition: transform .15s, box-shadow .15s; }
  .boton:hover { transform: translateY(-2px); }
  .primario { background: linear-gradient(135deg, #E53945, var(--rojo2)); color: #fff;
              box-shadow: 0 10px 22px rgba(217,30,43,.35); }
  .whatsapp { background: #fff; color: #128C4A; border: 2px solid #25D366; }
  .whatsapp svg { width: 22px; height: 22px; }

  footer { background: var(--carbon); color: #fff; }
  .columnas { max-width: 1200px; margin: 0 auto; padding: 34px 24px; display: grid;
              grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 26px; text-align: center; }
  .columnas h2 { font-size: 13px; letter-spacing: .14em; color: #FF5A64; margin: 0 0 10px; }
  .columnas p, .columnas a { margin: 0; color: #e8e5df; text-decoration: none; line-height: 1.6; }
  .columnas a:hover { color: #fff; text-decoration: underline; }
  .derechos { text-align: center; padding: 14px; font-size: 13px; color: #9a9ca3; border-top: 1px solid #333; }

  .flotante { position: fixed; right: 22px; bottom: 22px; width: 60px; height: 60px; border-radius: 50%;
              background: #25D366; color: #fff; display: flex; align-items: center; justify-content: center;
              box-shadow: 0 10px 24px rgba(0,0,0,.3); }
  .flotante svg { width: 34px; height: 34px; }

  @media (max-width: 640px) {
    .barra { flex-direction: column; padding: 12px 16px; }
    .logo img { height: 48px; }
    nav a { padding: 7px 10px; font-size: 15px; }
    .boton { width: 100%; justify-content: center; }
    .flotante { right: 14px; bottom: 14px; width: 54px; height: 54px; }
  }
</style>
</head>
<body>
<header>
  <div class="barra">
    <a class="logo" href="/" aria-label="Ir al inicio de ${_e(nombre)}"><img src="/assets/assets/images/logo_maykel.jpg" alt="${_e(nombre)}"></a>
    <nav>
      <a href="/">Inicio</a>
      <a href="/">Catálogo</a>
      ${enlaceWa.isEmpty ? '' : '<a href="$enlaceWa" target="_blank" rel="noopener">Contacto</a>'}
    </nav>
  </div>
</header>

<main>
  <div class="caja">
    <span class="etiqueta">ERROR 404</span>
    <div class="numero" aria-label="404"><span>4</span>$_neumatico<span>4</span></div>
    <h1>Esta página se quedó en pana</h1>
    <p class="texto">La dirección que buscas no existe o ya no está disponible.
      Vuelve al inicio para revisar el catálogo, o escríbenos y te ayudamos a encontrar tu repuesto.</p>
    <div class="botones">
      <a class="boton primario" href="/">Volver al inicio</a>
      ${enlaceWa.isEmpty ? '' : '<a class="boton whatsapp" href="$enlaceWa" target="_blank" rel="noopener">$_logoWhatsapp Escríbenos por WhatsApp</a>'}
    </div>
  </div>
</main>

<footer>
  <div class="columnas">
    <div><h2>DIRECCIÓN</h2><p>${_e(direccion)}</p></div>
    ${email.isEmpty ? '' : '<div><h2>CORREO</h2><a href="mailto:${_e(email)}">${_e(email)}</a></div>'}
    ${wa.isEmpty ? '' : '<div><h2>WHATSAPP</h2><a href="$enlaceWa" target="_blank" rel="noopener">${_e(_telefonoLegible(whatsapp))}</a></div>'}
    ${horario.isEmpty ? '' : '<div><h2>HORARIO</h2><p>$horarioHtml</p></div>'}
  </div>
  <div class="derechos">© ${DateTime.now().year} ${_e(nombre)}</div>
</footer>

${enlaceWa.isEmpty ? '' : '<a class="flotante" href="$enlaceWa" target="_blank" rel="noopener" aria-label="Escríbenos por WhatsApp">$_logoWhatsapp</a>'}
</body>
</html>''';
}
