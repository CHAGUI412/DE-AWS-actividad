-- Punto 6 - consultas de Athena (las ejecuta athena_consultas.py)

-- A1 conteo total
SELECT COUNT(*) AS registros FROM de_aws_ventas.ventas;

-- A2 filtro: ventas de audio o computadores en Medellín y Envigado
SELECT id_venta, fecha, ciudad, codigo_postal, producto, cantidad * precio_unitario AS total
FROM de_aws_ventas.ventas
WHERE ciudad IN ('Medellín', 'Envigado') AND categoria IN ('audio', 'computadores')
ORDER BY fecha;

-- A3 agrupacion: ventas por ciudad
SELECT ciudad, codigo_postal, COUNT(*) AS ventas, SUM(cantidad) AS unidades,
       SUM(cantidad * precio_unitario) AS total
FROM de_aws_ventas.ventas
GROUP BY ciudad, codigo_postal
ORDER BY total DESC;

-- Tabla creada a mano (para comparar con el crawler)
CREATE EXTERNAL TABLE IF NOT EXISTS de_aws_ventas.ventas_manual (
    id_venta        INT,
    fecha           DATE,
    ciudad          STRING,
    codigo_postal   STRING,
    producto        STRING,
    categoria       STRING,
    cantidad        INT,
    precio_unitario DECIMAL(12,2)
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
LOCATION 's3://{bucket}/ventas/'
TBLPROPERTIES ('skip.header.line.count' = '1');
