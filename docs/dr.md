# Runbook de Disaster Recovery (DR)

Este documento descreve como **despoletar**, **observar** e **reverter** um
failover entre a regiao primaria e a regiao standby do projeto.

## Visao geral

| Item | Valor |
|---|---|
| Padrao de standby | **Pilot-light** (standby ligado ao minimo, arranca no failover) |
| Regiao primaria | `eu-west-1` |
| Regiao standby | `eu-central-1` |
| Failover de DNS | Route 53 health check + registos primary/secondary |
| Promocao de dados | Read replica RDS cross-region, promovida por Lambda |
| **RTO alvo** | **<= 10 minutos** |
| **RPO alvo** | **<= 5 minutos** (replicacao assincrona do RDS) |

## Como funciona (resumo)

1. Em operacao normal, o Route 53 resolve o dominio para o ALB da **primaria**.
2. Um **health check** do Route 53 chama `GET /actuator/health` na primaria a cada 30s.
3. Se falhar 3 vezes seguidas, a primaria e marcada como *unhealthy*:
   - o Route 53 passa automaticamente a resolver para o ALB **standby**;
   - um **alarme CloudWatch** (em `us-east-1`) dispara e publica num topico SNS;
   - a **Lambda `failover-controller`** e invocada e faz, sem cliques na consola:
     - `PromoteReadReplica` -> a replica RDS torna-se base de dados independente;
     - `SetDesiredCapacity` -> o Auto Scaling Group standby sobe de `0` para `2`.
4. Passado ~1-2 min as instancias standby ficam *healthy* e servem trafego.

## Despoletar um failover (drill)

### Opcao A - pelo pipeline (recomendado)

1. GitHub -> **Actions** -> **DR Drill** -> **Run workflow**.
2. No campo `confirm`, escrever `SIM`.
3. O workflow reduz o ASG primario a `0` (simula queda da regiao), espera a
   recuperacao e imprime o **RTO medido** no resumo da execucao.

### Opcao B - manual (linha de comandos)

```bash
# Simular queda da primaria
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name cloudprojetofinal-primary-asg \
  --min-size 0 --desired-capacity 0 --region eu-west-1
```

## Observar o failover

```bash
# Estado do health check (1 = saudavel, 0 = em baixo)
aws cloudwatch get-metric-statistics --namespace AWS/Route53 \
  --metric-name HealthCheckStatus --region us-east-1 \
  --dimensions Name=HealthCheckId,Value=<HC_ID> \
  --start-time $(date -u -d '-10 min' +%FT%TZ) --end-time $(date -u +%FT%TZ) \
  --period 60 --statistics Minimum

# Logs da Lambda de failover
aws logs tail /aws/lambda/cloudprojetofinal-failover-controller --region us-east-1 --follow

# Confirmar que o standby esta a responder
curl -i http://app.exemplo.com/actuator/health
```

## Reverter (voltar a primaria)

O drill ja repoe o ASG primario no fim (`desired-capacity 2`). Para reverter
manualmente apos um failover real:

```bash
# 1. Repor as instancias da primaria
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name cloudprojetofinal-primary-asg \
  --min-size 0 --desired-capacity 2 --region eu-west-1

# 2. Esperar o health check ficar verde -> o Route 53 volta sozinho a primaria
```

> Nota: depois de a replica ter sido **promovida**, deixa de estar ligada a
> primaria. Para voltar ao estado original e preciso recriar a relacao de
> replicacao com `terraform apply` (a replica e reprovisionada a partir da
> primaria restaurada). Isto e aceitavel porque o objetivo do DR e sobreviver
> a falha, nao manter as duas bases sincronizadas para sempre.

## RTO e RPO - numeros

| Metrica | Alvo | Como e medido |
|---|---|---|
| **RTO** (tempo ate recuperar) | <= 10 min | Cronometrado pelo workflow `DR Drill` (t0 = queda, t1 = primeiro `200`) |
| **RPO** (perda maxima de dados) | <= 5 min | Lag de replicacao assincrona do RDS (`ReplicaLag` no CloudWatch) |

O RPO nao e zero porque a replicacao e **assincrona**: transacoes confirmadas na
primaria nos segundos anteriores a falha podem nao ter chegado a replica. Este
e o trade-off consciente do padrao pilot-light - custo baixo em troca de um RPO
de poucos minutos.
