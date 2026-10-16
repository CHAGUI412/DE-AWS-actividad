# Punto 2 - Despliegue con Terraform, Boto3 y AWS CLI

## Terraform

Terraform es una herramienta de infraestructura como código: uno describe en archivos `.tf` los recursos que quiere (un bucket, una instancia, una base de datos) y Terraform se encarga de crearlos llamando a la API del proveedor. El ciclo es:

- `terraform init`: descarga el provider de AWS.
- `terraform plan`: compara lo que está en los archivos con lo que existe y muestra qué va a crear, cambiar o borrar, sin tocar nada.
- `terraform apply`: ejecuta ese plan.
- `terraform destroy`: elimina todo lo que Terraform creó.

Lo que diferencia a Terraform de un script es que es declarativo y guarda un **archivo de estado** (`terraform.tfstate`) con el mapeo entre cada recurso del código y su id real en AWS, más todos sus atributos. Por eso puede saber qué cambió y borrar exactamente lo que creó.

## Usuario user_cli y cómo se autentican las herramientas

1. En la consola IAM (con la cuenta raíz o un admin, solo esta vez) se crea el usuario `user_cli` sin acceso a la consola.
2. Se le adjuntan dos políticas **administradas por el cliente** (customer managed, creadas en IAM → Políticas): `user-cli-puntos-2` con el contenido de `iam/politica_user_cli.json` (lo de este punto) y `user-cli-puntos-1-3a6` con `iam/politica_user_cli_puntos_1_3a6.json` (lo que necesitan los demás puntos).
3. Se crea una clave de acceso para uso en CLI y se configura en local:

```bash
aws configure --profile user_cli    # access key, secret key, us-east-1, json
aws sts get-caller-identity --profile user_cli   # debe mostrar .../user/user_cli
```

Las tres herramientas leen las mismas credenciales de `~/.aws/credentials` con la cadena estándar de AWS: la CLI y Boto3 por la variable `AWS_PROFILE=user_cli` y Terraform por `profile = "user_cli"` en el provider. Con esas claves firman cada petición (firma SigV4), así que nada de esto pasa por Secrets Manager: para leer un secreto primero hay que estar autenticado en AWS, entonces guardar las claves de acceso dentro de un secreto sería circular. Las claves quedan en el computador, fuera del repo, y se borran al terminar el taller.

### Permisos y por qué

| Recurso | Acciones | Motivo |
|---|---|---|
| S3 | `CreateBucket`, `DeleteBucket`, `GetBucket*`, `PutBucketTagging`, `PutBucketPublicAccessBlock`, objetos | Terraform, al crear un bucket, lee toda su configuración (versionado, cifrado, ACL, CORS...), por eso necesita los `Get*`. Limitado a buckets `de-aws-*` |
| EC2 | `RunInstances`, `TerminateInstances`, `Describe*`, `CreateTags` | crear la instancia, esperar a que esté lista y borrarla |
| Red | `Create/DeleteSecurityGroup`, `Authorize/RevokeSecurityGroupIngress/Egress` | los dos grupos de seguridad (Terraform revoca la regla de salida por defecto y pone la suya) |
| SSM | `GetParameter` sobre `/aws/service/ami-amazon-linux-latest/*` | buscar el id de la AMI más reciente de Amazon Linux 2023 |
| RDS | `Create/Delete/ModifyDBInstance`, `Create/DeleteDBSubnetGroup`, `Describe*`, tags | la base de datos y su grupo de subredes |
| Secrets Manager / KMS | `CreateSecret`, `TagResource`, `DescribeKey` | con `manage_master_user_password` RDS crea el secreto en nombre de quien hace la llamada |
| IAM | `CreateServiceLinkedRole` solo para `rds.amazonaws.com` | la primera vez que una cuenta usa RDS se crea su rol de servicio |

Para verificar que no se usa la raíz: todas las corridas muestran primero `aws sts get-caller-identity` con el ARN de `user_cli` (captura en evidencias).

## Qué se despliega

Las tres versiones crean lo mismo en la VPC por defecto (sin VPC nueva, sin NAT, que es lo más caro de la red):

- Bucket S3 `de-aws-p2-<metodo>-<cuenta>` con acceso público bloqueado.
- EC2 `t3.micro` con Amazon Linux 2023, disco gp3 de 8 GB, **sin IPv4 pública** (AWS cobra cada IPv4 pública por hora).
- RDS PostgreSQL `db.t4g.micro`, 20 GB gp3, una sola zona, sin backups automáticos, sin acceso público.
- Red: un grupo de seguridad para la EC2, otro para RDS que solo deja entrar al 5432 desde la EC2, y un grupo de subredes con las subredes por defecto.

La contraseña de RDS la administra Secrets Manager (`manage_master_user_password` / `ManageMasterUserPassword` / `--manage-master-user-password`). PostgreSQL en RDS lo permite. RDS crea un secreto con nombre `rds!db-...` y la contraseña nunca la escribimos nosotros ni pasa por ninguna de las tres herramientas.

## Cómo reproducirlo (en orden, eliminando antes de la siguiente)

```bash
# 1) Terraform
cd terraform
terraform init
terraform plan -out plan.tfplan
terraform apply plan.tfplan
terraform output
terraform destroy

# 2) Boto3
cd ../boto3
AWS_PROFILE=user_cli python desplegar.py
AWS_PROFILE=user_cli python eliminar.py

# 3) AWS CLI
cd ../cli
bash crear.sh
bash eliminar.sh
```

Cada eliminación termina listando lo que queda (debe salir vacío): instancias RDS, EC2 con la etiqueta del método, buckets `de-aws-p2` y secretos `rds!`. El secreto de RDS se borra solo cuando se borra la instancia.

## Archivo de estado de Terraform

El `terraform.tfstate` guarda en texto plano todos los atributos de cada recurso: ids, ARNs, endpoints, y si uno le pasa una contraseña a `aws_db_instance` con `password = ...`, también la contraseña, aunque se marque como `sensitive` (eso solo la oculta de la pantalla, no del archivo). Por eso aquí se usa `manage_master_user_password = true`: en el estado solo queda el ARN del secreto, no su valor. Igual el `.tfstate` está en `.gitignore`; en un proyecto real se guardaría en un backend remoto como S3 cifrado con bloqueo.

## Comparación de los métodos

| | Terraform | Boto3 | AWS CLI |
|---|---|---|---|
| Tiempo para crear (medido) | 5 min 24 s | 5 min 28 s | 5 min 28 s |
| Tiempo para eliminar (medido) | 2 min 04 s | 1 min 35 s | 1 min 47 s |
| Estilo | declarativo: describo el resultado | imperativo: escribo cada llamada | imperativo, comando por comando |
| Orden y dependencias | lo calcula solo (sabe que el SG va antes que RDS) | lo tengo que poner yo, y esperar con waiters | igual que boto3, con `aws ... wait` |
| Saber qué existe | el `.tfstate` | un JSON que guardo yo (`estado_boto3.json`) | un `.env` que guardo yo |
| Eliminar | `terraform destroy` y listo | otro script, en orden inverso | otro script, en orden inverso |
| Repetir sin duplicar | sí, si ya existe no hace nada | no, falla porque el recurso ya existe | no, igual |
| Plan antes de aplicar | sí (`plan`) | no | no |
| Mejor para | infraestructura que dura y se versiona | automatizar dentro de programas Python | pruebas rápidas y scripts cortos |

Los tiempos medidos son casi iguales porque los domina la espera de RDS y EC2 (que AWS tarda lo mismo sin importar la herramienta), no la herramienta. Lo que más se nota es la eliminación: en Terraform fue un solo comando, en los otros dos hubo que esperar a que RDS y EC2 terminaran antes de poder borrar los grupos de seguridad.

## Costos (us-east-1, precios bajo demanda)

Precios de lista usados (confirmar en la calculadora de AWS antes de desplegar): EC2 t3.micro $0.0104/h, EBS gp3 $0.08/GB-mes, RDS PostgreSQL db.t4g.micro $0.016/h, almacenamiento RDS gp3 $0.115/GB-mes, S3 Standard $0.023/GB-mes, secreto $0.40/mes.

| Componente | 1 hora | 1 semana (168 h) |
|---|---|---|
| EC2 t3.micro | $0.0104 | $1.75 |
| Disco EC2 8 GB | $0.0009 | $0.15 |
| RDS db.t4g.micro | $0.0160 | $2.69 |
| Almacenamiento RDS 20 GB | $0.0032 | $0.53 |
| Secreto de RDS | $0.0005 | $0.09 |
| Bucket S3 vacío | ~$0 | ~$0 |
| **Total** | **≈ $0.031** | **≈ $5.20** |

El cálculo de los mensuales es proporcional: por ejemplo 20 GB × 0.115 × 168 / 730 horas = $0.53.

Siguen cobrando sin recibir tráfico: las horas de la EC2 y de RDS (se cobran por estar encendidas, no por uso), los discos de ambas (incluso con la EC2 apagada, el EBS se sigue cobrando) y el secreto. Si la EC2 tuviera IPv4 pública sumaría $0.005/h; por eso se dejó sin ella. El bucket vacío no cuesta. Ojo también con instantáneas: si RDS se borrara con snapshot final, ese snapshot sí se cobra; por eso se borra con `skip_final_snapshot`.

El secreto de RDS añade $0.40/mes proporcional (≈ $0.0005 por hora, $0.09 a la semana) más $0.05 por cada 10,000 lecturas, que aquí son prácticamente cero. Si la cuenta es nueva, todo esto puede salir de los créditos de la capa gratuita.

Las tres versiones se dejaron activas unos 15-20 minutos cada una, así que el gasto real del punto fue de centavos.

## Evidencias

En `../evidencias/p2/`: `get-caller-identity` con user_cli, `terraform plan`/`apply`/`output`/`destroy`, salida de `desplegar.py`/`eliminar.py`, salida de `crear.sh`/`eliminar.sh`, y la consola mostrando el secreto `rds!` (sin abrir su valor).
