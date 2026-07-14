# Limitações

- Ambiente `dev`: single-AZ, sem load balancer — cada instância corre uma
  cópia completa dos 4 serviços, sem verdadeira distribuição de carga
- Ambiente `dev`: IPs públicos dos EC2s mudam ao reiniciar (sem Elastic IP)
- Ambiente `dr`: resiliente a queda de AZ e de região inteira (ver `docs/dr.md`),
  mas só corre o `api-gateway` — não replica os 4 serviços do `dev`
- Swagger UI não funciona em produção
- Porta SSH aberta para 0.0.0.0/0 (aceitável para projeto académico de curta
  duração; produção real usaria um bastion host ou SSM Session Manager)