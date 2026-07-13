# Como pôr o Claude Code a fazer o projeto por ti

Este ficheiro tem 3 partes:
- **PARTE A** - o que só TU podes fazer (antes de chamar o Claude Code)
- **PARTE B** - a tabela de valores que precisas de ter à mão
- **PARTE C** - o prompt para colar no Claude Code (ele faz o resto)

O Claude Code é uma ferramenta que corre no teu terminal, dentro da pasta do
projeto, e sabe correr comandos (aws, terraform, git, gh). A ideia: ele executa
tudo o que é automatizável e PÁRA para te avisar sempre que for preciso um clique
teu.

---

# PARTE A - O que SÓ TU podes fazer (manual)

Estas coisas exigem uma pessoa (cartão, cliques, decisões). Faz por esta ordem:

1. **Ter conta AWS com pagamento ativo** (https://aws.amazon.com).
2. **Criar um utilizador IAM com AdministratorAccess e gerar Access Keys**
   (consola AWS -> IAM -> Users). É isto que dá "mãos" ao Claude Code na AWS.
   > Já geraste uma chave antes. Se a partilhaste, apaga-a no fim e usa uma nova.
3. **Configurar as chaves no PC**: no Git Bash corre `aws configure` e mete a
   Access Key, a Secret Key, região `eu-west-1`, formato `json`.
   - Confirma com `aws sts get-caller-identity`. **Tem de responder com o teu
     número de conta.** Se der erro de rede (resposta vazia/XML), liga o PC ao
     hotspot do telemóvel ou desliga VPN/proxy e tenta de novo. **Não avances sem
     este passo a funcionar** - o Claude Code precisa dele.
4. **Instalar o GitHub CLI** e autenticar: `winget install GitHub.cli` (PowerShell),
   depois no Git Bash `gh auth login` (escolhe GitHub.com -> HTTPS -> autentica no
   browser). Isto deixa o Claude Code criar o repo e os secrets por ti.
5. **Registar um domínio na Route 53** (consola AWS -> Route 53 -> Register domains,
   ~3-5 €/ano num `.click`). Isto é uma COMPRA, tem de ser tu. Guarda o nome.
6. **Instalar o Claude Code** (se ainda não tens): segue https://claude.com/claude-code
   e abre-o dentro da pasta do projeto (`CloudProjetoFinal-main`).

Durante a execução, o Claude Code vai PARAR e pedir-te 2 cliques:
- **Aprovar o deploy** no GitHub (Environment `production`).
- **Confirmar o drill** (correr o workflow / escrever `SIM`).

---

# PARTE B - Valores para teres à mão

Preenche isto num papel/bloco de notas antes de começar:

| O que | Onde obténs | O teu valor |
|---|---|---|
| Account ID (12 dígitos) | `aws sts get-caller-identity` | ____________ |
| Utilizador/repo GitHub | o teu GitHub | ____________ / ____________ |
| Nome do domínio | Route 53 (PARTE A.5) | ____________ |
| Password do RDS (inventa) | à tua escolha, forte | ____________ |
| Docker Hub user + token | hub.docker.com -> Security | ____________ |

O Claude Code descobre o resto sozinho (Hosted Zone ID, Role ARN, etc.).

---

# PARTE C - Prompt para colar no Claude Code

Abre o Claude Code na pasta do projeto e cola exatamente isto (só muda as linhas
"OS MEUS DADOS" com os teus valores):

---

Estás na raiz do meu projeto de recurso de Cloud. O objetivo é uma capacidade de
Disaster Recovery multi-região (pilot-light) já implementada em
`infrastructure/terraform/environments/dr` e nos workflows `.github/workflows/dr-*.yml`.
Lê primeiro `MANUAL_DO_ZERO.md`, `docs/dr.md` e `infrastructure/terraform/environments/dr/`
para perceberes o que já existe. NÃO reescrevas a arquitetura; só a fazes funcionar.

OS MEUS DADOS:
- Região primária: eu-west-1 | Região standby: eu-central-1
- Domínio (já registado por mim na Route 53): <O_MEU_DOMINIO>
- GitHub repo: <UTILIZADOR>/<REPO>
- Docker Hub username: <DOCKERHUB_USERNAME>

Faz o seguinte, por ordem, e PÁRA a pedir-me confirmação em cada ponto marcado [MANUAL]:

1. Verifica os pré-requisitos: corre `aws sts get-caller-identity`, `terraform version`,
   `gh auth status`. Se algum falhar, diz-me exatamente o que corrigir e para.
2. Bootstrap do backend (idempotente): cria, se ainda não existirem, o bucket S3
   `cloudprojetofinal-tf-state-eu-west-1` (com versioning) e a tabela DynamoDB
   `cloudprojetofinal-tf-locks`. Se o nome do bucket estiver ocupado, escolhe um
   único, atualiza `providers.tf` em conformidade e diz-me qual usaste.
3. OIDC: cria (se não existir) o OIDC provider do GitHub e um role `github-actions-dr`
   que confia no repo <UTILIZADOR>/<REPO>, com AdministratorAccess. Imprime o Role ARN.
4. Descobre o Hosted Zone ID do meu domínio com a AWS CLI e preenche
   `infrastructure/terraform/environments/dr/ci.tfvars` com project, regiões,
   domain_name e hosted_zone_id. Confirma que o `app_image` no módulo region-stack
   aponta para <DOCKERHUB_USERNAME>/api-gateway:latest; se não, corrige.
5. [MANUAL] Pede-me a password do RDS. Guarda-a como secret do GitHub `DB_PASSWORD`
   via `gh secret set` (nunca em ficheiro). Define também os secrets
   AWS_ROLE_TO_ASSUME (o ARN do passo 3), PROJECT=cloudprojetofinal,
   DOCKERHUB_USERNAME e DOCKERHUB_TOKEN (pede-me o token).
6. Cria o Environment `production` do GitHub com required reviewers = eu, se possível
   via API; se não for possível por CLI, diz-me os cliques exatos para o fazer.
7. Git: inicializa o repo se preciso, faz commit e push para main em <UTILIZADOR>/<REPO>.
8. Deploy local de validação: em `environments/dr` corre `terraform init`,
   `terraform validate`, `terraform fmt -check -recursive ../../` e `terraform plan`
   (usa TF_VAR_db_password com a password que te dei, em memória). Mostra-me o resumo
   do plan e ESPERA a minha autorização antes de `terraform apply`.
9. [MANUAL] Quando eu autorizar, corre `terraform apply`. Depois confirma que
   `http://<O_MEU_DOMINIO>/actuator/health` responde 200 (pode demorar pelas RDS).
10. [MANUAL] Drill: dispara o workflow `DR Drill` (com input confirm=SIM) via
    `gh workflow run`, acompanha a execução e diz-me o RTO medido no summary.
11. No fim, lembra-me de correr `terraform destroy` para não ter custos, e de
    apagar/rotacionar a access key que usei.

Regras: nunca escrevas segredos em ficheiros versionados; usa OIDC no pipeline e
SSM para a password; explica-me em português simples o que fizeste em cada passo.

---

# Depois de tudo

- Estuda o `GUIA_DEFESA_RECURSO.md` para a apresentação oral.
- Corre `terraform destroy` quando não estiveres a demonstrar.
- Vai a IAM e **apaga a access key** que usaste (segurança).
