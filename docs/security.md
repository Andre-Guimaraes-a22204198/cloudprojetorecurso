# Segurança

- GitHub Actions usa OIDC — sem credenciais hardcoded
- RDS em subnet privada (ambiente `dr`), só acessível pelas instâncias da app
- Role do GitHub Actions (`github-actions-dr`) usa uma policy customizada
  escopada aos serviços que o Terraform realmente gere (EC2, ELB, RDS,
  Route53, Lambda, SNS, SQS, SSM, CloudWatch, backend S3/DynamoDB) — não usa
  `AdministratorAccess`
- Instâncias EC2 do ambiente `dev` têm uma IAM instance role dedicada, limitada
  a `sqs:SendMessage`/`ReceiveMessage`/`DeleteMessage`/`GetQueueAttributes`
  apenas nas filas do projeto
- Secrets geridos via GitHub Secrets e AWS SSM Parameter Store (`SecureString`),
  nunca hardcoded no código ou nos templates