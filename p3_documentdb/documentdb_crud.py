"""
Punto 3 - DocumentDB desde Python a traves del tunel SSH.
Antes: dejar corriendo el tunel que imprime crear.sh (localhost:27017 -> cluster).
    AWS_PROFILE=user_cli python documentdb_crud.py
"""
import json
from urllib.parse import quote_plus

import boto3
from pymongo import MongoClient

REGION = "us-east-1"

# el ARN del secreto se pide a DocumentDB, la contrasena a Secrets Manager
docdb = boto3.client("docdb", region_name=REGION)
cluster = docdb.describe_db_clusters(DBClusterIdentifier="de-aws-docdb")["DBClusters"][0]
arn = cluster["MasterUserSecret"]["SecretArn"]
cred = json.loads(boto3.client("secretsmanager", region_name=REGION).get_secret_value(SecretId=arn)["SecretString"])

# localhost porque vamos por el tunel; tlsAllowInvalidHostnames porque el certificado
# es del endpoint real y no de localhost
uri = (
    f"mongodb://{quote_plus(cred['username'])}:{quote_plus(cred['password'])}@localhost:27017/"
    "?tls=true&tlsCAFile=global-bundle.pem&tlsAllowInvalidHostnames=true"
    "&directConnection=true&retryWrites=false"
)
cliente = MongoClient(uri, serverSelectionTimeoutMS=10000)
print("conectado, version:", cliente.server_info()["version"])

db = cliente["tienda"]
col = db["productos"]
col.drop()  # para poder correrlo varias veces

productos = [
    {"nombre": "Teclado mecánico", "categoria": "perifericos", "precio": 180000, "stock": 15, "ciudad": "Medellín"},
    {"nombre": "Mouse inalámbrico", "categoria": "perifericos", "precio": 65000, "stock": 40, "ciudad": "Bogotá"},
    {"nombre": "Monitor 24", "categoria": "pantallas", "precio": 620000, "stock": 8, "ciudad": "Medellín"},
    {"nombre": "Monitor 27", "categoria": "pantallas", "precio": 980000, "stock": 5, "ciudad": "Cali"},
    {"nombre": "Audífonos", "categoria": "audio", "precio": 210000, "stock": 22, "ciudad": "Barranquilla"},
    {"nombre": "Parlante bluetooth", "categoria": "audio", "precio": 150000, "stock": 0, "ciudad": "Bogotá"},
    {"nombre": "Portátil 14", "categoria": "computadores", "precio": 2900000, "stock": 6, "ciudad": "Medellín"},
    {"nombre": "Portátil 15", "categoria": "computadores", "precio": 3400000, "stock": 3, "ciudad": "Bogotá"},
    {"nombre": "Webcam HD", "categoria": "perifericos", "precio": 120000, "stock": 12, "ciudad": "Cali"},
    {"nombre": "Micrófono USB", "categoria": "audio", "precio": 260000, "stock": 9, "ciudad": "Medellín"},
    {"nombre": "Base refrigerante", "categoria": "accesorios", "precio": 85000, "stock": 30, "ciudad": "Barranquilla"},
    {"nombre": "Hub USB-C", "categoria": "accesorios", "precio": 95000, "stock": 0, "ciudad": "Bogotá"},
]
r = col.insert_many(productos)
print("documentos insertados:", len(r.inserted_ids))

print("\n1) Filtro: periféricos o audio con stock y precio menor a 200.000")
for d in col.find({"categoria": {"$in": ["perifericos", "audio"]}, "stock": {"$gt": 0}, "precio": {"$lt": 200000}},
                  {"_id": 0, "nombre": 1, "precio": 1, "stock": 1}):
    print("  ", d)

print("\n2) Ordenación: los 5 más caros")
for d in col.find({}, {"_id": 0, "nombre": 1, "precio": 1}).sort("precio", -1).limit(5):
    print("  ", d)

print("\n3) Agregación: por categoría, cantidad, precio promedio y valor del inventario")
pipeline = [
    {"$group": {
        "_id": "$categoria",
        "productos": {"$sum": 1},
        "precio_promedio": {"$avg": "$precio"},
        "valor_inventario": {"$sum": {"$multiply": ["$precio", "$stock"]}},
    }},
    {"$sort": {"valor_inventario": -1}},
]
for d in col.aggregate(pipeline):
    print(f"   {d['_id']:<13} productos={d['productos']}  promedio={d['precio_promedio']:,.0f}  inventario={d['valor_inventario']:,.0f}")

cliente.close()
