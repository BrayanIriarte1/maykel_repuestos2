# Manual de usuario — Maykel Repuestos 2

Sitio en producción: **https://maykel-repuestos2.cl**

## Cliente (sitio público)
1. Entrar al sitio y buscar escribiendo **cualquier palabra del producto, en cualquier orden** (por ejemplo «0w20 chery» o «aceite chery»), o filtrar por categoría, marca o modelo. Si no hay resultados, el sitio propone «¿Quisiste decir…?».
2. Los productos muestran disponibilidad, nunca precio.
3. Pulsar **Agregar a reserva** en cada repuesto que necesites. Aparece el botón flotante **Mi reserva** con el total de unidades.
4. En **Mi reserva** ajusta cantidades (o quita repuestos), escribe nombre, teléfono y correo, acepta el tratamiento de datos y pulsa **Finalizar reserva**.
5. Se entrega un folio `RES-####` y el **comprobante PDF se descarga solo**. También puedes enviarlo al equipo por WhatsApp o correo.
6. Si un producto está agotado, el botón **Agotado · Me interesa** registra tu interés (el equipo lo usa para decidir qué reponer).
7. Si no encuentras lo que buscas, usa **Solicitar reserva especial de este repuesto** (abre WhatsApp con tu búsqueda).

La reserva no es una compra ni un cobro: queda *pendiente* hasta que un vendedor confirma que el repuesto está en el local.

## Vendedor / administrador (panel)
Entrar con el enlace **Admin**. Tras 5 intentos fallidos la cuenta se bloquea 15 min. La sesión dura 8 h y no se pierde al recargar la página.
- **Inicio**: reservas por atender (Confirmar / Rechazar) y repuestos por reponer.
- **Analítica**: ventas, reservas y demanda insatisfecha (búsquedas sin resultado e interés en productos agotados).
- **Reservas**: confirmar, entregar o rechazar. *Confirmada* descuenta el stock; *entregada* registra la venta; *rechazada* devuelve el stock.
- **Ventas**: registrar una venta de mostrador; descuenta stock automáticamente.
- **Stock / Catálogo**: crear, editar y ocultar productos; alerta de stock bajo. El stock y los precios de los productos del sistema del cliente se actualizan solos cada 30 minutos.
- **Usuarios y roles** (solo superadmin): crear cuentas y permisos.
- **Configuración**: editar los textos del sitio.
- Reportes PDF de ventas, reservas y stock.

## Capacitación (sugerida, 1 h)
Demo de cada rol. Ejercicio: crear una reserva con 2 repuestos → confirmarla → entregarla → revisar la analítica.

## Panel: novedades
- **Inicio / Analítica / Catálogo / Reservas / Stock / Usuarios / Configuración** rediseñados: tarjetas con indicadores, tablero de reservas por estado, catálogo en cuadrícula con fotos y paginación, usuarios y roles en tarjetas.
- **Configuración → Notificaciones y sincronización:** estado del correo y WhatsApp, botones de prueba, guía para la contraseña de aplicación de Google y botón **Sincronizar ahora** con el historial.
- El cliente recibe un correo con su comprobante PDF al reservar (si el correo está configurado en el servidor).

