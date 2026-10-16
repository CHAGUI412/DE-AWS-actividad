# Punto 5 - Amazon Redshift

## Qué es

Redshift es el data warehouse de AWS: una base de datos columnar y distribuida pensada para análisis (OLAP), o sea consultas que leen millones de filas para agregarlas (ventas por mes, por región, cohortes, reportes de BI), más que para muchas transacciones pequeñas. Guarda los datos por columna y comprimidos, y reparte el trabajo de una consulta entre varios nodos en paralelo.

Componentes principales:

- **Aprovisionado:** un *cluster* con un nodo líder (recibe la consulta, arma el plan y junta los resultados) y nodos de cómputo que tienen los datos repartidos en *slices*. Uno elige el tipo y número de nodos.
- **Serverless:** en vez de cluster hay un **namespace** (base de datos, usuarios, esquemas, roles IAM asociados, el secreto del admin) y un **workgroup** (el cómputo, medido en RPU, más la red: VPC, subredes y grupo de seguridad).
- **Redshift Managed Storage:** el almacenamiento separado del cómputo.
- **COPY / UNLOAD:** cargar en paralelo desde S3 y exportar hacia S3. Para leer S3, Redshift asume un **rol de IAM**.
- **Data API:** API HTTP para mandar SQL sin manejar conexiones ni drivers (lo que usa el programa).
- **Query Editor v2:** editor web en la consola.
- Opciones de diseño de tablas: estilos de distribución (`DISTSTYLE`) y llaves de ordenamiento (`SORTKEY`).

## Redshift vs RDS

| | RDS | Redshift |
|---|---|---|
| Para qué | OLTP: la base de datos de una aplicación | OLAP: análisis sobre muchos datos |
| Almacenamiento | por filas | por columnas, comprimido |
| Consultas típicas | leer o actualizar pocas filas por llave, muchas veces por segundo | escanear y agregar millones de filas |
| Escala | una instancia (más réplicas de lectura) | en paralelo entre nodos o RPUs |
| Restricciones e índices | PK, FK y UNIQUE se hacen cumplir, índices B-tree | PK y FK son informativas, no se validan; no hay índices sino sort keys |

**Elegiría RDS** para el backend de una tienda en línea: registrar cada pedido, actualizar el inventario y consultar el carrito de un usuario. **Elegiría Redshift** para que el área de análisis de esa misma tienda junte años de pedidos y saque ventas por ciudad, categoría y mes para sus tableros. Normalmente se usan juntos: RDS registra y un pipeline lleva los datos a Redshift.

## Serverless vs aprovisionado: elección

Se eligió **Redshift Serverless con capacidad base de 4 RPU** en us-east-1:

- 4 RPU es el mínimo actual, está disponible en us-east-1 y cuesta $0.375 por RPU-hora, o sea **$1.50 por hora mientras hay consultas corriendo**. Se cobra por segundo con un mínimo de 60 segundos por consulta, y cuando no hay consultas no se cobra cómputo.
- Un cluster aprovisionado se cobra por cada hora que esté encendido, se use o no. Para un taller donde el cómputo realmente trabaja unos minutos, no tiene sentido pagar horas completas.
- El límite de 4 RPU sirve hasta 32 TB y 100 columnas por tabla, de sobra para dos tablas pequeñas.
- `crear.sh` además pone un límite de uso de 4 RPU-hora al día que desactiva el workgroup si se pasa, como seguro contra olvidos.

## Contraseña y autenticación

- El namespace se crea con `--manage-admin-password`: Redshift genera la contraseña de `adminrs` y la guarda en un secreto administrado. Nunca se escribe.
- `redshift_pipeline.py` obtiene el ARN con `get_namespace` (`adminPasswordSecretArn`) y se lo pasa a la Data API como `SecretArn` en cada `execute_statement`. La Data API lee el secreto y se autentica en la base. En el código no hay usuario ni contraseña.
- Para el `COPY`, el rol `de-aws-redshift-s3` confía en `redshift.amazonaws.com` y `redshift-serverless.amazonaws.com` y solo puede leer el bucket del punto (`rol_s3_lectura.json`). Se asocia al namespace como rol por defecto, por eso el SQL dice `IAM_ROLE default`.

## Conjunto de datos

`datos/clientes.csv` (12 clientes) y `datos/pedidos.csv` (30 pedidos de enero a abril de 2026), relacionados por `id_cliente`. Son datos inventados para la práctica. `clientes` usa `DISTSTYLE ALL` (es pequeña, se copia a todos los nodos y el join no mueve datos) y `pedidos` tiene `SORTKEY (fecha)` porque se filtra por fecha.

## Cómo reproducirlo

```bash
bash crear.sh                                # bucket, rol, namespace y workgroup
AWS_PROFILE=user_cli python redshift_pipeline.py
bash eliminar.sh
```

El programa: sube los CSV a `s3://de-aws-p5-<cuenta>/redshift/`, crea las tablas, carga con `COPY`, verifica conteos y corre C1–C4. Por cada sentencia hace `execute_statement`, pregunta con `describe_statement` hasta que el estado sea `FINISHED` (o lanza error si es `FAILED`) y trae las filas con `get_statement_result`. Los resultados se guardan en `resultados/c1.csv`... `c4.csv`. Todo el SQL está en `consultas.sql`.

## Consultas e interpretación

Resultados reales obtenidos en Redshift (guardados en `resultados.txt` y `resultados/c1.csv`... `c4.csv`, y en la captura de evidencias). Se cargaron 12 clientes y 30 pedidos.

**C1 – Filtro: ¿qué pedidos del primer trimestre superaron $1.000.000?** Son 11 de los 30. El más grande es el pedido 1009 de Tecnología Caribe, 5 portátiles por $17.000.000. Casi todos son portátiles o monitores; los únicos de productos baratos que pasan el umbral son compras por volumen (10 y 8 teclados, 15 hubs USB-C), todas de clientes empresa.

**C2 – Unión + agregación: ¿cuánto vende cada ciudad por segmento?** Barranquilla-empresa lidera con $29.990.000 en 6 pedidos, seguida de Medellín-empresa con $13.860.000. Aunque Medellín-persona tiene más pedidos (7), solo suma $4.480.000. Conclusión: las empresas compran menos veces pero mucho más por pedido, y Cali es la ciudad con menos ventas.

**C3 – Unión + agregación + HAVING: ¿quiénes son los mejores clientes recurrentes?** Top 5 con al menos 2 pedidos: Tecnología Caribe ($21.200.000, ticket promedio ≈ $7.066.667), Distribuidora Andina ($13.860.000), Ferretería El Tornillo ($8.790.000), Papelería Central ($4.465.000) y Laura Mejía ($3.660.000), que es la única persona natural del top gracias a un portátil.

**C4 – Agregación por mes y categoría: ¿cómo se mueven las ventas en el tiempo?** Computadores es la categoría que más vende en enero, febrero y marzo; febrero es el mejor mes (computadores $19.900.000). Abril solo tiene 3 pedidos hasta el día 8, por eso se ve bajo y no es comparable.

## Conexión desde un cliente SQL

No hizo falta: se usó la Data API y Query Editor v2, y el workgroup quedó **sin acceso público**. Si se quisiera usar DBeaver o similar desde el PC habría que: crear el workgroup con `--publicly-accessible`, usar subredes con ruta a un Internet Gateway (las de la VPC por defecto la tienen), agregar al grupo de seguridad del workgroup una regla de entrada TCP 5439 solo desde mi IP `/32`, y conectarse al endpoint del workgroup con el usuario y la contraseña copiados del secreto (o con credenciales IAM temporales).

## Costos

- **Modalidad más barata para esta práctica:** Serverless de 4 RPU, por lo explicado arriba.
- **Cómputo:** RPU-hora, $0.375 en us-east-1, por segundo con mínimo de 60 s por consulta y solo mientras hay actividad. Si el pipeline y las pruebas en Query Editor suman unos 10 minutos de cómputo: 4 × 0.375 × 10/60 ≈ **$0.25**. En aprovisionado, en cambio, se cobra la hora de cada nodo aunque esté quieto.
- **Almacenamiento:** se cobra aparte por GB-mes en Redshift Managed Storage; aquí son unos KB, prácticamente $0. Las copias en S3 (CSV y nada más) también son ~$0.
- **Secreto del admin:** $0.40/mes proporcional, menos de un centavo.
- **Qué puede seguir cobrando después de las consultas:** el almacenamiento del namespace mientras exista, los snapshots manuales o el snapshot final si se pide al borrar (por eso se borra sin `--final-snapshot-name`), el secreto administrado mientras exista el namespace, el bucket con los CSV, y en aprovisionado, el cluster completo cada hora. El cómputo Serverless en reposo no cobra, pero si una herramienta (un tablero, un cliente SQL que deja la sesión haciendo consultas) sigue mandando consultas, cada una cobra mínimo 60 s.

## Lo que pasó en la práctica

- **Permisos para la contraseña administrada:** el primer `crear.sh` falló en `create-namespace` con `ConflictException: Unable to create namespace credential secret: Amazon Redshift can't access the secret for this namespace`. La causa es que, con `--manage-admin-password`, Redshift crea el secreto en Secrets Manager con los permisos de quien llama, y según la documentación de AWS esa persona necesita además permisos de rotación, así que `user_cli` necesitaba `RotateSecret`, `UpdateSecret` y `CancelRotateSecret` (más los de crear, describir, borrar y etiquetar secretos y `GetRandomPassword`). Se agregaron a la política `user-cli-puntos-1-3a6` y se borraron los restos de la corrida fallida (bucket y rol) antes de repetir. Con RDS y DocumentDB no pasó porque no piden esos permisos.
- **Tiempos medidos:** crear namespace, workgroup, rol y bucket: 1 min 39 s. Pipeline (subir, crear tablas, `COPY`, consultas): 1 min 09 s. Eliminar todo: 3 min 33 s.
- **Verificación de la eliminación:** `list-workgroups`, `list-namespaces` y `list-snapshots` salen vacíos (`[]`) y el bucket ya no existe.

## Evidencias

En `../evidencias/p5/`: namespace con "admin password managed by Secrets Manager", workgroup con 4 RPU, rol asociado, salida de `redshift_pipeline.py`, tablas en Query Editor v2 y salida de `eliminar.sh`.
