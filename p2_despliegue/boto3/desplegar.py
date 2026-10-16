"""
Punto 2 - mismo despliegue que terraform pero con boto3.
    AWS_PROFILE=user_cli python desplegar.py
Guarda los ids en estado_boto3.json para que eliminar.py los use.
"""
import json
import time

import boto3

REGION = "us-east-1"
TAGS = [{"Key": "proyecto", "Value": "de-aws"}, {"Key": "metodo", "Value": "boto3"}]

sesion = boto3.Session(region_name=REGION)
ec2 = sesion.client("ec2")
rds = sesion.client("rds")
s3 = sesion.client("s3")
ssm = sesion.client("ssm")
cuenta = sesion.client("sts").get_caller_identity()["Account"]

estado = {}

# ---------- red ----------
vpc_id = ec2.describe_vpcs(Filters=[{"Name": "isDefault", "Values": ["true"]}])["Vpcs"][0]["VpcId"]
subnets = [s["SubnetId"] for s in ec2.describe_subnets(Filters=[{"Name": "vpc-id", "Values": [vpc_id]}])["Subnets"]]

sg_ec2 = ec2.create_security_group(GroupName="de-aws-b3-ec2", Description="SG EC2 punto 2 boto3", VpcId=vpc_id)["GroupId"]
sg_rds = ec2.create_security_group(GroupName="de-aws-b3-rds", Description="Postgres solo desde la EC2", VpcId=vpc_id)["GroupId"]
ec2.authorize_security_group_ingress(
    GroupId=sg_rds,
    IpPermissions=[{"IpProtocol": "tcp", "FromPort": 5432, "ToPort": 5432, "UserIdGroupPairs": [{"GroupId": sg_ec2}]}],
)
estado.update(sg_ec2=sg_ec2, sg_rds=sg_rds)
print("security groups:", sg_ec2, sg_rds)

rds.create_db_subnet_group(DBSubnetGroupName="de-aws-b3-subnets", DBSubnetGroupDescription="punto 2 boto3", SubnetIds=subnets)
estado["subnet_group"] = "de-aws-b3-subnets"

# ---------- S3 ----------
bucket = f"de-aws-p2-b3-{cuenta}"
s3.create_bucket(Bucket=bucket)  # en us-east-1 no se pasa LocationConstraint
s3.put_public_access_block(
    Bucket=bucket,
    PublicAccessBlockConfiguration={k: True for k in ["BlockPublicAcls", "IgnorePublicAcls", "BlockPublicPolicy", "RestrictPublicBuckets"]},
)
s3.put_bucket_tagging(Bucket=bucket, Tagging={"TagSet": TAGS})
estado["bucket"] = bucket
print("bucket:", bucket)

# ---------- EC2 ----------
ami = ssm.get_parameter(Name="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64")["Parameter"]["Value"]
inst = ec2.run_instances(
    ImageId=ami,
    InstanceType="t3.micro",
    MinCount=1,
    MaxCount=1,
    NetworkInterfaces=[{"DeviceIndex": 0, "SubnetId": subnets[0], "Groups": [sg_ec2], "AssociatePublicIpAddress": False}],
    BlockDeviceMappings=[{"DeviceName": "/dev/xvda", "Ebs": {"VolumeSize": 8, "VolumeType": "gp3"}}],
    TagSpecifications=[{"ResourceType": "instance", "Tags": TAGS + [{"Key": "Name", "Value": "de-aws-b3-ec2"}]}],
)["Instances"][0]["InstanceId"]
estado["ec2"] = inst
print("ec2:", inst)

# ---------- RDS ----------
rds.create_db_instance(
    DBInstanceIdentifier="de-aws-b3-rds",
    Engine="postgres",
    DBInstanceClass="db.t4g.micro",
    AllocatedStorage=20,
    StorageType="gp3",
    DBName="taller",
    MasterUsername="adminpg",
    ManageMasterUserPassword=True,  # RDS crea el secreto, aqui no hay contrasena
    DBSubnetGroupName="de-aws-b3-subnets",
    VpcSecurityGroupIds=[sg_rds],
    PubliclyAccessible=False,
    MultiAZ=False,
    BackupRetentionPeriod=0,
    DeletionProtection=False,
    Tags=TAGS,
)
estado["rds"] = "de-aws-b3-rds"

with open("estado_boto3.json", "w") as f:
    json.dump(estado, f, indent=2)

print("esperando EC2 y RDS (RDS tarda ~5-10 min)...")
t0 = time.time()
ec2.get_waiter("instance_running").wait(InstanceIds=[inst])
rds.get_waiter("db_instance_available").wait(DBInstanceIdentifier="de-aws-b3-rds")
db = rds.describe_db_instances(DBInstanceIdentifier="de-aws-b3-rds")["DBInstances"][0]
print(f"listo en {time.time() - t0:.0f} s")
print("endpoint:", db["Endpoint"]["Address"])
print("secreto de RDS:", db["MasterUserSecret"]["SecretArn"])
