"""
Controlador de failover (pilot-light).

Acionado pelo SNS quando o alarme CloudWatch do health check do
Route 53 deteta que a regiao primaria esta em baixo.

Faz duas coisas, sem qualquer clique na consola:
  1. Promove a read replica RDS a base de dados independente
     (deixa de depender da primaria que esta em baixo).
  2. Faz scale-up do Auto Scaling Group standby (0 -> N),
     arrancando as instancias da aplicacao na regiao secundaria.

O switch de DNS em si e automatico: o Route 53 tem registos de
failover (primary/secondary) e, assim que o health check falha,
deixa de resolver para a primaria e passa a resolver para o ALB
standby. Esta Lambda so trata do estado (base de dados + compute).
"""

import os
import boto3

STANDBY_REGION = os.environ["STANDBY_REGION"]
ASG_NAME = os.environ["STANDBY_ASG_NAME"]
DESIRED = int(os.environ["DESIRED_CAPACITY"])
REPLICA_ID = os.environ["REPLICA_IDENTIFIER"]


def handler(event, context):
    rds = boto3.client("rds", region_name=STANDBY_REGION)
    asg = boto3.client("autoscaling", region_name=STANDBY_REGION)

    # 1) Promover a replica (idempotente: se ja for standalone, ignora o erro)
    try:
        rds.promote_read_replica(DBInstanceIdentifier=REPLICA_ID)
        print(f"Replica {REPLICA_ID} promovida a primaria.")
    except rds.exceptions.InvalidDBInstanceStateFault:
        print(f"Replica {REPLICA_ID} ja esta promovida. Nada a fazer.")

    # 2) Arrancar o compute standby
    asg.set_desired_capacity(
        AutoScalingGroupName=ASG_NAME,
        DesiredCapacity=DESIRED,
        HonorCooldown=False,
    )
    print(f"ASG {ASG_NAME} escalado para {DESIRED} instancias.")

    return {"status": "failover-executado", "asg": ASG_NAME, "replica": REPLICA_ID}
