"""
Punto 5 - sube los CSV a S3, crea las tablas, carga con COPY y consulta,
todo con boto3 y la API de datos de Redshift. La autenticacion de la base
de datos es con el secreto que administra Redshift (SecretArn), sin contrasenas.
    AWS_PROFILE=user_cli python redshift_pipeline.py
"""
import csv
import os
import time

import boto3

REGION = "us-east-1"
WORKGROUP = "de-aws-wg"
DATABASE = "dev"

sesion = boto3.Session(region_name=REGION)
s3 = sesion.client("s3")
data_api = sesion.client("redshift-data")
rs = sesion.client("redshift-serverless")

cuenta = sesion.client("sts").get_caller_identity()["Account"]
BUCKET = f"de-aws-p5-{cuenta}"
SECRET_ARN = rs.get_namespace(namespaceName="de-aws-ns")["namespace"]["adminPasswordSecretArn"]
print("secreto usado:", SECRET_ARN.split(":")[-1])

# 1) subir archivos
for archivo in ["clientes.csv", "pedidos.csv"]:
    s3.upload_file(os.path.join("datos", archivo), BUCKET, f"redshift/{archivo}")
    print("subido", f"s3://{BUCKET}/redshift/{archivo}")


def ejecutar(sql):
    """Manda el SQL, espera a que termine y devuelve (columnas, filas) si hay resultado."""
    r = data_api.execute_statement(WorkgroupName=WORKGROUP, Database=DATABASE, SecretArn=SECRET_ARN, Sql=sql)
    while True:
        d = data_api.describe_statement(Id=r["Id"])
        if d["Status"] in ("FINISHED", "FAILED", "ABORTED"):
            break
        time.sleep(1)
    if d["Status"] != "FINISHED":
        raise RuntimeError(f"{d['Status']}: {d.get('Error')}\nSQL: {sql[:200]}")
    if not d.get("HasResultSet"):
        return None, None
    res = data_api.get_statement_result(Id=r["Id"])
    cols = [c["name"] for c in res["ColumnMetadata"]]
    filas = [[list(v.values())[0] if v and "isNull" not in v else None for v in fila] for fila in res["Records"]]
    return cols, filas


# 2) partir consultas.sql en sentencias y separar las de carga de las consultas
with open("consultas.sql", encoding="utf-8") as f:
    texto = f.read().replace("{bucket}", BUCKET)
lineas = [l for l in texto.splitlines() if not l.strip().startswith("--")]
sentencias = [s.strip() for s in "\n".join(lineas).split(";") if s.strip()]
preparacion = [s for s in sentencias if not s.upper().startswith("SELECT")]
consultas = [s for s in sentencias if s.upper().startswith("SELECT")]

for s in preparacion:
    ejecutar(s)
    print("ok:", s.split("\n")[0][:70])

_, n1 = ejecutar("SELECT COUNT(*) FROM clientes")
_, n2 = ejecutar("SELECT COUNT(*) FROM pedidos")
print(f"filas cargadas -> clientes: {n1[0][0]}, pedidos: {n2[0][0]}")

# 3) consultas: imprimir y guardar cada resultado en CSV
os.makedirs("resultados", exist_ok=True)
for i, q in enumerate(consultas, start=1):
    cols, filas = ejecutar(q)
    print(f"\n--- C{i} ---")
    print(" | ".join(cols))
    for fila in filas:
        print(" | ".join(str(v) for v in fila))
    with open(f"resultados/c{i}.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(cols)
        w.writerows(filas)
