# Manual do Zero - Recurso Cloud (Disaster Recovery)

> Assumindo que **nunca fizeste nada disto**. Segue as PARTES por ordem, de cima
> a baixo, sem saltar. Cada comando esta pronto a copiar. Onde vês `<...>` tens de
> substituir pelo teu valor. Reserva ~2-3 horas na primeira vez.

## O que vais ter no fim
Uma aplicacao que corre em `eu-west-1` (Irlanda) e que, se essa regiao cair,
salta sozinha para `eu-central-1` (Frankfurt), sem tu clicares em nada. Tudo
criado por codigo (Terraform) e por pipeline (GitHub Actions).

## Mapa das PARTES
0. Custos e avisos
1. Criar contas e instalar ferramentas
2. Preparar a AWS pela primeira vez (utilizador + CLI + "cofre" do Terraform)
3. Ligar o GitHub à AWS por OIDC (sem passwords)
4. Domínio + Route 53
5. Docker Hub (imagens da app)
6. Pôr o código no GitHub e configurar os secrets
7. Primeiro deploy: infraestrutura DR
8. Correr o drill e medir o RTO (o que mostras na defesa)
9. Limpar tudo no fim (para não pagar)
10. Resolução de problemas
11. Checklist do dia da defesa

---

# PARTE 0 - Custos e avisos

- A AWS tem **Free Tier**, mas este projeto cria **RDS (2x), ALB (2x), NAT/EC2**.
  Isto **gasta dinheiro** se ficar ligado dias. Regra de ouro: **cria, testa,
  demonstra, e faz `destroy` no mesmo dia**. Ver PARTE 9.
- Estimativa se deixares ligado 1 dia inteiro: poucos euros. Se esqueceres ligado
  um mês: dezenas de euros. **Não esqueças ligado.**
- Precisas de **um domínio** (custo único ~3-5 €/ano) para o failover de DNS
  funcionar. Explico na PARTE 4. É a única compra obrigatória.

---

# PARTE 1 - Criar contas e instalar ferramentas

### 1.1 Contas (se ainda não tens)
- **AWS**: https://aws.amazon.com -> "Create an AWS Account". Precisa de cartão.
- **GitHub**: https://github.com -> conta gratuita.
- **Docker Hub**: https://hub.docker.com -> conta gratuita.

### 1.2 Instalar ferramentas no teu PC
Vais precisar de 4 programas: **Git**, **AWS CLI**, **Terraform**, **Docker**.

**Windows** - abre o **PowerShell como Administrador** (tecla Windows -> escreve
`PowerShell` -> clica com o botão direito -> *Executar como administrador*) e cola:
```powershell
winget install Git.Git
winget install Amazon.AWSCLI
winget install Hashicorp.Terraform
winget install Docker.DockerDesktop
```

**macOS (com Homebrew):**
```bash
brew install git awscli terraform
brew install --cask docker
```

### 1.3 Confirmar que ficou tudo instalado
Fecha e reabre o terminal, e corre:
```bash
git --version
aws --version
terraform version
docker --version
```
Se cada um responde com um número de versão, estás pronto.

### 1.4 IMPORTANTE: onde vais escrever os comandos a partir de agora

Da PARTE 2 em diante, os comandos correm num **terminal do teu computador**
(NÃO no IntelliJ, NÃO na consola da AWS no browser). É uma janela onde escreves
texto e carregas Enter.

**No Windows usa o `Git Bash`** (foi instalado junto com o Git na PARTE 1):
- Tecla Windows -> escreve `Git Bash` -> Enter. Abre uma janela que acaba em `$`.
- Colar no Git Bash: **botão direito do rato -> Paste** (ou Shift+Insert).

Porquê Git Bash e não o CMD/PowerShell? Porque os comandos aqui usam a barra `\`
para partir linhas. Isso funciona no Git Bash tal como está escrito, mas parte no
PowerShell/CMD. Usando Git Bash, copias e colas sem pensar.

**No macOS** usa a app **Terminal** (Cmd+Espaço -> escreve `Terminal` -> Enter).

> Resumo: `winget` da PARTE 1.2 = PowerShell (só Windows). Tudo o resto (PARTE 2+)
> = **Git Bash** (Windows) ou **Terminal** (Mac). É sempre no teu PC.


---

# PARTE 2 - Preparar a AWS pela primeira vez

> **Onde:** todos os comandos desta PARTE correm no **Git Bash** (Windows) ou no
> **Terminal** (Mac), no teu computador. Ver a PARTE 1.4 se tiveres dúvidas.
> Alguns passos são cliques na **consola da AWS** (no browser) - digo sempre qual é qual.

### 2.1 Criar um utilizador com permissões (IAM)  ->  [na CONSOLA AWS, no browser]
Não uses a conta "root" para o dia a dia. Cria um utilizador:

1. Entra na consola AWS -> pesquisa **IAM** -> **Users** -> **Create user**.
2. Nome: `admin-cli`. **Next**.
3. **Attach policies directly** -> marca **AdministratorAccess**. **Next** -> **Create user**.
4. Clica no utilizador criado -> separador **Security credentials** ->
   **Create access key** -> escolhe **Command Line Interface (CLI)** -> **Create**.
5. **Copia** a `Access key ID` e a `Secret access key` (só aparece uma vez).

### 2.2 Configurar a AWS CLI no teu PC  ->  [no Git Bash / Terminal]
```bash
aws configure
```
Cola quando pedir:
- `AWS Access Key ID`: <a que copiaste>
- `AWS Secret Access Key`: <a que copiaste>
- `Default region name`: `eu-west-1`
- `Default output format`: `json`

Testa:
```bash
aws sts get-caller-identity
```
Se aparecer o teu número de conta (Account), está ligado.

### 2.3 Descobrir o teu Account ID (guarda-o)  ->  [no Git Bash / Terminal]
```bash
aws sts get-caller-identity --query Account --output text
```
Vais precisar deste número (12 dígitos) mais à frente. Chama-lhe `<ACCOUNT_ID>`.

### 2.4 Criar o "cofre" do Terraform (S3 + DynamoDB)  ->  [no Git Bash / Terminal]
O Terraform guarda o estado num bucket S3 e usa uma tabela DynamoDB para não
haver dois deploys ao mesmo tempo. **Estes nomes têm de bater certo** com o que
está escrito no código (`providers.tf`). Corre:

```bash
# Bucket para o estado do Terraform
aws s3api create-bucket \
  --bucket cloudprojetofinal-tf-state-eu-west-1 \
  --region eu-west-1 \
  --create-bucket-configuration LocationConstraint=eu-west-1

# Ativar versionamento (boa prática)
aws s3api put-bucket-versioning \
  --bucket cloudprojetofinal-tf-state-eu-west-1 \
  --versioning-configuration Status=Enabled

# Tabela DynamoDB para os "locks"
aws dynamodb create-table \
  --table-name cloudprojetofinal-tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-west-1
```
> Se o nome do bucket "já existe", muda o nome AQUI e também em
> `infrastructure/terraform/environments/dr/providers.tf` (campo `bucket`).

---

# PARTE 3 - Ligar o GitHub à AWS por OIDC (sem passwords)

O enunciado EXIGE OIDC (o GitHub autentica-se na AWS sem guardar chaves). Fazes
isto uma vez.

### 3.1 Criar o "provedor OIDC" do GitHub na AWS
```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```
> Se disser que "já existe", ótimo, avança.

### 3.2 Criar o papel (Role) que o GitHub vai assumir
Cria um ficheiro `trust.json` no teu PC (substitui `<ACCOUNT_ID>` e o teu
`<UTILIZADOR>/<REPO>` do GitHub):

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": { "token.actions.githubusercontent.com:sub": "repo:<UTILIZADOR>/<REPO>:*" }
    }
  }]
}
```

Cria o papel e dá-lhe permissões:
```bash
aws iam create-role \
  --role-name github-actions-dr \
  --assume-role-policy-document file://trust.json

aws iam attach-role-policy \
  --role-name github-actions-dr \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```
> `AdministratorAccess` é largo, mas simplifica o projeto de escola. Guarda o ARN
> do papel que aparece no output (`arn:aws:iam::<ACCOUNT_ID>:role/github-actions-dr`).
> Chama-lhe `<ROLE_ARN>`.

---

# PARTE 4 - Domínio + Route 53

O failover é feito por **DNS**, logo precisas de um domínio gerido pela Route 53.

### 4.1 Registar um domínio barato (recomendado)
1. Consola AWS -> **Route 53** -> **Registered domains** -> **Register domains**.
2. Procura um barato (ex: `.click`, `.link` ~3-5 €/ano). Regista.
3. Ao registar, a AWS cria automaticamente uma **Hosted Zone** para esse domínio.

### 4.2 Ir buscar o Hosted Zone ID
```bash
aws route53 list-hosted-zones \
  --query "HostedZones[].{Name:Name,Id:Id}" --output table
```
Guarda o `Id` (formato `Z0123...`) -> chama-lhe `<HOSTED_ZONE_ID>`, e o nome do
domínio, ex: `app.oteudominio.click` -> chama-lhe `<DOMINIO>`.

> Alternativa sem comprar: se já tens um domínio noutro sítio, cria uma Hosted
> Zone na Route 53 e aponta os nameservers do teu domínio para os da AWS. Dá mais
> trabalho; comprar na Route 53 é o caminho mais simples.

---

# PARTE 5 - Docker Hub (imagens da app)

As instâncias arrancam um contentor Docker do api-gateway. A imagem tem de existir
no Docker Hub.

### 5.1 Criar um token
Docker Hub -> **Account Settings** -> **Security** -> **New Access Token** ->
copia o token (chama-lhe `<DOCKERHUB_TOKEN>`) e o teu username (`<DOCKERHUB_USERNAME>`).

### 5.2 Confirmar o nome da imagem
No código, as instâncias puxam `cloudprojetofinal/api-gateway:latest`. Muda para
o **teu** username em `infrastructure/terraform/modules/region-stack/variables.tf`
(variável `app_image`, default), OU garante que o pipeline de CI publica com esse
nome. Mais simples: edita o default para `"<DOCKERHUB_USERNAME>/api-gateway:latest"`.

---

# PARTE 6 - Pôr o código no GitHub e configurar os secrets

### 6.1 Onde ficam os ficheiros
**Já está tudo no sítio certo** dentro da pasta `CloudProjetoFinal-main` que te
entreguei. Não precisas de mover nada. A estrutura relevante do recurso é:

```
CloudProjetoFinal-main/
├── .github/workflows/
│   ├── dr-plan.yml      <- terraform plan em cada Pull Request
│   ├── dr-apply.yml     <- terraform apply ao fazer merge para main
│   └── dr-drill.yml     <- botão que simula a falha e mede o RTO
├── infrastructure/terraform/
│   ├── modules/
│   │   ├── region-stack/         <- módulo reutilizável (rede+ALB+ASG)
│   │   └── failover-controller/  <- Lambda + alarme que faz o failover
│   └── environments/dr/
│       ├── main.tf, providers.tf, variables.tf, outputs.tf
│       ├── ci.tfvars             <- valores não-secretos (edita aqui!)
│       └── lambda/failover.py    <- código da Lambda
├── docs/dr.md                    <- runbook
├── GUIA_DEFESA_RECURSO.md        <- para estudares a defesa
└── MANUAL_DO_ZERO.md             <- este ficheiro
```

### 6.2 Editar os teus valores
Abre `infrastructure/terraform/environments/dr/ci.tfvars` e mete os teus:
```hcl
project        = "cloudprojetofinal"
primary_region = "eu-west-1"
standby_region = "eu-central-1"
domain_name    = "<DOMINIO>"          # ex: app.oteudominio.click
hosted_zone_id = "<HOSTED_ZONE_ID>"   # ex: Z0123456789ABCDEFGHIJ
```

### 6.3 Enviar o código para o GitHub
Cria um repositório vazio no GitHub (ex: `cloud-recurso`). Depois, no terminal,
dentro da pasta `CloudProjetoFinal-main`:
```bash
git init
git add .
git commit -m "Projeto recurso: DR multi-regiao"
git branch -M main
git remote add origin https://github.com/<UTILIZADOR>/<REPO>.git
git push -u origin main
```

### 6.4 Configurar os secrets do GitHub
No GitHub: **Settings** do repo -> **Secrets and variables** -> **Actions** ->
**New repository secret**. Cria estes:

| Nome do secret | Valor |
|---|---|
| `AWS_ROLE_TO_ASSUME` | `<ROLE_ARN>` (da PARTE 3.2) |
| `DB_PASSWORD` | uma password forte à tua escolha (ex: `Recurso2026!Cloud`) |
| `PROJECT` | `cloudprojetofinal` |
| `DOCKERHUB_USERNAME` | `<DOCKERHUB_USERNAME>` |
| `DOCKERHUB_TOKEN` | `<DOCKERHUB_TOKEN>` |

### 6.5 Criar o "Environment" com aprovação
O enunciado pede que o apply seja "gated by an environment approval":
1. GitHub -> **Settings** -> **Environments** -> **New environment** -> nome `production`.
2. Marca **Required reviewers** e adiciona-te a ti. **Save**.

---

# PARTE 7 - Primeiro deploy da infraestrutura DR

Tens duas formas. Faz a **7A (local)** na primeira vez, para veres tudo a correr
à tua frente; a **7B (pipeline)** é o que a cadeira quer ver.

### 7A - Deploy local (primeira vez, para aprenderes)
```bash
cd infrastructure/terraform/environments/dr

# Arranca o Terraform e liga-o ao "cofre" S3
terraform init

# Cria um ficheiro terraform.tfvars com os teus valores + password
cp terraform.tfvars.example terraform.tfvars
#  edita terraform.tfvars: mete domain_name, hosted_zone_id e db_password

# Ver o que vai criar (não cria nada ainda)
terraform plan

# Criar mesmo (demora ~10-15 min por causa das bases de dados)
terraform apply
#  escreve 'yes' quando pedir
```
No fim, o Terraform imprime os outputs (DNS dos ALBs, endpoints das BDs, etc.).

### 7B - Deploy pela pipeline (o que demonstras)
1. Faz uma alteração qualquer, um commit, e um **Pull Request** para `main`.
   -> O workflow **DR Plan** corre sozinho e mostra o `terraform plan`.
2. Faz **merge** do PR para `main`.
   -> O workflow **DR Apply** arranca e **pára à espera da tua aprovação**
   (por causa do Environment `production`). Aprova em **Actions**.
   -> O Terraform aplica às duas regiões.

> A password: no pipeline ela vem do secret `DB_PASSWORD` (variável
> `TF_VAR_db_password`) e é guardada no **SSM Parameter Store**, nunca no código.

---

# PARTE 8 - Correr o drill e medir o RTO

Isto é o que **tens mesmo de mostrar ao vivo** na defesa.

1. GitHub -> **Actions** -> **DR Drill** -> **Run workflow**.
2. No campo `confirm`, escreve exatamente `SIM`. **Run**.
3. O workflow:
   - baixa o ASG da primária a 0 (simula a região a cair);
   - o health check da Route 53 começa a falhar;
   - a Lambda promove a réplica e arranca o standby;
   - o workflow fica a chamar o `<DOMINIO>/actuator/health` até dar `200`;
   - imprime no resumo o **RTO medido** (em segundos).
4. Abre a execução -> **Summary** -> lê o "RTO medido". Esse é o teu número real.

> Treina isto **pelo menos uma vez antes da defesa**. Anota o RTO. Se o professor
> perguntar "qual é o teu RTO?", respondes com o número medido, não inventado.

Para confirmares a olho que o standby está a servir:
```bash
curl -i http://<DOMINIO>/actuator/health
```

---

# PARTE 9 - Limpar tudo no fim (MUITO IMPORTANTE)

Para **não pagares** depois da demo:
```bash
cd infrastructure/terraform/environments/dr
terraform destroy
#  escreve 'yes'
```
Confirma na consola (EC2, RDS, ELB) que não ficou nada ligado nas duas regiões
(`eu-west-1` e `eu-central-1`).

> Se destruíres, para voltar a demonstrar é só correr `terraform apply` outra vez.

---

# PARTE 10 - Resolução de problemas

**"Error: bucket already exists"** (PARTE 2.4)
O nome do bucket S3 é global. Escolhe outro nome e mete-o também no `providers.tf`.

**O health check nunca fica verde / o drill nunca dá 200**
- Confirma que a imagem `<DOCKERHUB_USERNAME>/api-gateway:latest` existe no Docker Hub.
- Confirma que o api-gateway responde em `/actuator/health` (já está configurado).
- Vê os logs da Lambda: `aws logs tail /aws/lambda/cloudprojetofinal-failover-controller --region us-east-1 --follow`.

**"NoCredentialProviders" / OIDC falha no GitHub**
- O `sub` no `trust.json` tem de ser `repo:<UTILIZADOR>/<REPO>:*` exatamente.
- Confirma o secret `AWS_ROLE_TO_ASSUME`.

**RDS replica demora muito**
Normal: criar bases de dados demora 10-15 min. Tem paciência no primeiro apply.

**Custos a subir**
Corre o `terraform destroy` (PARTE 9). Verifica também a **Billing** na consola.

---

# PARTE 11 - Checklist do dia da defesa

- [ ] `terraform apply` feito e a app responde em `http://<DOMINIO>/actuator/health`.
- [ ] Corri o **DR Drill** e sei o meu **RTO medido** (número).
- [ ] Sei explicar RTO vs RPO (ver GUIA_DEFESA_RECURSO.md, secção 2).
- [ ] Sei porque escolhi **pilot-light** (custo) e o trade-off.
- [ ] Sei apontar no código: módulo reutilizável, OIDC, SSM, Lambda, Route 53.
- [ ] Tenho o `terraform destroy` pronto para correr depois da demo.

Segue as PARTES por ordem e não falha. Se travares num passo, diz-me o número da
PARTE e a mensagem de erro exata que apareceu.
