# Deployment


Bash:

cd infrastructure/terraform/environments/dev
terraform init && terraform apply


O CI/CD faz deploy automático a cada push para o main.

Para destruir: terraform destroy