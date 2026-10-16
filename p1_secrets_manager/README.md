# Punto 1 - AWS Secrets Manager

## Qué es

Secrets Manager es el servicio de AWS para guardar información sensible como contraseñas de bases de datos, llaves de APIs externas, tokens o cadenas de conexión. Cada secreto se guarda cifrado con KMS (por defecto con la llave `aws/secretsmanager`) y puede tener hasta 64 KB, normalmente como un JSON con varios campos.

Quién puede leer un secreto se controla con IAM: una política le da a un usuario o rol la acción `secretsmanager:GetSecretValue` sobre el ARN de ese secreto puntual. También se puede poner una política de recurso en el propio secreto, y si se usa una llave KMS propia, el que lee también necesita `kms:Decrypt` sobre esa llave.

Las tres operaciones que pide distinguir:

- **Crear** (`CreateSecret`): se registra el secreto con un nombre y su primer valor. Esto lo hace un administrador o el pipeline de despliegue, una sola vez.
- **Recuperar** (`GetSecretValue`): lo que hace la aplicación cada vez que necesita la credencial. Por defecto devuelve la versión con la etiqueta `AWSCURRENT`, por eso el código nunca tiene que saber cuál es el valor.
- **Rotar**: cambiar el valor de forma periódica y automática. Una función Lambda (o el propio servicio, en los secretos que administra RDS/DocumentDB/Redshift) genera la nueva contraseña, la aplica en la base de datos y mueve la etiqueta `AWSCURRENT` a la versión nueva. La versión anterior queda como `AWSPREVIOUS`. Actualizar a mano con `PutSecretValue` es parecido, pero ahí nadie cambia la contraseña real en la base de datos, solo el valor guardado.

## Cómo reproducirlo

Requiere el perfil `user_cli` configurado (ver punto 2) y `pip install -r ../requirements.txt`.

```bash
bash crear.sh                 # crea el secreto y el rol de solo lectura
# copiar el bloque [profile lector-p1] que imprime al final en ~/.aws/config
# esperar ~10 s a que IAM propague el rol
AWS_PROFILE=lector-p1 python leer_secreto.py
bash actualizar.sh            # cambia usuario y contraseña
AWS_PROFILE=lector-p1 python leer_secreto.py   # mismo código, valor nuevo
AWS_PROFILE=lector-p1 python leer_secreto.py --veces 5 --cache 60
bash eliminar.sh
```

## Política de acceso

El programa no corre con `user_cli` sino asumiendo el rol `de-aws-lector-p1`, que solo tiene `politica_lectura.json`: `GetSecretValue` y `DescribeSecret` sobre el ARN `de-aws/p1/demo-??????`. Los seis signos de interrogación son porque AWS le agrega al ARN un sufijo aleatorio de 6 caracteres. El script al final intenta leer otro secreto y debe salir `AccessDeniedException`, eso sirve como evidencia de que el permiso es solo para ese secreto.

La contraseña de prueba la genera `get-random-password`, así que nunca está escrita en el código ni en el repo, y el script de Python la muestra enmascarada para que las capturas no la expongan.

## Actualización del secreto

`actualizar.sh` hace `put-secret-value` con un usuario y contraseña nuevos. Secrets Manager crea una versión nueva, le pone `AWSCURRENT` y la anterior pasa a `AWSPREVIOUS` (se ve en la tabla de `list-secret-version-ids`). Como `leer_secreto.py` pide el secreto por nombre y sin especificar versión, la siguiente ejecución ya imprime `usuario_demo_v2` y un `VersionId` distinto, sin haber cambiado una línea de código.

## Costos (us-east-1)

- Cada secreto cuesta $0.40 al mes, cobrado proporcional por hora, y las llamadas a la API cuestan $0.05 por cada 10,000.
- Para esta prueba: el secreto vive máximo un par de horas → 0.40 × 2 / 720 ≈ $0.0011. Unas 50 llamadas a la API ≈ $0.00025. En total menos de un centavo. Si la cuenta tiene créditos de la capa gratuita, también salen de ahí.
- Si el programa consulta el mismo secreto repetidamente, el costo de almacenamiento no cambia (sigue siendo un secreto) pero cada `GetSecretValue` es una llamada facturada. Por ejemplo, una Lambda que lee el secreto en cada invocación con 1 millón de invocaciones al mes son 100 × $0.05 = $5 solo en lecturas, más la latencia extra de cada llamada.
- Conviene guardar el valor en memoria cuando el programa lo lee muchas veces en poco tiempo (un proceso de larga duración, una API, una Lambda que se reutiliza entre invocaciones). Lo normal es un tiempo de vida corto (minutos) para que, si el secreto rota, el programa tome el valor nuevo pronto. Si la conexión falla por autenticación, se vuelve a leer el secreto sin esperar a que venza el cache. AWS tiene la librería `aws-secretsmanager-caching` que hace esto mismo; en el script lo hice a mano con `--cache` y al final imprime cuántas llamadas reales hizo vs cuántas lecturas pidió.

## Permisos de `user_cli` sobre Secrets Manager

Para este punto `user_cli` necesita `CreateSecret`, `PutSecretValue`, `DescribeSecret`, `GetSecretValue`, `ListSecretVersionIds`, `DeleteSecret` y `TagResource`. Más adelante, en el punto 5, hubo que agregar `RotateSecret`, `UpdateSecret` y `CancelRotateSecret`: Redshift, cuando administra la contraseña con Secrets Manager, crea el secreto con los permisos de quien llama y la documentación de AWS pide también los de rotación; sin esos permisos `create-namespace` falla con `ConflictException: Amazon Redshift can't access the secret` (ver el README del punto 5).

## Evidencias

En `../evidencias/p1/`: creación del secreto, primera lectura, salida de `actualizar.sh`, segunda lectura con versión nueva, lectura con cache, `AccessDenied` sobre otro secreto y la salida de `eliminar.sh`.
