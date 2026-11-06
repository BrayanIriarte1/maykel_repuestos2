-- ============================================================================
-- Migraciones idempotentes. El servidor las aplica al arrancar (lib/db.dart).
-- Se pueden ejecutar tantas veces como se quiera: todo usa IF NOT EXISTS.
-- ============================================================================

-- Búsqueda de texto rápida (ILIKE '%algo%') sobre el catálogo.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_productos_nombre_trgm
  ON productos USING gin (nombre gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_productos_codigo_trgm
  ON productos USING gin (codigo_interno gin_trgm_ops);

-- Filtros más usados del catálogo público y del panel.
CREATE INDEX IF NOT EXISTS idx_productos_estado_marca
  ON productos (estado_catalogo, marca_referencia, modelo_referencia);

CREATE INDEX IF NOT EXISTS idx_productos_stock
  ON productos (stock_actual) WHERE stock_actual <= 3;

CREATE INDEX IF NOT EXISTS idx_productos_sync
  ON productos (ultima_sincronizacion DESC);

-- Claves foráneas sin índice (borrados y joins lentos).
CREATE INDEX IF NOT EXISTS idx_reserva_detalles_reserva ON reserva_detalles (reserva_id);
CREATE INDEX IF NOT EXISTS idx_reserva_detalles_producto ON reserva_detalles (producto_id);
CREATE INDEX IF NOT EXISTS idx_reservas_creado ON reservas (creado_en DESC);
CREATE INDEX IF NOT EXISTS idx_reservas_estado ON reservas (estado);
CREATE INDEX IF NOT EXISTS idx_ventas_producto ON ventas (producto_id);
CREATE INDEX IF NOT EXISTS idx_metricas_producto ON metricas_demanda (producto_id);
CREATE INDEX IF NOT EXISTS idx_usuarios_rol ON usuarios (rol_id);

-- Registros de auditoría y sincronización: consulta por fecha y limpieza.
CREATE INDEX IF NOT EXISTS idx_logs_sync_fecha ON logs_sincronizacion (fecha_inicio DESC);
CREATE INDEX IF NOT EXISTS idx_logs_auditoria_fecha ON logs_auditoria (fecha DESC);

-- Integridad: precios y stock nunca negativos (el stock ya lo exige el esquema).
ALTER TABLE productos DROP CONSTRAINT IF EXISTS productos_precio_no_negativo;
ALTER TABLE productos ADD CONSTRAINT productos_precio_no_negativo
  CHECK (precio_referencia IS NULL OR precio_referencia >= 0) NOT VALID;

-- Un nombre de producto nunca debe quedar vacío.
ALTER TABLE productos DROP CONSTRAINT IF EXISTS productos_nombre_no_vacio;
ALTER TABLE productos ADD CONSTRAINT productos_nombre_no_vacio
  CHECK (length(btrim(nombre)) > 0) NOT VALID;

-- Origen del producto: SISTEMA (viene del sync con el cliente) o MANUAL (creado en el panel).
-- Solo los de SISTEMA se ponen en stock 0 cuando el cliente deja de enviarlos.
ALTER TABLE productos ADD COLUMN IF NOT EXISTS origen VARCHAR(10) NOT NULL DEFAULT 'MANUAL';
-- Solo se ejecuta si aún no hay ningún producto marcado SISTEMA (primera vez / base restaurada).
UPDATE productos SET origen = 'SISTEMA'
  WHERE origen = 'MANUAL' AND codigo_interno NOT LIKE 'MR-%'
    AND NOT EXISTS (SELECT 1 FROM productos WHERE origen = 'SISTEMA');

-- Reservas: indica si ya se descontó su stock (confirmada/entregada), para no descontar dos veces.
ALTER TABLE reservas ADD COLUMN IF NOT EXISTS stock_descontado BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_reservas_retenidas ON reservas (id) WHERE stock_descontado;

-- Ventas generadas al entregar una reserva (se anulan si la reserva deja de estar entregada).
ALTER TABLE ventas ADD COLUMN IF NOT EXISTS reserva_id INT REFERENCES reservas(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_ventas_reserva ON ventas (reserva_id) WHERE reserva_id IS NOT NULL;
