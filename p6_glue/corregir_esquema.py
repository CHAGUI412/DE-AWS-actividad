"""
Punto 6 - corrige el esquema que infirio el crawler.
El crawler toma codigo_postal como bigint (050001 -> 50001, se pierde el cero)
y fecha como string. Aqui se cambian a string y date.
    AWS_PROFILE=user_cli python corregir_esquema.py
"""
import boto3

glue = boto3.client("glue", region_name="us-east-1")
DB, TABLA = "de_aws_ventas", "ventas"
CORRECCIONES = {"codigo_postal": "string", "fecha": "date"}

tabla = glue.get_table(DatabaseName=DB, Name=TABLA)["Table"]
columnas = tabla["StorageDescriptor"]["Columns"]

print("antes:")
for c in columnas:
    print(f"  {c['Name']:<16} {c['Type']}")

for c in columnas:
    if c["Name"] in CORRECCIONES:
        c["Type"] = CORRECCIONES[c["Name"]]

# update_table solo acepta estos campos del TableInput (get_table trae otros de solo lectura)
permitidos = ["Name", "Description", "Owner", "Retention", "StorageDescriptor",
              "PartitionKeys", "TableType", "Parameters"]
entrada = {k: v for k, v in tabla.items() if k in permitidos}
entrada["Parameters"] = {**entrada.get("Parameters", {}), "corregido_a_mano": "true"}
glue.update_table(DatabaseName=DB, TableInput=entrada)

print("\ndespues:")
for c in glue.get_table(DatabaseName=DB, Name=TABLA)["Table"]["StorageDescriptor"]["Columns"]:
    print(f"  {c['Name']:<16} {c['Type']}")
