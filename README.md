# CloudProjetoFinal

Projeto A

## Serviços

| Serviço | Porta | Descrição |
|---|---|---|
| api-gateway | 8080 | Encaminha pedidos |
| user-service | 8081 | Gestão de utilizadores |
| product-service | 8082 | Gestão de produtos e stock |
| order-service | 8083 | Criação de encomendas |

## Fluxo

1. Cliente cria encomenda → order-service
2. order-service valida utilizador e produto
3. order-service guarda encomenda no RDS
4. order-service publica mensagem no SQS
5. product-service consome mensagem e atualiza stock

## Deploy

Ver [docs/deployment.md](docs/deployment.md)
## Disaster Recovery (Epoca de Recurso)

Extensao de DR multi-regiao com failover automatico (padrao **pilot-light**).

- **Primaria:** `eu-west-1` (a servir) · **Standby:** `eu-central-1` (pilot-light)
- **Failover DNS:** Route 53 health check + registos primary/secondary
- **Dados:** read replica RDS cross-region, promovida por Lambda (RPO <= 5 min)
- **Automacao:** alarme CloudWatch -> SNS -> Lambda (promove replica + escala ASG)
- **Infra:** `infrastructure/terraform/environments/dr` + modulo reutilizavel `modules/region-stack`
- **Pipelines:** `.github/workflows/dr-plan.yml`, `dr-apply.yml`, `dr-drill.yml` (OIDC)
- **Runbook:** [docs/dr.md](docs/dr.md)
- **Guia de defesa (PT):** [GUIA_DEFESA_RECURSO.md](GUIA_DEFESA_RECURSO.md)
