"""Punto 2 - elimina lo que creo desplegar.py, en orden inverso."""
import json

import boto3

sesion = boto3.Session(region_name="us-east-1")
ec2 = sesion.client("ec2")
rds = sesion.client("rds")
s3 = sesion.resource("s3")

with open("estado_boto3.json") as f:
    e = json.load(f)

# RDS y EC2 primero (los SG no se pueden borrar mientras esten en uso)
rds.delete_db_instance(DBInstanceIdentifier=e["rds"], SkipFinalSnapshot=True, DeleteAutomatedBackups=True)
ec2.terminate_instances(InstanceIds=[e["ec2"]])
print("esperando que terminen EC2 y RDS...")
ec2.get_waiter("instance_terminated").wait(InstanceIds=[e["ec2"]])
rds.get_waiter("db_instance_deleted").wait(DBInstanceIdentifier=e["rds"])

rds.delete_db_subnet_group(DBSubnetGroupName=e["subnet_group"])
ec2.delete_security_group(GroupId=e["sg_rds"])
ec2.delete_security_group(GroupId=e["sg_ec2"])

b = s3.Bucket(e["bucket"])
b.objects.all().delete()
b.delete()

# evidencia: no debe quedar nada con la etiqueta metodo=boto3
print("instancias RDS restantes:", [d["DBInstanceIdentifier"] for d in rds.describe_db_instances()["DBInstances"] if d["DBInstanceIdentifier"].startswith("de-aws-b3")])
vivas = ec2.describe_instances(Filters=[{"Name": "tag:metodo", "Values": ["boto3"]}, {"Name": "instance-state-name", "Values": ["pending", "running", "stopped"]}])
print("EC2 restantes:", [i["InstanceId"] for r in vivas["Reservations"] for i in r["Instances"]])
print("buckets restantes:", [x.name for x in s3.buckets.all() if x.name.startswith("de-aws-p2-b3")])
