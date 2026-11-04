-- Active: 1793756482913@@127.0.0.1@5432@maykel_repuestos2
-- Active: 1763267482657@@127.0.0.1@5432@maykel_repuestos2
-- ============================================================================
-- PROYECTO DE TÍTULO: MAYKEL REPUESTOS 2 (CALAMA)
-- Script DDL + Seed Data Unificado (3NF + Compatibilidad Frontend/Admin)
-- ============================================================================

DROP TABLE IF EXISTS ventas CASCADE;
DROP TABLE IF EXISTS logs_auditoria CASCADE;
DROP TABLE IF EXISTS logs_sincronizacion CASCADE;
DROP TABLE IF EXISTS metricas_demanda CASCADE;
DROP TABLE IF EXISTS reserva_detalles CASCADE;
DROP TABLE IF EXISTS reservas CASCADE;
DROP TABLE IF EXISTS producto_compatibilidad CASCADE;
DROP TABLE IF EXISTS productos CASCADE;
DROP TABLE IF EXISTS categorias CASCADE;
DROP TABLE IF EXISTS versiones_vehiculo CASCADE;
DROP TABLE IF EXISTS modelos CASCADE;
DROP TABLE IF EXISTS marcas CASCADE;
DROP TABLE IF EXISTS usuarios CASCADE;
DROP TABLE IF EXISTS roles CASCADE;
DROP TABLE IF EXISTS configuracion_sitio CASCADE;

-- ============================================================================
-- 1. SEGURIDAD, ROLES Y USUARIOS (RBAC - RNF03 + Panel Admin Compañera)
-- ============================================================================
CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(60) UNIQUE NOT NULL,
    permisos JSONB NOT NULL DEFAULT '[]'::jsonb
);

CREATE TABLE usuarios (
    id SERIAL PRIMARY KEY,
    usuario VARCHAR(60) UNIQUE NOT NULL,        -- Para login del panel (ej: 'admin', 'francisca')
    nombre VARCHAR(100) NOT NULL,
    email VARCHAR(120) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,        -- Formato sha256$<sal>$<hash>
    rol VARCHAR(30) NOT NULL DEFAULT 'SUPERADMIN' CHECK (rol IN ('SUPERADMIN', 'VENDEDOR')),
    rol_id INT REFERENCES roles(id) ON DELETE SET NULL,
    activo BOOLEAN DEFAULT TRUE,
    creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 2. CONTENIDO EDITABLE DEL SITIO WEB (Para home_screen y aviso_legal_screen)
-- ============================================================================
CREATE TABLE configuracion_sitio (
    clave VARCHAR(50) PRIMARY KEY,
    contenido JSONB NOT NULL,
    actualizado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 3. TAXONOMÍA VEHICULAR DE MARCAS CHINAS (3NF - HU-02 / RF02)
-- Jerarquía: Marca -> Modelo -> Año -> Motor -> Cilindrada
-- ============================================================================
CREATE TABLE marcas (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(80) UNIQUE NOT NULL,
    origen VARCHAR(50) DEFAULT 'China',
    activo BOOLEAN DEFAULT TRUE
);

CREATE TABLE modelos (
    id SERIAL PRIMARY KEY,
    marca_id INT NOT NULL REFERENCES marcas(id) ON DELETE CASCADE,
    nombre VARCHAR(100) NOT NULL,
    UNIQUE(marca_id, nombre)
);

CREATE TABLE versiones_vehiculo (
    id SERIAL PRIMARY KEY,
    modelo_id INT NOT NULL REFERENCES modelos(id) ON DELETE CASCADE,
    anio INT NOT NULL CHECK (anio >= 2000 AND anio <= 2030),
    motor VARCHAR(80) NOT NULL,
    cilindrada VARCHAR(40) NOT NULL,
    UNIQUE(modelo_id, anio, motor, cilindrada)
);

-- ============================================================================
-- 4. CATÁLOGO DE REPUESTOS E INSUMOS DE FAENA (HU-01, HU-05, HU-07)
-- ============================================================================
CREATE TABLE categorias (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) UNIQUE NOT NULL,
    descripcion TEXT,
    es_insumo_minero BOOLEAN DEFAULT FALSE
);

CREATE TABLE productos (
    id SERIAL PRIMARY KEY,
    codigo_interno VARCHAR(60) UNIQUE NOT NULL, -- SKU
    codigo_oem VARCHAR(80),
    nombre VARCHAR(180) NOT NULL,
    descripcion_tecnica TEXT,
    categoria_id INT REFERENCES categorias(id) ON DELETE SET NULL,
    marca_referencia VARCHAR(80) DEFAULT 'General',
    modelo_referencia VARCHAR(100) DEFAULT 'General',
    precio_referencia INT DEFAULT 0, -- Guardado SOLO para uso interno administrativo, JAMÁS expuesto en catálogo público (RF01)
    imagen_url TEXT,
    stock_actual INT NOT NULL DEFAULT 0 CHECK (stock_actual >= 0),
    es_agotado BOOLEAN GENERATED ALWAYS AS (stock_actual <= 0) STORED,
    es_insumo_faena BOOLEAN DEFAULT FALSE,
    estado_catalogo VARCHAR(30) DEFAULT 'PUBLICADO' 
        CHECK (estado_catalogo IN ('PENDIENTE', 'PUBLICADO', 'OCULTO')),
    ultima_sincronizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE producto_compatibilidad (
    producto_id INT NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    version_vehiculo_id INT NOT NULL REFERENCES versiones_vehiculo(id) ON DELETE CASCADE,
    notas_tecnicas VARCHAR(255),
    PRIMARY KEY (producto_id, version_vehiculo_id)
);

-- ============================================================================
-- 5. MÓDULO DE RESERVAS ASISTIDAS Y FOLIO CORRELATIVO (HU-03, HU-04)
-- ============================================================================
DROP SEQUENCE IF EXISTS seq_folio_reserva CASCADE;
DROP SEQUENCE IF EXISTS seq_folio_venta CASCADE;
CREATE SEQUENCE seq_folio_reserva START 1001;
CREATE SEQUENCE seq_folio_venta START 1;

CREATE TABLE reservas (
    id SERIAL PRIMARY KEY,
    folio VARCHAR(30) UNIQUE NOT NULL DEFAULT ('RES-' || nextval('seq_folio_reserva')),
    cliente_nombre VARCHAR(120) NOT NULL,
    cliente_telefono VARCHAR(30) NOT NULL,
    cliente_email VARCHAR(120) NOT NULL,
    cliente_rut_o_taller VARCHAR(100),
    nota TEXT,
    acepta_politica_datos BOOLEAN NOT NULL DEFAULT TRUE,
    estado VARCHAR(30) DEFAULT 'pendiente' 
        CHECK (estado IN ('pendiente', 'confirmada', 'entregada', 'rechazada', 'PENDIENTE', 'CONFIRMADA', 'RECHAZADA', 'CONCRETADA')),
    notificado_whatsapp BOOLEAN DEFAULT FALSE,
    notificado_email BOOLEAN DEFAULT FALSE,
    observaciones_vendedor TEXT,
    creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    actualizado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE reserva_detalles (
    id SERIAL PRIMARY KEY,
    reserva_id INT NOT NULL REFERENCES reservas(id) ON DELETE CASCADE,
    producto_id INT NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    cantidad INT NOT NULL DEFAULT 1 CHECK (cantidad > 0),
    vehiculo_referencia VARCHAR(200)
);

-- Ventas registradas en sucursal desde el panel admin (descuentan stock)
CREATE TABLE ventas (
    id SERIAL PRIMARY KEY,
    folio VARCHAR(30) UNIQUE NOT NULL DEFAULT ('VTA-' || LPAD(nextval('seq_folio_venta')::text, 5, '0')),
    producto_id INT REFERENCES productos(id) ON DELETE SET NULL,
    sku VARCHAR(60) NOT NULL,
    producto_nombre VARCHAR(180) NOT NULL,
    precio_unitario INT NOT NULL DEFAULT 0 CHECK (precio_unitario >= 0),
    cantidad INT NOT NULL CHECK (cantidad > 0),
    total INT NOT NULL DEFAULT 0,
    cliente VARCHAR(120),
    metodo_pago VARCHAR(40),
    nota TEXT,
    usuario_registro VARCHAR(60),
    creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 6. ANALÍTICA DE DEMANDA INSATISFECHA (BI - HU-06) Y SINCRONIZACIÓN (HU-05)
-- ============================================================================
CREATE TABLE metricas_demanda (
    id SERIAL PRIMARY KEY,
    tipo_evento VARCHAR(40) NOT NULL 
        CHECK (tipo_evento IN ('BUSQUEDA_SIN_RESULTADO', 'INTERACCION_AGOTADO', 'SOLICITUD_ESPECIAL')),
    termino_buscado VARCHAR(200),
    marca_consultada VARCHAR(80),
    modelo_consultado VARCHAR(100),
    anio_consultado INT,
    motor_consultado VARCHAR(80),
    producto_id INT REFERENCES productos(id) ON DELETE SET NULL,
    fecha_evento TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE logs_sincronizacion (
    id SERIAL PRIMARY KEY,
    fecha_inicio TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_procesados INT NOT NULL DEFAULT 0,
    total_agotados INT NOT NULL DEFAULT 0,
    nuevos_pendientes INT NOT NULL DEFAULT 0,
    estado VARCHAR(30) NOT NULL CHECK (estado IN ('EXITOSO', 'ERROR_VALIDACION', 'RECHAZADO')),
    mensaje_detalle TEXT
);

CREATE TABLE logs_auditoria (
    id SERIAL PRIMARY KEY,
    usuario_email VARCHAR(120),
    ruta_accedida VARCHAR(150) NOT NULL,
    metodo_http VARCHAR(10) NOT NULL,
    resultado VARCHAR(50) NOT NULL,
    ip_origen VARCHAR(50),
    fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- 7. ÍNDICES B-TREE COMPUESTOS PARA RENDIMIENTO <= 1,8s (<50ms en BD - RNF02)
-- ============================================================================
CREATE INDEX idx_modelos_marca ON modelos(marca_id);
CREATE INDEX idx_versiones_cascada ON versiones_vehiculo(modelo_id, anio, motor, cilindrada);
CREATE INDEX idx_productos_busqueda ON productos(categoria_id, estado_catalogo, es_agotado);
CREATE INDEX idx_productos_codigo ON productos(codigo_interno);
CREATE INDEX idx_compatibilidad_version ON producto_compatibilidad(version_vehiculo_id, producto_id);
CREATE INDEX idx_ventas_fecha ON ventas(creado_en DESC);
CREATE INDEX idx_metricas_tipo_fecha ON metricas_demanda(tipo_evento, fecha_evento DESC);

-- ============================================================================
-- 8. DATOS SEMILLA (SEED DATA) REALISTAS PARA MAYKEL REPUESTOS 2 (CALAMA)
-- ============================================================================

INSERT INTO roles (id, nombre, permisos) VALUES
(1, 'Superadministrador', '["dashboard", "catalogo", "reservas", "stock", "usuarios", "configuracion"]'::jsonb),
(2, 'Vendedor', '["dashboard", "catalogo", "reservas", "stock"]'::jsonb);
SELECT setval('roles_id_seq', 2);

INSERT INTO usuarios (usuario, nombre, email, password_hash, rol, rol_id) VALUES
('admin', 'Francisca Soto', 'francisca.soto@maykelrepuestos.cl', 'sha256$a1f3c9d2e8b7$ae62e2b693e64c0d8283b3d06e81b0ad5da71f506d3329a30d91d0eec24edf34', 'SUPERADMIN', 1),
('daniel', 'Daniel Collado', 'daniel.collado@maykelrepuestos.cl', 'sha256$5b8e2d4f7a1c$7201713a73be098e9e1c026b33f509467eb26f29cf2dca182c31c962be7aba91', 'SUPERADMIN', 1),
('vendedor', 'Maximiliano Carvajal', 'ventas@maykelrepuestos.cl', 'sha256$9c4d1e7b3f2a$66cf80bddb6c32eecb59c24b86d394004eb348cba7555281eb26a8925a0b520f', 'VENDEDOR', 2);
-- Contraseñas de demostración (cámbialas desde el panel): admin y daniel = maykel2026, vendedor = ventas2026.
-- Se guardan como hash SHA-256 con sal: sha256$<sal>$<hash>

INSERT INTO marcas (id, nombre) VALUES
(1, 'Great Wall'),
(2, 'Chery'),
(3, 'Maxus'),
(4, 'JAC'),
(5, 'Changan'),
(6, 'MG'),
(7, 'Haval'),
(8, 'Jetour');
SELECT setval('marcas_id_seq', 8);

INSERT INTO modelos (id, marca_id, nombre) VALUES
(1, 1, 'Poer'),
(2, 1, 'Wingle 5'),
(3, 1, 'Haval H6'),
(4, 2, 'Tiggo 2'),
(5, 2, 'Tiggo 3'),
(6, 3, 'T60'),
(7, 4, 'T8'),
(8, 5, 'Hunter');
SELECT setval('modelos_id_seq', 8);

INSERT INTO versiones_vehiculo (id, modelo_id, anio, motor, cilindrada) VALUES
(1, 1, 2022, '2.0 Turbo Diesel', '2000 cc'),
(2, 1, 2023, '2.0 Turbo Diesel', '2000 cc'),
(3, 2, 2020, '2.0 Diesel VGT', '2000 cc'),
(4, 3, 2021, '2.0 Turbo Gasolina', '2000 cc'),
(5, 4, 2021, '1.5 VVT Gasolina', '1500 cc'),
(6, 4, 2022, '1.5 VVT Gasolina', '1500 cc'),
(7, 6, 2022, '2.8 Turbo Diesel', '2800 cc'),
(8, 7, 2023, '2.0 CTI Diesel', '2000 cc');
SELECT setval('versiones_vehiculo_id_seq', 8);

INSERT INTO categorias (id, nombre, descripcion, es_insumo_minero) VALUES
(1, 'Frenos', 'Pastillas, discos, cálipers y sensores ABS', FALSE),
(2, 'Suspensión y Dirección', 'Amortiguadores, bandejas, terminales y rótulas', FALSE),
(3, 'Filtros y Mantención', 'Filtros de aceite, aire, petróleo y polen', FALSE),
(4, 'Motor y Distribución', 'Kits de distribución, bombas de agua, correas y tensores', FALSE),
(5, 'Insumos Mineros y Faena', 'Pértigas, balizas estroboscópicas, cuñas y equipamiento estándar minero', TRUE);
SELECT setval('categorias_id_seq', 5);

INSERT INTO productos (id, codigo_interno, codigo_oem, nombre, descripcion_tecnica, categoria_id, marca_referencia, modelo_referencia, imagen_url, stock_actual, es_insumo_faena, estado_catalogo) VALUES
(1, 'MR-GW-001', '3501110XKW09A', 'Pastillas de Freno Delanteras Cerámicas Great Wall Poer', 'Juego de 4 pastillas cerámicas de alta resistencia térmica, incluye sensor acústico de desgaste.', 1, 'Great Wall', 'Poer', NULL, 8, FALSE, 'PUBLICADO'),
(2, 'MR-GW-002', '1012100-ED01', 'Filtro de Aceite Original Great Wall 2.0 Diesel', 'Filtro blindado de alto flujo para motores 4D20M Turbo Diesel.', 3, 'Great Wall', 'Poer / Wingle 5', NULL, 15, FALSE, 'PUBLICADO'),
(3, 'MR-CH-001', 'J69-3501080', 'Pastillas de Freno Chery Tiggo 2', 'Compuesto semimetálico norma OEM para eje delantero.', 1, 'Chery', 'Tiggo 2', NULL, 0, FALSE, 'PUBLICADO'),
(4, 'MR-MX-001', 'C00049651', 'Amortiguador Delantero Reforzado Maxus T60', 'Amortiguador bitubo presurizado a gas para trabajo pesado en ruta y faena.', 2, 'Maxus', 'T60', NULL, 2, FALSE, 'PUBLICADO'),
(5, 'MR-FAENA-01', 'MIN-PERT-12F', 'Pértiga Minera 12 Pies con Resorte y Bandera LED 12V/24V', 'Fibra de vidrio certificada para faenas mineras en Calama, conector rápido pesado.', 5, 'Universal', 'Faena Minera', NULL, 12, TRUE, 'PUBLICADO'),
(6, 'MR-FAENA-02', 'MIN-BAL-AMB', 'Baliza Estroboscópica LED Ámbar Base Magnética/Fija', 'Homologada para camionetas de faena, 12V-24V multivoltaje IP67.', 5, 'Universal', 'Faena Minera', NULL, 0, TRUE, 'PUBLICADO');
UPDATE productos SET precio_referencia = CASE id
    WHEN 1 THEN 24990 WHEN 2 THEN 8990 WHEN 3 THEN 19990
    WHEN 4 THEN 54990 WHEN 5 THEN 89990 WHEN 6 THEN 34990 END;

-- Catálogo de ejemplo adicional (precios en CLP, solo visibles en el panel admin)
INSERT INTO productos (id, codigo_interno, codigo_oem, nombre, descripcion_tecnica, categoria_id, marca_referencia, modelo_referencia, precio_referencia, imagen_url, stock_actual, es_insumo_faena, estado_catalogo) VALUES
(7,  'MR-GW-003', '1109100XP64XA', 'Filtro de Aire Motor Great Wall Wingle 5', 'Elemento filtrante de alta retención para caminos con polvo.', 3, 'Great Wall', 'Wingle 5', 12990, NULL, 10, FALSE, 'PUBLICADO'),
(8,  'MR-GW-004', '1306100-ED01', 'Kit de Distribución Great Wall 2.0 Diesel', 'Incluye correa, tensor y polea guía para motor 4D20.', 4, 'Great Wall', 'Poer / Wingle 5', 119990, NULL, 3, FALSE, 'PUBLICADO'),
(9,  'MR-HV-001', '3501101XKZ16A', 'Disco de Freno Delantero Haval H6', 'Disco ventilado, se vende por unidad.', 1, 'Haval', 'H6', 39990, NULL, 6, FALSE, 'PUBLICADO'),
(10, 'MR-CH-002', 'T11-1109111', 'Filtro de Aire Chery Tiggo 3', 'Reemplazo directo del filtro original.', 3, 'Chery', 'Tiggo 3', 9990, NULL, 9, FALSE, 'PUBLICADO'),
(11, 'MR-CH-003', 'J69-2904020', 'Terminal de Dirección Chery Tiggo 2', 'Terminal exterior, lado izquierdo o derecho.', 2, 'Chery', 'Tiggo 2', 14990, NULL, 4, FALSE, 'PUBLICADO'),
(12, 'MR-MX-002', 'C00014682', 'Filtro de Petróleo Maxus T60 2.8', 'Separador de agua integrado.', 3, 'Maxus', 'T60', 16990, NULL, 12, FALSE, 'PUBLICADO'),
(13, 'MR-MX-003', 'C00048934', 'Bomba de Agua Maxus T60 2.8 Diesel', 'Con empaquetadura incluida.', 4, 'Maxus', 'T60', 74990, NULL, 1, FALSE, 'PUBLICADO'),
(14, 'MR-JC-001', '1109100U1910', 'Filtro de Aire JAC T8 2.0 CTI', 'Filtro de panel para motor diésel 2.0.', 3, 'JAC', 'T8', 13990, NULL, 7, FALSE, 'PUBLICADO'),
(15, 'MR-JC-002', '2904100P3010', 'Bandeja de Suspensión Inferior JAC T8', 'Incluye rótula y bujes.', 2, 'JAC', 'T8', 89990, NULL, 2, FALSE, 'PUBLICADO'),
(16, 'MR-CG-001', 'S101028-0300', 'Pastillas de Freno Delanteras Changan Hunter', 'Compuesto cerámico de bajo polvo.', 1, 'Changan', 'Hunter', 27990, NULL, 5, FALSE, 'PUBLICADO'),
(17, 'MR-MG-001', '10105969', 'Filtro de Aceite MG ZS 1.5', 'Filtro roscado con válvula antirretorno.', 3, 'MG', 'ZS', 7990, NULL, 20, FALSE, 'PUBLICADO'),
(18, 'MR-JT-001', 'F01-3501080', 'Pastillas de Freno Jetour X70', 'Juego eje delantero.', 1, 'Jetour', 'X70', 29990, NULL, 0, FALSE, 'PUBLICADO'),
(19, 'MR-FAENA-03', 'MIN-CUN-PAR', 'Par de Cuñas de Seguridad para Camioneta', 'Poliuretano de alta resistencia, color amarillo.', 5, 'Universal', 'Faena Minera', 24990, NULL, 15, TRUE, 'PUBLICADO'),
(20, 'MR-FAENA-04', 'MIN-EXT-2KG', 'Extintor PQS 2 kg con Soporte Vehicular', 'Certificado para vehículos de faena.', 5, 'Universal', 'Faena Minera', 32990, NULL, 8, TRUE, 'PUBLICADO');
SELECT setval('productos_id_seq', 20);

INSERT INTO producto_compatibilidad (producto_id, version_vehiculo_id, notas_tecnicas) VALUES
(1, 1, 'Aplica versiones 4x2 y 4x4'),
(1, 2, 'Aplica versiones 4x2 y 4x4'),
(2, 1, 'Motor 2.0 Diesel'),
(2, 2, 'Motor 2.0 Diesel'),
(2, 3, 'Compatible también con Wingle 5 2.0 Diesel'),
(3, 5, 'Todas las versiones Tiggo 2 1.5'),
(3, 6, 'Todas las versiones Tiggo 2 1.5'),
(4, 7, 'Suspensión delantera estándar y heavy duty');

INSERT INTO metricas_demanda (tipo_evento, termino_buscado, marca_consultada, modelo_consultado, anio_consultado, producto_id) VALUES
('INTERACCION_AGOTADO', 'Pastillas de Freno Chery Tiggo 2', 'Chery', 'Tiggo 2', 2021, 3),
('INTERACCION_AGOTADO', 'Pastillas de Freno Chery Tiggo 2', 'Chery', 'Tiggo 2', 2022, 3),
('INTERACCION_AGOTADO', 'Baliza Estroboscópica LED Ámbar', 'Universal', 'Faena Minera', NULL, 6),
('BUSQUEDA_SIN_RESULTADO', 'Kit embrague JAC T8', 'JAC', 'T8', 2023, NULL),
('BUSQUEDA_SIN_RESULTADO', 'Bomba de agua Changan Hunter', 'Changan', 'Hunter', 2022, NULL),
('BUSQUEDA_SIN_RESULTADO', 'Foco delantero Haval H6', 'Great Wall', 'Haval H6', 2021, NULL);

INSERT INTO logs_sincronizacion (total_procesados, total_agotados, nuevos_pendientes, estado, mensaje_detalle)
VALUES (6, 2, 0, 'EXITOSO', 'Carga inicial de inventario Maykel Repuestos 2');