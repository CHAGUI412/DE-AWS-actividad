# Evidencias

Capturas de pantalla de la ejecución real, ordenadas por punto. Ninguna muestra contraseñas, claves de acceso ni llaves privadas (las capturas donde aparecía una clave se descartaron).

| Punto | Carpeta | Qué se ve |
|---|---|---|
| 1. Secrets Manager | [p1](p1) | secreto en consola, versiones (AWSCURRENT/AWSPREVIOUS), lecturas con caché y tras actualizar, `AccessDeniedException` al leer otro secreto, eliminación |
| 2. Terraform / Boto3 / CLI | [p2](p2) | creación de `user_cli` y sus políticas (01–07); Terraform (10–18), Boto3 (20–26) y CLI (30–35): salida con el tiempo medido, RDS, S3, EC2, secreto y verificación de eliminación |
| 3. DocumentDB | [p3](p3) | actualización a plan de pago, clúster en consola, túnel SSH (timeout por IP rotativa y luego conectado), Compass y consultas con PyMongo |
| 4. Neptune | [p4](p4) | `crear.sh` (11 min 29 s), clúster en consola, consultas Gremlin |
| 5. Redshift | [p5](p5) | secreto administrado, Redshift Serverless en consola, datos en S3, eliminación verificada (`[]`) |
| 6. Glue / Athena | [p6](p6) | crawler, tablas, esquema inferido y corregido, consultas en Athena (22 → 28 registros), tabla manual con DECIMAL, eliminación |

La salida en texto de los scripts de P3 a P5 también está en los README de cada punto y en los archivos `resultados*` de cada carpeta.
