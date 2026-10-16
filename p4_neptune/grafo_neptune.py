"""
Punto 4 - carga un grafo en Neptune y hace 3 consultas que recorren relaciones.
Se conecta al endpoint publico; boto3 (cliente neptunedata) firma cada consulta
con las credenciales IAM de user_cli, no hay contrasena.
    AWS_PROFILE=user_cli python grafo_neptune.py
"""
import boto3

REGION = "us-east-1"

endpoint = boto3.client("neptune", region_name=REGION).describe_db_clusters(
    DBClusterIdentifier="de-aws-neptune")["DBClusters"][0]["Endpoint"]
neptune = boto3.client("neptunedata", region_name=REGION, endpoint_url=f"https://{endpoint}:8182")


def cypher(query):
    return neptune.execute_open_cypher_query(openCypherQuery=query)["results"]


# limpiar por si se corre otra vez
cypher("MATCH (n) DETACH DELETE n")

# 10 vertices: 1 universidad, 2 profesores, 3 cursos, 4 estudiantes
# 18 relaciones
cypher("""
CREATE (eia:Universidad {nombre:'EIA'}),
       (p1:Profesor {nombre:'Santiago'}), (p2:Profesor {nombre:'Laura'}),
       (c1:Curso {nombre:'Ingeniería de Datos', creditos:3}),
       (c2:Curso {nombre:'Bases de Datos', creditos:3}),
       (c3:Curso {nombre:'Estadística', creditos:4}),
       (ana:Estudiante {nombre:'Ana', semestre:6}),
       (juan:Estudiante {nombre:'Juan', semestre:6}),
       (sofi:Estudiante {nombre:'Sofía', semestre:5}),
       (mateo:Estudiante {nombre:'Mateo', semestre:7}),
       (p1)-[:TRABAJA_EN]->(eia), (p2)-[:TRABAJA_EN]->(eia),
       (c1)-[:OFRECIDO_POR]->(eia), (c2)-[:OFRECIDO_POR]->(eia), (c3)-[:OFRECIDO_POR]->(eia),
       (p1)-[:DICTA]->(c1), (p1)-[:DICTA]->(c2), (p2)-[:DICTA]->(c3),
       (ana)-[:INSCRITO_EN {nota:4.5}]->(c1), (ana)-[:INSCRITO_EN {nota:4.0}]->(c3),
       (juan)-[:INSCRITO_EN {nota:3.8}]->(c1), (juan)-[:INSCRITO_EN {nota:4.2}]->(c2),
       (sofi)-[:INSCRITO_EN {nota:4.7}]->(c2), (sofi)-[:INSCRITO_EN {nota:3.5}]->(c3),
       (mateo)-[:INSCRITO_EN {nota:4.1}]->(c1),
       (ana)-[:AMIGO_DE]->(juan), (juan)-[:AMIGO_DE]->(sofi), (sofi)-[:AMIGO_DE]->(mateo)
""")

print("vertices:", cypher("MATCH (n) RETURN count(n) AS total")[0]["total"])
print("relaciones:", cypher("MATCH ()-[r]->() RETURN count(r) AS total")[0]["total"])

print("\n1) Compañeros de clase de Ana (estudiante -> curso <- estudiante)")
for r in cypher("""
    MATCH (a:Estudiante {nombre:'Ana'})-[:INSCRITO_EN]->(c:Curso)<-[:INSCRITO_EN]-(otro:Estudiante)
    RETURN otro.nombre AS companero, collect(c.nombre) AS cursos_en_comun
    ORDER BY companero"""):
    print("  ", r)

print("\n2) Estudiantes que tiene cada profesor y su nota promedio (profesor -> curso <- estudiante)")
for r in cypher("""
    MATCH (p:Profesor)-[:DICTA]->(c:Curso)<-[i:INSCRITO_EN]-(e:Estudiante)
    RETURN p.nombre AS profesor, count(DISTINCT e) AS estudiantes, round(avg(i.nota)*100)/100 AS nota_promedio
    ORDER BY profesor"""):
    print("  ", r)

print("\n3) Amigos de amigos de Ana que no son sus amigos directos (2 saltos de AMIGO_DE)")
for r in cypher("""
    MATCH (a:Estudiante {nombre:'Ana'})-[:AMIGO_DE]-(d:Estudiante)
    WITH a, collect(d) AS directos
    MATCH (a)-[:AMIGO_DE]-(x)-[:AMIGO_DE]-(fof:Estudiante)
    WHERE fof <> a AND NOT fof IN directos
    RETURN DISTINCT fof.nombre AS sugerido, x.nombre AS a_traves_de"""):
    print("  ", r)
