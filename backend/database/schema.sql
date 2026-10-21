-- ============================================================================
-- PROYECTO DE TÍTULO: MAYKEL REPUESTOS 2 (CALAMA)
-- Script DDL + Seed Data Unificado (3NF + Compatibilidad Frontend/Admin)
-- ============================================================================

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
    password_hash VARCHAR(255) NOT NULL,        -- Soporta validación y hash
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
CREATE SEQUENCE IF NOT EXISTS seq_folio_reserva START 1001;

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
CREATE INDEX idx_metricas_tipo_fecha ON metricas_demanda(tipo_evento, fecha_evento DESC);

-- ============================================================================
-- 8. DATOS SEMILLA (SEED DATA) REALISTAS PARA MAYKEL REPUESTOS 2 (CALAMA)
-- ============================================================================

INSERT INTO roles (id, nombre, permisos) VALUES
(1, 'Superadministrador', '["dashboard", "catalogo", "reservas", "stock", "usuarios", "configuracion"]'::jsonb),
(2, 'Vendedor', '["dashboard", "catalogo", "reservas", "stock"]'::jsonb);
SELECT setval('roles_id_seq', 2);

INSERT INTO usuarios (usuario, nombre, email, password_hash, rol, rol_id) VALUES
('admin', 'Francisca Soto', 'francisca.soto@maykelrepuestos.cl', 'maykel2026', 'SUPERADMIN', 1),
('daniel', 'Daniel Collado', 'daniel.collado@maykelrepuestos.cl', 'maykel2026', 'SUPERADMIN', 1),
('vendedor', 'Maximiliano Carvajal', 'ventas@maykelrepuestos.cl', 'ventas2026', 'VENDEDOR', 2);

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
(1, 'MR-GW-001', '3501110XKW09A', 'Pastillas de Freno Delanteras Cerámicas Great Wall Poer', 'Juego de 4 pastillas cerámicas de alta resistencia térmica, incluye sensor acústico de desgaste.', 1, 'Great Wall', 'Poer', 'assets/images/logo.jpg', 8, FALSE, 'PUBLICADO'),
(2, 'MR-GW-002', '1012100-ED01', 'Filtro de Aceite Original Great Wall 2.0 Diesel', 'Filtro blindado de alto flujo para motores 4D20M Turbo Diesel.', 3, 'Great Wall', 'Poer / Wingle 5', 'assets/images/logo.jpg', 15, FALSE, 'PUBLICADO'),
(3, 'MR-CH-001', 'J69-3501080', 'Pastillas de Freno Chery Tiggo 2', 'Compuesto semimetálico norma OEM para eje delantero.', 1, 'Chery', 'Tiggo 2', 'assets/images/logo.jpg', 0, FALSE, 'PUBLICADO'),
(4, 'MR-MX-001', 'C00049651', 'Amortiguador Delantero Reforzado Maxus T60', 'Amortiguador bitubo presurizado a gas para trabajo pesado en ruta y faena.', 2, 'Maxus', 'T60', 'assets/images/logo.jpg', 2, FALSE, 'PUBLICADO'),
(5, 'MR-FAENA-01', 'MIN-PERT-12F', 'Pértiga Minera 12 Pies con Resorte y Bandera LED 12V/24V', 'Fibra de vidrio certificada para faenas mineras en Calama, conector rápido pesado.', 5, 'Universal', 'Faena Minera', 'assets/images/logo.jpg', 12, TRUE, 'PUBLICADO'),
(6, 'MR-FAENA-02', 'MIN-BAL-AMB', 'Baliza Estroboscópica LED Ámbar Base Magnética/Fija', 'Homologada para camionetas de faena, 12V-24V multivoltaje IP67.', 5, 'Universal', 'Faena Minera', 'assets/images/logo.jpg', 0, TRUE, 'PUBLICADO');
SELECT setval('productos_id_seq', 6);

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