# Actividad AWS - Ingeniería de Datos 2026-2

Solución de la actividad AWS: Secrets Manager, despliegue con Terraform/Boto3/CLI, DocumentDB, Neptune, Redshift y Glue Data Catalog. Cada punto tiene su carpeta con el código, los scripts de creación y eliminación y un `README.md` con las respuestas, los costos y cómo reproducirlo.

| Punto | Carpeta |
|---|---|
| 1. AWS Secrets Manager | [`p1_secrets_manager/`](p1_secrets_manager/) |
| 2. Terraform, SDK y AWS CLI | [`p2_despliegue/`](p2_despliegue/) |
| 3. Amazon DocumentDB | [`p3_documentdb/`](p3_documentdb/) |
| 4. Amazon Neptune | [`p4_neptune/`](p4_neptune/) |
| 5. Amazon Redshift | [`p5_redshift/`](p5_redshift/) |
| 6. AWS Glue Data Catalog | [`p6_glue/`](p6_glue/) |
| Capturas | [`evidencias/`](evidencias/) |

## Decisiones generales

- **Región única: us-east-1 (Norte de Virginia).** Es de las más baratas y donde están disponibles todas las opciones que usa el taller (Redshift Serverless de 4 RPU, DocumentDB Serverless, endpoints públicos de Neptune).
- **Red:** se usa la VPC por defecto en todos los puntos. Crear una VPC propia con subredes privadas necesitaría NAT Gateway para salir a internet, que es de lo más caro de la red y no aporta nada al taller.
- **Mínimo costo:** instancias más pequeñas disponibles, sin Multi-AZ, sin backups extra, sin IPv4 pública cuando no hace falta, borrado sin snapshot final, y cada punto se elimina al terminar sus pruebas. Cada `eliminar.sh` termina listando lo que quede como evidencia.
- **Secretos:** ninguna contraseña está en el código. Donde el servicio lo permite (RDS, DocumentDB, Redshift) la contraseña la crea y la administra el propio servicio en Secrets Manager, y los programas leen el secreto en tiempo de ejecución. Neptune y Glue/Athena no usan contraseña sino IAM.
- **Credenciales de AWS:** todo se ejecuta con el usuario IAM `user_cli` (perfil `user_cli` de `~/.aws/credentials`), nunca con la cuenta raíz. Sus claves no se suben al repo ni se guardan en Secrets Manager.

## Requisitos

- AWS CLI v2, Terraform ≥ 1.5, Python 3.11, `ssh` y `curl` (probado en WSL2 Ubuntu).
- `pip install -r requirements.txt` (boto3 y pymongo).
- Usuario `user_cli` con las políticas de `p2_despliegue/iam/` y su perfil configurado:

```bash
aws configure --profile user_cli    # región us-east-1
export AWS_PROFILE=user_cli
aws sts get-caller-identity         # debe decir user/user_cli
```

## Orden sugerido

Primero el punto 2 (porque ahí se crea `user_cli`), luego el 1 y después del 3 al 6. Cada punto se reproduce con `bash crear.sh`, el programa de Python y `bash eliminar.sh`; los pasos exactos están en su README.

## Resumen de costos (us-east-1)

| Punto | Recursos con cobro | Por hora encendido | Gasto aproximado de la práctica |
|---|---|---|---|
| 1 | 1 secreto | $0.0005 | < $0.01 |
| 2 | EC2 t3.micro + RDS db.t4g.micro + secreto RDS | ≈ $0.031 | ≈ $0.03 (3 despliegues de ~20 min) |
| 3 | DocumentDB Serverless 0.5 DCU + EC2 túnel | ≈ $0.058 | ≈ $0.11–0.20 |
| 4 | Neptune db.t4g.medium | ≈ $0.073 | ≈ $0.15 (o $0 con prueba gratis) |
| 5 | Redshift Serverless 4 RPU (solo con consultas) | $1.50 activo | ≈ $0.25 |
| 6 | Crawler + Athena | por ejecución | ≈ $0.15 |

Los detalles de cada cálculo y las fuentes de precios están en el README de cada punto. Los precios marcados "confirmar" son precios de lista que conviene revisar en la calculadora de AWS el día del despliegue.

## Tiempos medidos

| Punto | Crear | Eliminar |
|---|---|---|
| 2 Terraform / Boto3 / CLI | 5:24 / 5:28 / 5:28 | 2:04 / 1:35 / 1:47 |
| 3 DocumentDB Serverless + EC2 | 5:32 | 13:37 |
| 4 Neptune db.t4g.medium | 11:29 | 9:57 |
| 5 Redshift Serverless | 1:39 (+ 1:09 de pipeline) | 3:33 |
| 6 Glue + Athena | 2:41 (+ 0:58 segundo crawl) | 0:13 |

## Lecciones de la práctica

- **Plan gratuito:** DocumentDB no se puede crear en el plan gratuito de AWS (`FreeTierRestrictionError`); hubo que pasar a plan de pago. Los costos reales fueron de centavos porque todo se eliminó al terminar cada punto.
- **IP de salida variable:** los grupos de seguridad abiertos solo a mi IP con `/32` fallaron cuando el proveedor cambió la dirección. Los scripts de los puntos 3 y 4 usan el `/24` de la IP actual.
- **Permisos de `user_cli` por punto:** cada servicio pidió permisos que no estaban a la vista (Redshift: `RotateSecret` y `UpdateSecret` para la contraseña administrada). El error de AWS nombra la causa, y los permisos finales quedaron en `p2_despliegue/iam/`.

## Qué no está en el repo

Por las condiciones de entrega no se publican: valores de secretos, claves de IAM, llaves privadas (`*.pem`), archivos de estado de Terraform (`*.tfstate`) ni los `estado_*.env` que generan los scripts con los ids de los recursos. Todo eso está en `.gitignore`. Las capturas en `evidencias/` no muestran contraseñas ni claves.
