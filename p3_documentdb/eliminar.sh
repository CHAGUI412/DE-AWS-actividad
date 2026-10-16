#!/usr/bin/env bash
# Punto 3 - elimina DocumentDB, la EC2, la llave y la red
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-user_cli}
export AWS_DEFAULT_REGION=us-east-1
cd "$(dirname "$0")"
source estado_docdb.env

aws docdb delete-db-instance --db-instance-identifier de-aws-docdb-1 > /dev/null
aws ec2 terminate-instances --instance-ids $EC2 > /dev/null
aws docdb wait db-instance-deleted --db-instance-identifier de-aws-docdb-1
aws docdb delete-db-cluster --db-cluster-identifier de-aws-docdb --skip-final-snapshot > /dev/null
echo "esperando que se borre el cluster..."
while aws docdb describe-db-clusters --db-cluster-identifier de-aws-docdb > /dev/null 2>&1; do sleep 20; done
aws ec2 wait instance-terminated --instance-ids $EC2

aws docdb delete-db-subnet-group --db-subnet-group-name de-aws-docdb
aws ec2 delete-security-group --group-id $SG_DB
aws ec2 delete-security-group --group-id $SG_EC2
aws ec2 delete-key-pair --key-name de-aws-docdb
rm -f docdb-key.pem

echo "--- evidencia ---"
aws docdb describe-db-clusters --query "DBClusters[?starts_with(DBClusterIdentifier,'de-aws')].DBClusterIdentifier"
aws docdb describe-db-cluster-snapshots --query "DBClusterSnapshots[?starts_with(DBClusterIdentifier,'de-aws')].DBClusterSnapshotIdentifier"
aws ec2 describe-instances --instance-ids $EC2 --query 'Reservations[0].Instances[0].State.Name'
