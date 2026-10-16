-- Punto 5 - SQL que ejecuta redshift_pipeline.py (mismo orden)

-- ===== tablas =====
DROP TABLE IF EXISTS pedidos;
DROP TABLE IF EXISTS clientes;

CREATE TABLE clientes (
    id_cliente      INT PRIMARY KEY,
    nombre          VARCHAR(100),
    ciudad          VARCHAR(50),
    segmento        VARCHAR(20),
    fecha_registro  DATE
) DISTSTYLE ALL;

CREATE TABLE pedidos (
    id_pedido        INT PRIMARY KEY,
    id_cliente       INT REFERENCES clientes(id_cliente),
    fecha            DATE,
    producto         VARCHAR(100),
    categoria        VARCHAR(30),
    cantidad         INT,
    precio_unitario  DECIMAL(12,2)
) SORTKEY (fecha);

-- ===== carga =====
COPY clientes FROM 's3://{bucket}/redshift/clientes.csv'
IAM_ROLE default FORMAT AS CSV IGNOREHEADER 1 DATEFORMAT 'YYYY-MM-DD';

COPY pedidos FROM 's3://{bucket}/redshift/pedidos.csv'
IAM_ROLE default FORMAT AS CSV IGNOREHEADER 1 DATEFORMAT 'YYYY-MM-DD';

-- ===== consultas =====

-- C1 (filtro): pedidos grandes, mas de 1.000.000, del primer trimestre de 2026
SELECT id_pedido, fecha, producto, cantidad, cantidad * precio_unitario AS total
FROM pedidos
WHERE cantidad * precio_unitario > 1000000
  AND fecha BETWEEN '2026-01-01' AND '2026-03-31'
ORDER BY total DESC;

-- C2 (union + agregacion): ventas por ciudad y segmento
SELECT c.ciudad, c.segmento,
       COUNT(*) AS pedidos,
       SUM(p.cantidad * p.precio_unitario) AS ventas
FROM pedidos p
JOIN clientes c ON c.id_cliente = p.id_cliente
GROUP BY c.ciudad, c.segmento
ORDER BY ventas DESC;

-- C3 (union + agregacion + filtro de grupo): top 5 clientes, con su ticket promedio
SELECT c.nombre, c.ciudad,
       COUNT(*) AS pedidos,
       SUM(p.cantidad * p.precio_unitario) AS total_comprado,
       ROUND(AVG(p.cantidad * p.precio_unitario), 0) AS ticket_promedio
FROM pedidos p
JOIN clientes c ON c.id_cliente = p.id_cliente
GROUP BY c.nombre, c.ciudad
HAVING COUNT(*) >= 2
ORDER BY total_comprado DESC
LIMIT 5;

-- C4 (agregacion por mes y categoria)
SELECT DATE_TRUNC('month', fecha)::DATE AS mes, categoria,
       SUM(cantidad * precio_unitario) AS ventas
FROM pedidos
GROUP BY 1, 2
ORDER BY 1, 3 DESC;
