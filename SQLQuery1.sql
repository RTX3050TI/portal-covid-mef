
-- ====================================================================================
-- OPCIÓN PARA IMPORTAR (BULK INSERT) MEJORADA
-- ====================================================================================

-- 2. IMPORTAR LOS DATOS (¡RECUERDA CAMBIAR LA RUTA DEL ARCHIVO ABAJO!)
BULK INSERT Ejecucion_Presupuestal
FROM 'C:\Users\pauca\Downloads\open data\2021-Gasto-COVID-19.csv'
WITH (
    FORMAT = 'CSV',          
    FIRSTROW = 2,            
    FIELDTERMINATOR = ',',   
    ROWTERMINATOR = '\n',    
    CODEPAGE = '65001',      
    TABLOCK,
    MAXERRORS = 100, -- Permitirá hasta 100 filas con errores sin detener la carga
    ERRORFILE = 'C:\Users\pauca\Downloads\open data\errores_carga.csv' -- Guardará las filas malas aquí
);
GO

SELECT  * FROM Gasto_COVID_2021; -- (O el nombre que le hayas puesto a tu tabla)
go
SELECT COUNT(*) 
FROM Gasto_COVID_2021;
go
go
SELECT
    COLUMN_NAME AS Columna,
    DATA_TYPE AS TipoDato,
    CHARACTER_MAXIMUM_LENGTH AS Longitud,
    IS_NULLABLE AS PermiteNulos
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'Gasto_COVID_2021'
ORDER BY ORDINAL_POSITION;
-- ====================================================================================
-- PASO 1: ELIMINAR TABLAS SI EXISTEN (Para evitar errores si corres el script varias veces)
-- ====================================================================================
IF OBJECT_ID('Hechos_Ejecucion', 'U') IS NOT NULL DROP TABLE Hechos_Ejecucion;
IF OBJECT_ID('Dim_Ejecutora', 'U') IS NOT NULL DROP TABLE Dim_Ejecutora;
IF OBJECT_ID('Dim_Pliego', 'U') IS NOT NULL DROP TABLE Dim_Pliego;
IF OBJECT_ID('Dim_Sector', 'U') IS NOT NULL DROP TABLE Dim_Sector;
IF OBJECT_ID('Dim_Nivel_Gobierno', 'U') IS NOT NULL DROP TABLE Dim_Nivel_Gobierno;
IF OBJECT_ID('Dim_Distrito', 'U') IS NOT NULL DROP TABLE Dim_Distrito;
IF OBJECT_ID('Dim_Provincia', 'U') IS NOT NULL DROP TABLE Dim_Provincia;
IF OBJECT_ID('Dim_Departamento', 'U') IS NOT NULL DROP TABLE Dim_Departamento;
IF OBJECT_ID('Dim_Financiamiento', 'U') IS NOT NULL DROP TABLE Dim_Financiamiento;
IF OBJECT_ID('Dim_Clasificador_Gasto', 'U') IS NOT NULL DROP TABLE Dim_Clasificador_Gasto;
GO

-- ====================================================================================
-- PASO 2: CREAR TABLAS ALTAMENTE NORMALIZADAS (TERCERA FORMA NORMAL / SNOWFLAKE)
-- ====================================================================================

------------------------- A. JERARQUÍA INSTITUCIONAL -------------------------
CREATE TABLE Dim_Nivel_Gobierno (
    COD_NIVEL_GOBIERNO VARCHAR(50) PRIMARY KEY,
    NIVEL_GOBIERNO_NOMBRE VARCHAR(MAX)
);

CREATE TABLE Dim_Sector (
    COD_SECTOR VARCHAR(50) PRIMARY KEY, -- Clave compuesta (Nivel + Sector) para evitar duplicados
    COD_NIVEL_GOBIERNO VARCHAR(50) FOREIGN KEY REFERENCES Dim_Nivel_Gobierno(COD_NIVEL_GOBIERNO),
    SECTOR_NOMBRE VARCHAR(MAX)
);

CREATE TABLE Dim_Pliego (
    COD_PLIEGO VARCHAR(100) PRIMARY KEY, -- Clave compuesta (Nivel + Sector + Pliego)
    COD_SECTOR VARCHAR(50) FOREIGN KEY REFERENCES Dim_Sector(COD_SECTOR),
    PLIEGO_NOMBRE VARCHAR(MAX)
);

CREATE TABLE Dim_Ejecutora (
    SEC_EJEC VARCHAR(50) PRIMARY KEY, -- SEC_EJEC ya es un código único por defecto en el MEF
    COD_PLIEGO VARCHAR(100) FOREIGN KEY REFERENCES Dim_Pliego(COD_PLIEGO),
    EJECUTORA VARCHAR(50),
    EJECUTORA_NOMBRE VARCHAR(MAX)
);

------------------------- B. JERARQUÍA GEOGRÁFICA (UBIGEO) -------------------------
CREATE TABLE Dim_Departamento (
    COD_DEPARTAMENTO VARCHAR(50) PRIMARY KEY,
    DEPARTAMENTO_NOMBRE VARCHAR(MAX)
);

CREATE TABLE Dim_Provincia (
    COD_PROVINCIA VARCHAR(50) PRIMARY KEY, -- Dep + Prov
    COD_DEPARTAMENTO VARCHAR(50) FOREIGN KEY REFERENCES Dim_Departamento(COD_DEPARTAMENTO),
    PROVINCIA_NOMBRE VARCHAR(MAX)
);

CREATE TABLE Dim_Distrito (
    COD_UBIGEO VARCHAR(50) PRIMARY KEY, -- Dep + Prov + Dist
    COD_PROVINCIA VARCHAR(50) FOREIGN KEY REFERENCES Dim_Provincia(COD_PROVINCIA),
    DISTRITO_NOMBRE VARCHAR(MAX)
);

------------------------- C. OTRAS DIMENSIONES -------------------------
CREATE TABLE Dim_Financiamiento (
    ID_FINANCIAMIENTO INT IDENTITY(1,1) PRIMARY KEY,
    FUENTE_FINANCIAMIENTO VARCHAR(50),
    FUENTE_FINANCIAMIENTO_NOMBRE VARCHAR(MAX),
    RUBRO VARCHAR(50),
    RUBRO_NOMBRE VARCHAR(MAX),
    TIPO_RECURSO VARCHAR(50),
    TIPO_RECURSO_NOMBRE VARCHAR(MAX)
);

CREATE TABLE Dim_Clasificador_Gasto (
    ID_CLASIFICADOR INT IDENTITY(1,1) PRIMARY KEY,
    CATEGORIA_GASTO VARCHAR(50),
    CATEGORIA_GASTO_NOMBRE VARCHAR(MAX),
    TIPO_TRANSACCION VARCHAR(50),
    GENERICA VARCHAR(50),
    GENERICA_NOMBRE VARCHAR(MAX),
    SUBGENERICA VARCHAR(50),
    SUBGENERICA_NOMBRE VARCHAR(MAX),
    SUBGENERICA_DET VARCHAR(50),
    SUBGENERICA_DET_NOMBRE VARCHAR(MAX),
    ESPECIFICA VARCHAR(50),
    ESPECIFICA_NOMBRE VARCHAR(MAX),
    ESPECIFICA_DET VARCHAR(50),
    ESPECIFICA_DET_NOMBRE VARCHAR(MAX)
);

------------------------- D. TABLA DE HECHOS -------------------------
CREATE TABLE Hechos_Ejecucion (
    ANO_EJE INT,
    MES_EJE INT,
    SEC_EJEC VARCHAR(50) FOREIGN KEY REFERENCES Dim_Ejecutora(SEC_EJEC), -- Se enlaza al nivel más bajo
    COD_UBIGEO VARCHAR(50) FOREIGN KEY REFERENCES Dim_Distrito(COD_UBIGEO), -- Se enlaza al nivel más bajo
    ID_FINANCIAMIENTO INT FOREIGN KEY REFERENCES Dim_Financiamiento(ID_FINANCIAMIENTO),
    ID_CLASIFICADOR INT FOREIGN KEY REFERENCES Dim_Clasificador_Gasto(ID_CLASIFICADOR),
    
    MONTO_PIA DECIMAL(18,2),
    MONTO_PIM DECIMAL(18,2),
    MONTO_CERTIFICADO DECIMAL(18,2),
    MONTO_COMPROMETIDO_ANUAL DECIMAL(18,2),
    MONTO_COMPROMETIDO DECIMAL(18,2),
    MONTO_DEVENGADO DECIMAL(18,2),
    MONTO_GIRADO DECIMAL(18,2)
);
GO

-- ====================================================================================
-- PASO 3: POBLAR DATOS RESPETANDO LA JERARQUÍA Y AGRUPANDO PARA EVITAR DUPLICADOS
-- ====================================================================================

-- 1. Jerarquía Geográfica
PRINT 'Llenando Departamentos...';
INSERT INTO Dim_Departamento (COD_DEPARTAMENTO, DEPARTAMENTO_NOMBRE)
SELECT 
    CAST(DEPARTAMENTO_EJECUTORA AS VARCHAR(50)), 
    MAX(DEPARTAMENTO_EJECUTORA_NOMBRE) -- Toma el primer nombre válido para evitar inconsistencias
FROM Gasto_COVID_2021 
WHERE DEPARTAMENTO_EJECUTORA IS NOT NULL
GROUP BY CAST(DEPARTAMENTO_EJECUTORA AS VARCHAR(50));

PRINT 'Llenando Provincias...';
INSERT INTO Dim_Provincia (COD_PROVINCIA, COD_DEPARTAMENTO, PROVINCIA_NOMBRE)
SELECT 
    (CAST(DEPARTAMENTO_EJECUTORA AS VARCHAR(50)) + CAST(PROVINCIA_EJECUTORA AS VARCHAR(50))), 
    MAX(CAST(DEPARTAMENTO_EJECUTORA AS VARCHAR(50))), 
    MAX(PROVINCIA_EJECUTORA_NOMBRE) 
FROM Gasto_COVID_2021 
WHERE PROVINCIA_EJECUTORA IS NOT NULL
GROUP BY (CAST(DEPARTAMENTO_EJECUTORA AS VARCHAR(50)) + CAST(PROVINCIA_EJECUTORA AS VARCHAR(50)));

PRINT 'Llenando Distritos...';
INSERT INTO Dim_Distrito (COD_UBIGEO, COD_PROVINCIA, DISTRITO_NOMBRE)
SELECT 
    (CAST(DEPARTAMENTO_EJECUTORA AS VARCHAR(50)) + CAST(PROVINCIA_EJECUTORA AS VARCHAR(50)) + CAST(DISTRITO_EJECUTORA AS VARCHAR(50))), 
    MAX((CAST(DEPARTAMENTO_EJECUTORA AS VARCHAR(50)) + CAST(PROVINCIA_EJECUTORA AS VARCHAR(50)))), 
    MAX(DISTRITO_EJECUTORA_NOMBRE) 
FROM Gasto_COVID_2021 
WHERE DISTRITO_EJECUTORA IS NOT NULL
GROUP BY (CAST(DEPARTAMENTO_EJECUTORA AS VARCHAR(50)) + CAST(PROVINCIA_EJECUTORA AS VARCHAR(50)) + CAST(DISTRITO_EJECUTORA AS VARCHAR(50)));

-- 2. Jerarquía Institucional
PRINT 'Llenando Niveles de Gobierno...';
INSERT INTO Dim_Nivel_Gobierno (COD_NIVEL_GOBIERNO, NIVEL_GOBIERNO_NOMBRE)
SELECT 
    CAST(NIVEL_GOBIERNO AS VARCHAR(50)), 
    MAX(NIVEL_GOBIERNO_NOMBRE) 
FROM Gasto_COVID_2021 
WHERE NIVEL_GOBIERNO IS NOT NULL
GROUP BY CAST(NIVEL_GOBIERNO AS VARCHAR(50));

PRINT 'Llenando Sectores...';
INSERT INTO Dim_Sector (COD_SECTOR, COD_NIVEL_GOBIERNO, SECTOR_NOMBRE)
SELECT 
    (CAST(NIVEL_GOBIERNO AS VARCHAR(50)) + '-' + CAST(SECTOR AS VARCHAR(50))), 
    MAX(CAST(NIVEL_GOBIERNO AS VARCHAR(50))), 
    MAX(SECTOR_NOMBRE) 
FROM Gasto_COVID_2021 
WHERE SECTOR IS NOT NULL
GROUP BY (CAST(NIVEL_GOBIERNO AS VARCHAR(50)) + '-' + CAST(SECTOR AS VARCHAR(50)));

PRINT 'Llenando Pliegos...';
INSERT INTO Dim_Pliego (COD_PLIEGO, COD_SECTOR, PLIEGO_NOMBRE)
SELECT 
    (CAST(NIVEL_GOBIERNO AS VARCHAR(50)) + '-' + CAST(SECTOR AS VARCHAR(50)) + '-' + CAST(PLIEGO AS VARCHAR(50))), 
    MAX((CAST(NIVEL_GOBIERNO AS VARCHAR(50)) + '-' + CAST(SECTOR AS VARCHAR(50)))), 
    MAX(PLIEGO_NOMBRE) 
FROM Gasto_COVID_2021 
WHERE PLIEGO IS NOT NULL
GROUP BY (CAST(NIVEL_GOBIERNO AS VARCHAR(50)) + '-' + CAST(SECTOR AS VARCHAR(50)) + '-' + CAST(PLIEGO AS VARCHAR(50)));

PRINT 'Llenando Ejecutoras...';
INSERT INTO Dim_Ejecutora (SEC_EJEC, COD_PLIEGO, EJECUTORA, EJECUTORA_NOMBRE)
SELECT 
    CAST(SEC_EJEC AS VARCHAR(50)), 
    MAX((CAST(NIVEL_GOBIERNO AS VARCHAR(50)) + '-' + CAST(SECTOR AS VARCHAR(50)) + '-' + CAST(PLIEGO AS VARCHAR(50)))), 
    MAX(CAST(EJECUTORA AS VARCHAR(50))), 
    MAX(EJECUTORA_NOMBRE) 
FROM Gasto_COVID_2021 
WHERE SEC_EJEC IS NOT NULL
GROUP BY CAST(SEC_EJEC AS VARCHAR(50));

-- 3. Dimensiones Planas
PRINT 'Llenando Financiamiento y Clasificador...';
INSERT INTO Dim_Financiamiento (FUENTE_FINANCIAMIENTO, FUENTE_FINANCIAMIENTO_NOMBRE, RUBRO, RUBRO_NOMBRE, TIPO_RECURSO, TIPO_RECURSO_NOMBRE)
SELECT DISTINCT CAST(FUENTE_FINANCIAMIENTO AS VARCHAR(50)), FUENTE_FINANCIAMIENTO_NOMBRE, CAST(RUBRO AS VARCHAR(50)), RUBRO_NOMBRE, CAST(TIPO_RECURSO AS VARCHAR(50)), TIPO_RECURSO_NOMBRE
FROM Gasto_COVID_2021;

INSERT INTO Dim_Clasificador_Gasto (CATEGORIA_GASTO, CATEGORIA_GASTO_NOMBRE, TIPO_TRANSACCION, GENERICA, GENERICA_NOMBRE, SUBGENERICA, SUBGENERICA_NOMBRE, SUBGENERICA_DET, SUBGENERICA_DET_NOMBRE, ESPECIFICA, ESPECIFICA_NOMBRE, ESPECIFICA_DET, ESPECIFICA_DET_NOMBRE)
SELECT DISTINCT CAST(CATEGORIA_GASTO AS VARCHAR(50)), CATEGORIA_GASTO_NOMBRE, CAST(TIPO_TRANSACCION AS VARCHAR(50)), CAST(GENERICA AS VARCHAR(50)), GENERICA_NOMBRE, CAST(SUBGENERICA AS VARCHAR(50)), SUBGENERICA_NOMBRE, CAST(SUBGENERICA_DET AS VARCHAR(50)), SUBGENERICA_DET_NOMBRE, CAST(ESPECIFICA AS VARCHAR(50)), ESPECIFICA_NOMBRE, CAST(ESPECIFICA_DET AS VARCHAR(50)), ESPECIFICA_DET_NOMBRE
FROM Gasto_COVID_2021;

-- 4. Insertar en Tabla de Hechos
PRINT 'Llenando Hechos_Ejecucion (Esto toma unos segundos)...';
INSERT INTO Hechos_Ejecucion (ANO_EJE, MES_EJE, SEC_EJEC, COD_UBIGEO, ID_FINANCIAMIENTO, ID_CLASIFICADOR, MONTO_PIA, MONTO_PIM, MONTO_CERTIFICADO, MONTO_COMPROMETIDO_ANUAL, MONTO_COMPROMETIDO, MONTO_DEVENGADO, MONTO_GIRADO)
SELECT 
    EP.ANO_EJE, 
    EP.MES_EJE, 
    CAST(EP.SEC_EJEC AS VARCHAR(50)), 
    (CAST(EP.DEPARTAMENTO_EJECUTORA AS VARCHAR(50)) + CAST(EP.PROVINCIA_EJECUTORA AS VARCHAR(50)) + CAST(EP.DISTRITO_EJECUTORA AS VARCHAR(50))),
    F.ID_FINANCIAMIENTO,
    C.ID_CLASIFICADOR,
    CAST(EP.MONTO_PIA AS DECIMAL(18,2)), CAST(EP.MONTO_PIM AS DECIMAL(18,2)), CAST(EP.MONTO_CERTIFICADO AS DECIMAL(18,2)), CAST(EP.MONTO_COMPROMETIDO_ANUAL AS DECIMAL(18,2)), CAST(EP.MONTO_COMPROMETIDO AS DECIMAL(18,2)), CAST(EP.MONTO_DEVENGADO AS DECIMAL(18,2)), CAST(EP.MONTO_GIRADO AS DECIMAL(18,2))
FROM Gasto_COVID_2021 EP
LEFT JOIN Dim_Financiamiento F ON ISNULL(CAST(EP.FUENTE_FINANCIAMIENTO AS VARCHAR(50)), '') = ISNULL(F.FUENTE_FINANCIAMIENTO, '') AND ISNULL(CAST(EP.RUBRO AS VARCHAR(50)), '') = ISNULL(F.RUBRO, '') AND ISNULL(CAST(EP.TIPO_RECURSO AS VARCHAR(50)), '') = ISNULL(F.TIPO_RECURSO, '')
LEFT JOIN Dim_Clasificador_Gasto C ON ISNULL(CAST(EP.CATEGORIA_GASTO AS VARCHAR(50)), '') = ISNULL(C.CATEGORIA_GASTO, '') AND ISNULL(CAST(EP.TIPO_TRANSACCION AS VARCHAR(50)), '') = ISNULL(C.TIPO_TRANSACCION, '') AND ISNULL(CAST(EP.GENERICA AS VARCHAR(50)), '') = ISNULL(C.GENERICA, '') AND ISNULL(CAST(EP.SUBGENERICA AS VARCHAR(50)), '') = ISNULL(C.SUBGENERICA, '') AND ISNULL(CAST(EP.ESPECIFICA_DET AS VARCHAR(50)), '') = ISNULL(C.ESPECIFICA_DET, '');

PRINT '¡BASE DE DATOS SUPER NORMALIZADA CON ÉXITO!';
GO

-- Jerarquía Institucional
SELECT TOP 100 * FROM Dim_Nivel_Gobierno;
SELECT TOP 100 * FROM Dim_Sector;
SELECT TOP 100 * FROM Dim_Pliego;
SELECT TOP 100 * FROM Dim_Ejecutora;

-- Jerarquía Geográfica
SELECT TOP 100 * FROM Dim_Departamento;
SELECT TOP 100 * FROM Dim_Provincia;
SELECT TOP 100 * FROM Dim_Distrito;

-- Dimensiones Planas
SELECT TOP 100 * FROM Dim_Financiamiento;
SELECT TOP 100 * FROM Dim_Clasificador_Gasto;

-- Tabla Principal (Hechos)
SELECT TOP 100 * FROM Hechos_Ejecucion;
GO

IF OBJECT_ID('vw_Gasto_General', 'V') IS NOT NULL DROP VIEW vw_Gasto_General;
GO

CREATE VIEW vw_Gasto_General AS
SELECT 
    H.ANO_EJE,
    H.MES_EJE,
    
    -- 1. Datos Institucionales (Desenrollando la jerarquía)
    NG.COD_NIVEL_GOBIERNO AS NIVEL_GOBIERNO,
    NG.NIVEL_GOBIERNO_NOMBRE,
    S.COD_SECTOR AS SECTOR_CODIGO_COMPUESTO,
    S.SECTOR_NOMBRE,
    P.COD_PLIEGO AS PLIEGO_CODIGO_COMPUESTO,
    P.PLIEGO_NOMBRE,
    E.SEC_EJEC,
    E.EJECUTORA,
    E.EJECUTORA_NOMBRE,

    -- 2. Datos Geográficos (Desenrollando el Ubigeo)
    D.COD_DEPARTAMENTO AS DEPARTAMENTO,
    D.DEPARTAMENTO_NOMBRE,
    PR.COD_PROVINCIA AS PROVINCIA_CODIGO,
    PR.PROVINCIA_NOMBRE,
    DI.COD_UBIGEO AS DISTRITO_CODIGO,
    DI.DISTRITO_NOMBRE,

    -- 3. Datos de Financiamiento
    F.FUENTE_FINANCIAMIENTO,
    F.FUENTE_FINANCIAMIENTO_NOMBRE,
    F.RUBRO,
    F.RUBRO_NOMBRE,
    F.TIPO_RECURSO,
    F.TIPO_RECURSO_NOMBRE,

    -- 4. Datos del Clasificador de Gasto
    CG.CATEGORIA_GASTO,
    CG.CATEGORIA_GASTO_NOMBRE,
    CG.TIPO_TRANSACCION,
    CG.GENERICA,
    CG.GENERICA_NOMBRE,
    CG.SUBGENERICA,
    CG.SUBGENERICA_NOMBRE,
    CG.SUBGENERICA_DET,
    CG.SUBGENERICA_DET_NOMBRE,
    CG.ESPECIFICA,
    CG.ESPECIFICA_NOMBRE,
    CG.ESPECIFICA_DET,
    CG.ESPECIFICA_DET_NOMBRE,

    -- 5. Montos (Desde la Tabla de Hechos)
    H.MONTO_PIA,
    H.MONTO_PIM,
    H.MONTO_CERTIFICADO,
    H.MONTO_COMPROMETIDO_ANUAL,
    H.MONTO_COMPROMETIDO,
    H.MONTO_DEVENGADO,
    H.MONTO_GIRADO

FROM Hechos_Ejecucion H

-- Uniendo la parte Geográfica (De abajo hacia arriba)
INNER JOIN Dim_Distrito DI ON H.COD_UBIGEO = DI.COD_UBIGEO
INNER JOIN Dim_Provincia PR ON DI.COD_PROVINCIA = PR.COD_PROVINCIA
INNER JOIN Dim_Departamento D ON PR.COD_DEPARTAMENTO = D.COD_DEPARTAMENTO

-- Uniendo la parte Institucional (De abajo hacia arriba)
INNER JOIN Dim_Ejecutora E ON H.SEC_EJEC = E.SEC_EJEC
INNER JOIN Dim_Pliego P ON E.COD_PLIEGO = P.COD_PLIEGO
INNER JOIN Dim_Sector S ON P.COD_SECTOR = S.COD_SECTOR
INNER JOIN Dim_Nivel_Gobierno NG ON S.COD_NIVEL_GOBIERNO = NG.COD_NIVEL_GOBIERNO

-- Uniendo Dimensiones Planas
INNER JOIN Dim_Financiamiento F ON H.ID_FINANCIAMIENTO = F.ID_FINANCIAMIENTO
INNER JOIN Dim_Clasificador_Gasto CG ON H.ID_CLASIFICADOR = CG.ID_CLASIFICADOR;
GO


select * from vw_Gasto_General;

-- ====================================================================================
-- CORRECCIÓN DEL PRODUCTO CARTESIANO (FILAS DUPLICADAS)
-- Este script limpia las tablas afectadas y las vuelve a llenar garantizando códigos únicos.
-- ====================================================================================

-- 1. Vaciar la tabla de hechos (elimina los registros inflados)
DELETE FROM Hechos_Ejecucion;

-- 2. Vaciar las dos dimensiones con problemas y reiniciar sus contadores (IDs)
DELETE FROM Dim_Financiamiento;
DBCC CHECKIDENT ('Dim_Financiamiento', RESEED, 0);

DELETE FROM Dim_Clasificador_Gasto;
DBCC CHECKIDENT ('Dim_Clasificador_Gasto', RESEED, 0);
GO

-- 3. Volver a llenar Dim_Financiamiento usando GROUP BY y MAX (Garantiza 1 sola fila por código)
PRINT 'Corrigiendo Dim_Financiamiento...';
INSERT INTO Dim_Financiamiento (FUENTE_FINANCIAMIENTO, FUENTE_FINANCIAMIENTO_NOMBRE, RUBRO, RUBRO_NOMBRE, TIPO_RECURSO, TIPO_RECURSO_NOMBRE)
SELECT 
    CAST(FUENTE_FINANCIAMIENTO AS VARCHAR(50)), MAX(FUENTE_FINANCIAMIENTO_NOMBRE), 
    CAST(RUBRO AS VARCHAR(50)), MAX(RUBRO_NOMBRE), 
    CAST(TIPO_RECURSO AS VARCHAR(50)), MAX(TIPO_RECURSO_NOMBRE)
FROM Gasto_COVID_2021
GROUP BY 
    CAST(FUENTE_FINANCIAMIENTO AS VARCHAR(50)), 
    CAST(RUBRO AS VARCHAR(50)), 
    CAST(TIPO_RECURSO AS VARCHAR(50));
GO

-- 4. Volver a llenar Dim_Clasificador_Gasto usando GROUP BY y MAX
PRINT 'Corrigiendo Dim_Clasificador_Gasto...';
INSERT INTO Dim_Clasificador_Gasto (CATEGORIA_GASTO, CATEGORIA_GASTO_NOMBRE, TIPO_TRANSACCION, GENERICA, GENERICA_NOMBRE, SUBGENERICA, SUBGENERICA_NOMBRE, SUBGENERICA_DET, SUBGENERICA_DET_NOMBRE, ESPECIFICA, ESPECIFICA_NOMBRE, ESPECIFICA_DET, ESPECIFICA_DET_NOMBRE)
SELECT 
    CAST(CATEGORIA_GASTO AS VARCHAR(50)), MAX(CATEGORIA_GASTO_NOMBRE), 
    CAST(TIPO_TRANSACCION AS VARCHAR(50)), 
    CAST(GENERICA AS VARCHAR(50)), MAX(GENERICA_NOMBRE), 
    CAST(SUBGENERICA AS VARCHAR(50)), MAX(SUBGENERICA_NOMBRE), 
    CAST(SUBGENERICA_DET AS VARCHAR(50)), MAX(SUBGENERICA_DET_NOMBRE), 
    CAST(ESPECIFICA AS VARCHAR(50)), MAX(ESPECIFICA_NOMBRE), 
    CAST(ESPECIFICA_DET AS VARCHAR(50)), MAX(ESPECIFICA_DET_NOMBRE)
FROM Gasto_COVID_2021
GROUP BY 
    CAST(CATEGORIA_GASTO AS VARCHAR(50)), 
    CAST(TIPO_TRANSACCION AS VARCHAR(50)), 
    CAST(GENERICA AS VARCHAR(50)), 
    CAST(SUBGENERICA AS VARCHAR(50)), 
    CAST(SUBGENERICA_DET AS VARCHAR(50)), 
    CAST(ESPECIFICA AS VARCHAR(50)), 
    CAST(ESPECIFICA_DET AS VARCHAR(50));
GO

-- 5. Llenar Hechos_Ejecucion nuevamente CON TODOS LOS FILTROS COMPLETOS
PRINT 'Llenando Hechos_Ejecucion garantizando las 135,007 filas originales...';
INSERT INTO Hechos_Ejecucion (ANO_EJE, MES_EJE, SEC_EJEC, COD_UBIGEO, ID_FINANCIAMIENTO, ID_CLASIFICADOR, MONTO_PIA, MONTO_PIM, MONTO_CERTIFICADO, MONTO_COMPROMETIDO_ANUAL, MONTO_COMPROMETIDO, MONTO_DEVENGADO, MONTO_GIRADO)
SELECT 
    EP.ANO_EJE, 
    EP.MES_EJE, 
    CAST(EP.SEC_EJEC AS VARCHAR(50)), 
    (CAST(EP.DEPARTAMENTO_EJECUTORA AS VARCHAR(50)) + CAST(EP.PROVINCIA_EJECUTORA AS VARCHAR(50)) + CAST(EP.DISTRITO_EJECUTORA AS VARCHAR(50))),
    F.ID_FINANCIAMIENTO,
    C.ID_CLASIFICADOR,
    CAST(EP.MONTO_PIA AS DECIMAL(18,2)), CAST(EP.MONTO_PIM AS DECIMAL(18,2)), CAST(EP.MONTO_CERTIFICADO AS DECIMAL(18,2)), CAST(EP.MONTO_COMPROMETIDO_ANUAL AS DECIMAL(18,2)), CAST(EP.MONTO_COMPROMETIDO AS DECIMAL(18,2)), CAST(EP.MONTO_DEVENGADO AS DECIMAL(18,2)), CAST(EP.MONTO_GIRADO AS DECIMAL(18,2))
FROM Gasto_COVID_2021 EP
LEFT JOIN Dim_Financiamiento F ON 
    ISNULL(CAST(EP.FUENTE_FINANCIAMIENTO AS VARCHAR(50)), '') = ISNULL(F.FUENTE_FINANCIAMIENTO, '') AND 
    ISNULL(CAST(EP.RUBRO AS VARCHAR(50)), '') = ISNULL(F.RUBRO, '') AND 
    ISNULL(CAST(EP.TIPO_RECURSO AS VARCHAR(50)), '') = ISNULL(F.TIPO_RECURSO, '')
LEFT JOIN Dim_Clasificador_Gasto C ON 
    ISNULL(CAST(EP.CATEGORIA_GASTO AS VARCHAR(50)), '') = ISNULL(C.CATEGORIA_GASTO, '') AND 
    ISNULL(CAST(EP.TIPO_TRANSACCION AS VARCHAR(50)), '') = ISNULL(C.TIPO_TRANSACCION, '') AND 
    ISNULL(CAST(EP.GENERICA AS VARCHAR(50)), '') = ISNULL(C.GENERICA, '') AND 
    ISNULL(CAST(EP.SUBGENERICA AS VARCHAR(50)), '') = ISNULL(C.SUBGENERICA, '') AND 
    ISNULL(CAST(EP.SUBGENERICA_DET AS VARCHAR(50)), '') = ISNULL(C.SUBGENERICA_DET, '') AND   -- <-- Este faltaba
    ISNULL(CAST(EP.ESPECIFICA AS VARCHAR(50)), '') = ISNULL(C.ESPECIFICA, '') AND           -- <-- Este faltaba
    ISNULL(CAST(EP.ESPECIFICA_DET AS VARCHAR(50)), '') = ISNULL(C.ESPECIFICA_DET, '');

PRINT '¡CORRECCIÓN COMPLETADA!';
GO

SELECT count(*) FROM Hechos_Ejecucion;

USE DataMart;
GO


-- 1. Monto devengado para la crisis del COVID-19 por región, por mes

CREATE VIEW VW_Devengado_Region_Mes AS
SELECT
    g.region,
    t.mes_nombre,
    t.anio,
    SUM(f.monto_devengado) AS total_devengado
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Geografia g ON f.id_geografia = g.id_geografia
INNER JOIN Dim_Tiempo t ON f.id_tiempo = t.id_tiempo
GROUP BY g.region, t.mes_nombre, t.anio;
GO

select * from VW_Devengado_Region_Mes


-- 2. Gasto devengado en oxígeno medicinal e infraestructura crítica  por centro de salud de destino

CREATE VIEW VW_Devengado_Oxigeno AS
SELECT
    e.centro_salud_destino,
    e.entidad,
    SUM(f.monto_devengado) AS total_devengado
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Entidad e ON f.id_entidad = e.id_entidad
INNER JOIN Dim_Estructura es ON f.id_estructura = es.id_estructura
WHERE es.producto_servicio LIKE '%oxígeno%'
   OR es.producto_servicio LIKE '%infraestructura%'
GROUP BY e.centro_salud_destino, e.entidad;
GO


-- 3. Gasto pagado por tipo de gasto en cada distrito

CREATE VIEW VW_TipoGasto_Distrito AS
SELECT
    es.tipo_gasto,
    g.distrito,
    SUM(f.monto_pagado) AS total_pagado
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Estructura es ON f.id_estructura = es.id_estructura
INNER JOIN Dim_Geografia g ON f.id_geografia = g.id_geografia
GROUP BY es.tipo_gasto, g.distrito;
GO


-- 4. Gasto devengado por programa de salud, mes a mes

CREATE VIEW VW_Programa_Salud_Mes AS
SELECT
    es.programa_salud,
    t.mes_nombre,
    t.anio,
    SUM(f.monto_devengado) AS total_devengado
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Estructura es ON f.id_estructura = es.id_estructura
INNER JOIN Dim_Tiempo t ON f.id_tiempo = t.id_tiempo
GROUP BY es.programa_salud, t.mes_nombre, t.anio;
GO


--- 5. Dinero que quedó sin gastar por entidad ejecutora, en cada año

CREATE VIEW VW_Saldo_Entidad_Anio AS
SELECT
    e.entidad,
    t.anio,
    SUM(f.monto_comprometido - f.monto_devengado) AS saldo_no_gastado
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Entidad e ON f.id_entidad = e.id_entidad
INNER JOIN Dim_Tiempo t ON f.id_tiempo = t.id_tiempo
GROUP BY e.entidad, t.anio;
GO


-- 6. Presupuesto certificado vs comprometido por fuente de financiamiento

CREATE VIEW VW_Certificado_Comprometido_Fuente AS
SELECT
    fi.fuente_financiamiento,
    SUM(f.monto_certificado) AS total_certificado,
    SUM(f.monto_comprometido) AS total_comprometido
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Financiamiento fi ON f.id_financiamiento = fi.id_financiamiento
GROUP BY fi.fuente_financiamiento;
GO



-- 7. Eficiencia del gasto por distrito (comprometido vs devengado)

CREATE VIEW VW_Eficiencia_Gasto_Distrito AS
SELECT
    g.distrito,
    SUM(f.monto_comprometido) AS total_comprometido,
    SUM(f.monto_devengado) AS total_devengado,
    CASE 
        WHEN SUM(f.monto_comprometido) = 0 THEN 0
        ELSE (SUM(f.monto_devengado) * 100.0) / SUM(f.monto_comprometido)
    END AS porcentaje_ejecucion
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Geografia g ON f.id_geografia = g.id_geografia
GROUP BY g.distrito;
GO


-- 8. Comprometido por función del estado según rubro de financiamiento

CREATE VIEW VW_Comprometido_Funcion_Rubro AS
SELECT
    es.funcion_estado,
    fi.rubro_financiero,
    SUM(f.monto_comprometido) AS total_comprometido
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Estructura es ON f.id_estructura = es.id_estructura
INNER JOIN Dim_Financiamiento fi ON f.id_financiamiento = fi.id_financiamiento
GROUP BY es.funcion_estado, fi.rubro_financiero;
GO


-- 9. Gasto devengado por programa de salud, mes a mes (análisis temporal)

CREATE VIEW VW_Programa_Salud_Mes_Temporal AS
SELECT
    es.programa_salud,
    t.mes_nombre,
    t.anio,
    SUM(f.monto_devengado) AS total_devengado
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Estructura es ON f.id_estructura = es.id_estructura
INNER JOIN Dim_Tiempo t ON f.id_tiempo = t.id_tiempo
GROUP BY es.programa_salud, t.mes_nombre, t.anio;
GO


-- 10. Ejecución del presupuesto por entidad ejecutora en cada año

CREATE VIEW VW_Ejecucion_Entidad_Anio AS
SELECT
    e.entidad,
    t.anio,
    SUM(f.monto_devengado) AS total_ejecutado
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Entidad e ON f.id_entidad = e.id_entidad
INNER JOIN Dim_Tiempo t ON f.id_tiempo = t.id_tiempo
GROUP BY e.entidad, t.anio;
GO




-- ==============================================================================
-- 1. Monto devengado para la crisis del COVID-19 por región, por mes
-- ==============================================================================
CREATE OR ALTER VIEW VW_Devengado_Region_Mes AS
SELECT
    g.region,
    t.mes_nombre,
    t.anio,
    SUM(f.monto_devengado) AS total_devengado
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Geografia g ON f.id_geografia = g.id_geografia
INNER JOIN Dim_Tiempo t ON f.id_tiempo = t.id_tiempo
GROUP BY g.region, t.mes_nombre, t.anio;
GO

-- ==============================================================================
-- 2. Gasto devengado en oxígeno medicinal e infraestructura crítica por centro 
-- ==============================================================================
CREATE OR ALTER VIEW VW_Devengado_Oxigeno AS
SELECT
    e.centro_salud_destino,
    e.entidad,
    SUM(f.monto_devengado) AS total_devengado
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Entidad e ON f.id_entidad = e.id_entidad
INNER JOIN Dim_Estructura es ON f.id_estructura = es.id_estructura
WHERE es.producto_servicio LIKE '%oxígeno%'
   OR es.producto_servicio LIKE '%infraestructura%'
GROUP BY e.centro_salud_destino, e.entidad;
GO

-- ==============================================================================
-- 3. Gasto pagado por tipo de gasto en cada distrito
-- ==============================================================================
CREATE OR ALTER VIEW VW_TipoGasto_Distrito AS
SELECT
    es.tipo_gasto,
    g.distrito,
    SUM(f.monto_pagado) AS total_pagado
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Estructura es ON f.id_estructura = es.id_estructura
INNER JOIN Dim_Geografia g ON f.id_geografia = g.id_geografia
GROUP BY es.tipo_gasto, g.distrito;
GO

-- ==============================================================================
-- 4. (y 9) Gasto devengado por programa de salud, mes a mes
-- ==============================================================================
CREATE OR ALTER VIEW VW_Programa_Salud_Mes AS
SELECT
    es.programa_salud,
    t.mes_nombre,
    t.anio,
    SUM(f.monto_devengado) AS total_devengado
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Estructura es ON f.id_estructura = es.id_estructura
INNER JOIN Dim_Tiempo t ON f.id_tiempo = t.id_tiempo
GROUP BY es.programa_salud, t.mes_nombre, t.anio;
GO

-- ==============================================================================
-- 5 y 10. Ejecución y Saldo sin gastar por entidad en cada año (Combinadas)
-- ==============================================================================
CREATE OR ALTER VIEW VW_Analisis_Entidad_Anio AS
SELECT
    e.entidad,
    t.anio,
    SUM(f.monto_devengado) AS total_ejecutado,
    SUM(f.monto_comprometido - f.monto_devengado) AS saldo_no_gastado
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Entidad e ON f.id_entidad = e.id_entidad
INNER JOIN Dim_Tiempo t ON f.id_tiempo = t.id_tiempo
GROUP BY e.entidad, t.anio;
GO

-- ==============================================================================
-- 6. Presupuesto certificado vs comprometido por fuente de financiamiento
-- ==============================================================================
CREATE OR ALTER VIEW VW_Certificado_Comprometido_Fuente AS
SELECT
    fi.fuente_financiamiento,
    SUM(f.monto_certificado) AS total_certificado,
    SUM(f.monto_comprometido) AS total_comprometido
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Financiamiento fi ON f.id_financiamiento = fi.id_financiamiento
GROUP BY fi.fuente_financiamiento;
GO

-- ==============================================================================
-- 7. Eficiencia del gasto por distrito (comprometido vs devengado)
-- ==============================================================================
CREATE OR ALTER VIEW VW_Eficiencia_Gasto_Distrito AS
SELECT
    g.distrito,
    SUM(f.monto_comprometido) AS total_comprometido,
    SUM(f.monto_devengado) AS total_devengado,
    CASE 
        WHEN SUM(f.monto_comprometido) = 0 THEN 0
        ELSE (SUM(f.monto_devengado) * 100.0) / SUM(f.monto_comprometido)
    END AS porcentaje_ejecucion
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Geografia g ON f.id_geografia = g.id_geografia
GROUP BY g.distrito;
GO

-- ==============================================================================
-- 8. Comprometido por función del estado según rubro de financiamiento
-- ==============================================================================
CREATE OR ALTER VIEW VW_Comprometido_Funcion_Rubro AS
SELECT
    es.funcion_estado,
    fi.rubro_financiero,
    SUM(f.monto_comprometido) AS total_comprometido
FROM Fact_EjecucionGasto f
INNER JOIN Dim_Estructura es ON f.id_estructura = es.id_estructura
INNER JOIN Dim_Financiamiento fi ON f.id_financiamiento = fi.id_financiamiento
GROUP BY es.funcion_estado, fi.rubro_financiero;
GO