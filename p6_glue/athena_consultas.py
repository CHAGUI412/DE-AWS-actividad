"""
Punto 6 - consulta la tabla del catalogo desde Athena.
    AWS_PROFILE=user_cli python athena_consultas.py            # consultas A1-A3
    AWS_PROFILE=user_cli python athena_consultas.py --manual   # crea la tabla manual y la consulta
Imprime tambien los bytes escaneados de cada consulta (eso es lo que cobra Athena).
"""
import sys
import time

import boto3

sesion = boto3.Session(region_name="us-east-1")
athena = sesion.client("athena")
cuenta = sesion.client("sts").get_caller_identity()["Account"]
BUCKET = f"de-aws-p6-{cuenta}"
SALIDA = f"s3://{BUCKET}/athena-results/"


def consultar(sql):
    qid = athena.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": "de_aws_ventas"},
        ResultConfiguration={"OutputLocation": SALIDA},
        WorkGroup="primary",
    )["QueryExecutionId"]
    while True:
        e = athena.get_query_execution(QueryExecutionId=qid)["QueryExecution"]
        if e["Status"]["State"] in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(1)
    if e["Status"]["State"] != "SUCCEEDED":
        raise RuntimeError(e["Status"].get("StateChangeReason"))
    escaneado = e["Statistics"].get("DataScannedInBytes", 0)
    filas = athena.get_query_results(QueryExecutionId=qid)["ResultSet"]["Rows"]
    tabla = [[c.get("VarCharValue", "") for c in f["Data"]] for f in filas]
    return tabla, escaneado


with open("consultas.sql", encoding="utf-8") as f:
    texto = f.read().replace("{bucket}", BUCKET)
lineas = [l for l in texto.splitlines() if not l.strip().startswith("--")]
sentencias = [s.strip() for s in "\n".join(lineas).split(";") if s.strip()]
selects = [s for s in sentencias if s.upper().startswith("SELECT")]
ddl = [s for s in sentencias if s.upper().startswith("CREATE")]

if "--manual" in sys.argv:
    consultar(ddl[0])
    print("tabla ventas_manual creada")
    # misma agrupacion contra la tabla manual
    selects = [s.replace("de_aws_ventas.ventas", "de_aws_ventas.ventas_manual") for s in selects]

for i, q in enumerate(selects, start=1):
    tabla, escaneado = consultar(q)
    print(f"\n--- A{i} (escaneó {escaneado} bytes) ---")
    for fila in tabla:
        print(" | ".join(fila))
