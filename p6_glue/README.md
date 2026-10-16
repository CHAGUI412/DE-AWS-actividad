# Punto 6 - AWS Glue Data Catalog

## Qué almacena

Glue Data Catalog es un catálogo de **metadatos**: guarda la descripción de los datos, no los datos. Hay que separar dos cosas:

- **Los archivos en S3** (`s3://de-aws-p6-<cuenta>/ventas/ventas.csv`): los datos reales, filas y bytes. Glue no los copia ni los mueve.
- **Los metadatos en el catálogo:** en qué carpeta de S3 están, en qué formato (CSV, separador, si tiene encabezado, qué SerDe leerlos), qué columnas tienen y de qué tipo, particiones y estadísticas. Con eso Athena, Redshift Spectrum o EMR pueden consultar los archivos como si fueran una tabla.

Si se borra la tabla del catálogo, los CSV siguen en S3; si se borra un CSV, la tabla sigue existiendo pero devuelve menos filas.

- **Base de datos:** un contenedor lógico que agrupa tablas (aquí `de_aws_ventas`). No tiene datos propios.
- **Tabla:** la definición de un conjunto de datos: ubicación en S3, formato y esquema.
- **Crawler:** un proceso que recorre una ruta de S3, lee una muestra de los archivos, adivina el formato y los tipos con clasificadores, y crea o actualiza tablas en el catálogo. Se puede correr a mano o programado.

## Cómo reproducirlo

```bash
bash crear.sh                                # bucket, CSV, rol, base de datos, crawler y primera ejecución
AWS_PROFILE=user_cli python corregir_esquema.py
AWS_PROFILE=user_cli python athena_consultas.py
bash agregar_registros.sh                    # sube 6 filas más, recorre otra vez y consulta
AWS_PROFILE=user_cli python athena_consultas.py --manual   # tabla creada a mano
bash eliminar.sh
```

Datos: `datos/ventas.csv` con 22 ventas y `datos/ventas_extra.csv` con 6 más (inventados para la práctica). Columnas: `id_venta, fecha, ciudad, codigo_postal, producto, categoria, cantidad, precio_unitario`.

## Esquema inferido y correcciones

Lo que infirió el crawler (comprobado en la práctica, ver la salida de `crear.sh` en las evidencias) y lo que se corrigió:

| Columna | Inferido | Problema | Corregido |
|---|---|---|---|
| codigo_postal | `bigint` | los códigos de Medellín, Barranquilla y Envigado empiezan por 0 (`050001`, `080001`, `055420`); como número se vuelven `50001`, `80001`, `55420`. Además no es un valor para sumar | `string` |
| fecha | `string` | el clasificador de CSV no reconoce fechas, quedaría como texto y no se podría filtrar por rango ni usar funciones de fecha | `date` |
| id_venta, cantidad, precio_unitario | `bigint` | ninguno | se dejan |

`corregir_esquema.py` lee la tabla con `get_table`, cambia el tipo de esas dos columnas y la guarda con `update_table` (quitando los campos de solo lectura que devuelve `get_table`). El crawler se creó con `UpdateBehavior=LOG`, para que en la segunda ejecución solo registre los cambios que vea y **no sobrescriba** la corrección manual; con el valor por defecto (`UPDATE_IN_DATABASE`) el `codigo_postal` volvería a ser `bigint`.

## Consultas en Athena

Athena usa el catálogo para saber dónde están los archivos y cómo leerlos; los resultados los escribe en `s3://de-aws-p6-<cuenta>/athena-results/`.

- **A1:** conteo total de registros.
- **A2 (filtro):** ventas de audio o computadores en Medellín y Envigado. Con los 22 registros iniciales salen 4 (ids 5, 9, 14 y 19); el código postal aparece como `050001` gracias a la corrección.
- **A3 (agrupación):** ventas por ciudad. Con los 22 registros, Bogotá encabeza con $5.240.000 en 5 ventas, seguida de Medellín con $5.035.000 en 6; Envigado es la última con $755.000.

## Agregar registros y actualizar el catálogo

`agregar_registros.sh` sube `ventas_extra.csv` a la misma carpeta `ventas/`, vuelve a correr el crawler y consulta. Lo que se verifica:

- La tabla apunta a la **carpeta**, así que Athena lee los dos archivos: A1 pasa de 22 a **28**.
- A2 pasa de 4 a 6 filas (entran las ventas 23 y 25) y en A3 Medellín pasa al primer lugar con $8.720.000 en 8 ventas, por el portátil de la venta 23.
- El esquema sigue con `codigo_postal string` y `fecha date` después del segundo crawl (las métricas del crawler muestran 0 tablas creadas).

Como la tabla no tiene particiones, para ver filas nuevas no hacía falta volver a correr el crawler; el crawler es necesario cuando cambia el esquema (una columna nueva) o cuando se agregan particiones (por ejemplo carpetas `anio=2026/mes=10/`).

## Crawler vs tabla manual

La tabla `ventas_manual` se crea con un `CREATE EXTERNAL TABLE` en Athena (ver `consultas.sql`) sobre la misma carpeta, ya con los tipos correctos desde el principio. Las consultas sobre ella dan los mismos resultados.

| | Crawler | Manual |
|---|---|---|
| Esfuerzo | ninguno, lo descubre solo | hay que escribir el DDL |
| Tipos | adivinados por muestreo, se pueden equivocar (el código postal) | exactamente los que uno define |
| Cambios de esquema o particiones nuevas | los detecta en cada ejecución | hay que hacer `ALTER TABLE` o `MSCK REPAIR` a mano |
| Costo | cada ejecución cobra DPU-hora | gratis (solo el DDL en Athena, que no escanea datos) |
| Mejor para | muchos archivos o esquemas que cambian | pocas tablas con esquema conocido y estable |

## ¿Necesita credenciales de aplicación?

No. En este punto solo se usan S3, Glue y Athena, y los tres se autorizan con **IAM**: el crawler asume el rol `de-aws-glue-crawler` (política `AWSGlueServiceRole` más lectura solo de `ventas/`), y las consultas de Athena se hacen con las credenciales de `user_cli` firmadas por SigV4. No hay ninguna base de datos con usuario y contraseña de por medio, por eso no se creó otro secreto. Solo haría falta uno si el crawler o un job de Glue se conectaran por JDBC a una base como RDS o Redshift; en ese caso la conexión de Glue guardaría las credenciales en Secrets Manager.

## Costos

- **Crawler:** se cobra por DPU-hora (precio de lista $0.44, confirmar en la calculadora) por segundo, con un mínimo de 10 minutos por ejecución. Dos ejecuciones pequeñas ≈ $0.15 o menos.
- **Catálogo:** el primer millón de objetos guardados (bases, tablas, particiones) y el primer millón de peticiones al mes son gratis. Aquí son 1 base y 2 tablas, $0.
- **S3:** unos 2 KB de datos y los resultados de Athena, ~$0.
- **Athena:** $5 por TB escaneado, redondeado al MB, con mínimo de 10 MB por consulta. Los CSV pesan 1.460 y 443 bytes, así que cada consulta se cobra por el mínimo: 10 MB × $5/TB ≈ $0.00005. Unas 15 consultas ≈ $0.001. Las sentencias DDL como `CREATE EXTERNAL TABLE` no cobran.
- **Efecto del volumen escaneado:** Athena cobra por lo que lee, no por lo que devuelve. Con un CSV de 1 TB, cada consulta costaría $5 aunque devuelva una fila. Se reduce usando formatos columnares comprimidos (Parquet lee solo las columnas que pide la consulta), particionando por fecha para que los filtros salten carpetas, y comprimiendo. `athena_consultas.py` imprime los bytes escaneados de cada consulta para comprobarlo.

## Resultados medidos

- **Esquema:** tal como se esperaba, el crawler dejó `codigo_postal` como `bigint` y `fecha` como `string`; `corregir_esquema.py` los pasó a `string` y `date`.
- **Consultas con 22 registros:** A1 = 22; A2 devuelve las ventas 5, 9, 14 y 19 con el código postal intacto; A3 pone a Bogotá primero con $5.240.000 en 5 ventas. Cada consulta escaneó **1.460 bytes** (el tamaño exacto del CSV).
- **Con 28 registros:** A1 = 28; A2 sube a 6 filas (entran la 23 y la 25); Medellín pasa al primer lugar con $8.720.000 en 8 ventas. Cada consulta escaneó **1.903 bytes** (1.460 + 443). Las métricas del segundo crawl: 0 tablas creadas, 0 actualizadas, 0 borradas, y el `UpdateTime` de la tabla seguía siendo el de la corrección manual: `UpdateBehavior=LOG` protegió el esquema.
- **Tabla manual:** da las mismas filas y totales. La única diferencia visible es el formato del total (`8720000.00` frente a `8720000`) porque en la tabla manual `precio_unitario` es `DECIMAL(12,2)` y el crawler lo infirió como `bigint`.
- **Tiempos:** crawler y creación: 2 min 41 s; segundo crawl con consultas: 58 s; eliminación: 13 s.

## Evidencias

En `../evidencias/p6/`: tabla en la consola de Glue con el esquema inferido, salida de `corregir_esquema.py` (antes y después), salidas de Athena con 22 y 28 registros, métricas del segundo crawl, tabla manual, y salida de `eliminar.sh`.
