#!/usr/bin/env bash
# Punto 4 - elimina Neptune y su red
set -euo pipefail
export AWS_PROFILE=${AWS_PROFILE:-user_cli}
export AWS_DEFAULT_REGION=us-east-1
cd "$(dirname "$0")"
source estado_neptune.env

aws neptune delete-db-instance --db-instance-identifier de-aws-neptune-1 > /dev/null
aws neptune wait db-instance-deleted --db-instance-identifier de-aws-neptune-1
aws neptune delete-db-cluster --db-cluster-identifier de-aws-neptune --skip-final-snapshot > /dev/null
echo "esperando que se borre el cluster..."
while aws neptune describe-db-clusters --db-cluster-identifier de-aws-neptune > /dev/null 2>&1; do sleep 20; done

aws neptune delete-db-subnet-group --db-subnet-group-name de-aws-neptune
aws ec2 delete-security-group --group-id $SG

echo "--- evidencia ---"
aws neptune describe-db-clusters --query "DBClusters[?starts_with(DBClusterIdentifier,'de-aws')].DBClusterIdentifier"
aws neptune describe-db-cluster-snapshots --query "DBClusterSnapshots[?starts_with(DBClusterIdentifier,'de-aws')].DBClusterSnapshotIdentifier"
