"""
Punto 1 - lee el secreto de prueba con boto3.
Corre con el perfil del rol que solo puede leer ese secreto:
    AWS_PROFILE=lector-p1 python leer_secreto.py
    AWS_PROFILE=lector-p1 python leer_secreto.py --veces 5 --cache 60
"""
import argparse
import json
import time

import boto3

SECRET_ID = "de-aws/p1/demo"
cliente = boto3.client("secretsmanager", region_name="us-east-1")

# cache muy simple en memoria: valor + momento en que se leyo
_cache = {"valor": None, "leido_en": 0.0}
llamadas_api = 0


def leer_secreto(ttl=0):
    """Si ttl > 0 reutiliza el valor guardado mientras no haya vencido."""
    global llamadas_api
    ahora = time.time()
    if ttl > 0 and _cache["valor"] and ahora - _cache["leido_en"] < ttl:
        return _cache["valor"]

    resp = cliente.get_secret_value(SecretId=SECRET_ID)  # siempre trae AWSCURRENT
    llamadas_api += 1
    valor = json.loads(resp["SecretString"])
    valor["_version"] = resp["VersionId"]
    _cache["valor"], _cache["leido_en"] = valor, ahora
    return valor


def ocultar(texto):
    # para las capturas: solo se ven los 2 primeros caracteres
    return texto[:2] + "*" * (len(texto) - 2)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--veces", type=int, default=1)
    p.add_argument("--cache", type=int, default=0, help="segundos de cache, 0 = sin cache")
    args = p.parse_args()

    for i in range(args.veces):
        s = leer_secreto(ttl=args.cache)
        print(f"lectura {i+1}: usuario={s['username']} password={ocultar(s['password'])} version={s['_version'][:8]}")
        time.sleep(1)

    print(f"\nllamadas reales a la API: {llamadas_api} de {args.veces} lecturas")

    # prueba de que el rol no puede leer otros secretos
    try:
        cliente.get_secret_value(SecretId="de-aws/otro-secreto")
    except cliente.exceptions.ClientError as e:
        print("leer otro secreto ->", e.response["Error"]["Code"])
