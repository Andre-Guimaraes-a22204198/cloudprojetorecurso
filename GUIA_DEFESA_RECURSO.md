# Guia de Defesa - Epoca de Recurso (Disaster Recovery)

> Documento para **estudares e defenderes** a entrega do recurso.
> Escrito em linguagem simples. Le de cima a baixo uma vez; depois decora as
> "frases de defesa" no fim de cada seccao.

---

## 1. O que te pediram (numa frase)

Pegar no projeto que ja tens e provar que ele **sobrevive a queda de uma
Availability Zone ou de uma Regiao inteira da AWS**, de forma **automatica** e
**sem cliques na consola**. Nao e adicionar funcionalidades novas; e provar
**resiliencia**.

**Frase de defesa:** *"O objetivo do recurso nao era logica nova, era resiliencia
operacional: detetar a falha, fazer failover para infraestrutura saudavel e
recuperar o estado, tudo automatizado."*

---

## 2. Conceitos-base (explicados como se tivesses 5 anos)

**Regiao vs Availability Zone (AZ)**
Uma **Regiao** e uma zona geografica da AWS (ex: `eu-west-1` = Irlanda). Dentro
de cada regiao ha varias **AZs**, que sao data centers separados. Se uma AZ
arde, as outras continuam. Se a regiao toda cai, precisas de outra regiao.

**Disaster Recovery (DR)**
Plano para continuar a funcionar quando algo grave falha. Mede-se com dois numeros:
- **RTO** (Recovery Time Objective) = **quanto tempo** demoras a recuperar.
- **RPO** (Recovery Point Objective) = **quantos dados** podes perder (em tempo).

**Analogia:** imagina uma loja com uma caixa registadora (primaria) e uma de
reserva na arrecadacao (standby). O **RTO** e quanto tempo demoras a ligar a de
reserva. O **RPO** e quantas vendas ficaram por registar no momento em que a
primeira caixa avariou.

**Frase de defesa:** *"RTO e o tempo de recuperacao; RPO e a perda maxima de
dados aceitavel. Sao os dois numeros que definem qualquer estrategia de DR."*

---

## 3. As pecas do puzzle (a arquitetura)

Tens **duas regioes**:

- **Primaria (`eu-west-1`)** - esta a servir os clientes normalmente.
- **Standby (`eu-central-1`)** - esta "adormecida" a espera (pilot-light).

A frente de tudo esta o **Route 53** (o servico de DNS da AWS = a "lista
telefonica" que traduz o teu dominio no endereco certo).

```
                 Route 53 (DNS + health check)
                          |
         health OK -----> |  <----- se primaria falhar, aponta para standby
                          |
     +--------------------+---------------------+
     |                                          |
  PRIMARIA (eu-west-1)                    STANDBY (eu-central-1)
  ALB + 2 instancias                      ALB + 0 instancias (pilot-light)
  RDS primaria  --- replicacao async --->  RDS read replica
```

**Frase de defesa:** *"O Route 53 esta a frente com um health check. Enquanto a
primaria responde, o trafego vai para ela. Se deixar de responder, o DNS aponta
automaticamente para o standby."*

---

## 4. Pilot-light: o que e e porque escolhi

**Pilot-light** = na regiao standby so deixas ligado o essencial e barato: a
**rede** e a **replica da base de dados** (que tem de estar sempre a copiar os
dados). As **instancias da aplicacao ficam a zero** (`desired_capacity = 0`) e so
arrancam quando ha failover.

Porque? Porque manter tudo ligado nas duas regioes custa o dobro. O enunciado
pede explicitamente uma solucao **"cost-aware"** (consciente do custo). Pilot-light
e barato e ligeiramente mais lento que warm-standby.

**Trade-off (tens de saber dizer isto):**
- Vantagem: custo baixo (nao pagas instancias paradas).
- Desvantagem: RTO um pouco maior, porque as instancias precisam de ~1-2 min
  para arrancar no momento do failover.

**Frase de defesa:** *"Escolhi pilot-light porque o enunciado pede cost-awareness.
Mantenho ligado so a rede e a replica de dados; o compute arranca sob procura no
failover. O trade-off e um RTO ligeiramente maior em troca de metade do custo."*

---

## 5. Como acontece o failover (o filme, passo a passo)

1. A regiao primaria cai (ou eu simulo isso baixando o ASG a 0).
2. O **health check** do Route 53 chama `/health` de 30 em 30 segundos e falha
   3 vezes seguidas.
3. **Duas coisas acontecem em paralelo:**
   - **DNS:** o Route 53 deixa de resolver para a primaria e passa a resolver
     para o ALB do standby (registos "failover" primary/secondary).
   - **Estado:** o alarme CloudWatch dispara -> SNS -> a **Lambda** corre e:
     a) **promove a read replica** a base de dados independente;
     b) **sobe o Auto Scaling Group** standby de 0 para 2 instancias.
4. Passados poucos minutos, o standby esta a servir tudo. Zero cliques na consola.

**Frase de defesa:** *"O failover tem duas metades: o Route 53 trata do DNS
automaticamente, e uma Lambda controladora trata do estado - promove a replica
de base de dados e arranca o compute standby. Nenhum passo depende da consola."*

---

## 6. Ficheiro a ficheiro - o que dizer sobre cada parte

| Onde | O que e | Frase para a defesa |
|---|---|---|
| `modules/region-stack/` | Modulo **reutilizavel** que cria rede + ALB + Auto Scaling Group de uma regiao. | "Uso o **mesmo modulo** para as duas regioes; o standby e so uma instancia parametrizada da primaria com `desired_capacity=0`." |
| `environments/dr/main.tf` | Junta tudo: as duas regioes, a base de dados, o Route 53 e a Lambda. | "Aqui instancio o modulo duas vezes, com providers diferentes para cada regiao." |
| `environments/dr/providers.tf` | Define os 3 providers AWS (primaria, standby, us-east-1). | "Preciso de us-east-1 porque as metricas dos health checks do Route 53 vivem sempre la." |
| RDS `replica` (main.tf) | **Read replica cross-region** da base de dados. | "A replica copia os dados de forma assincrona para a outra regiao; e o que me da o RPO de minutos." |
| `modules/failover-controller/` | A **Lambda** + IAM + alarme que automatizam a promocao. | "Esta Lambda e o cerebro do failover: reage ao alarme e promove o standby sem intervencao humana." |
| `lambda/failover.py` | O codigo Python da Lambda. | "So faz duas chamadas: `promote_read_replica` e `set_desired_capacity`." |
| `.github/workflows/dr-apply.yml` | Pipeline unico que provisiona **as duas regioes**. | "Um so pipeline aplica o Terraform as duas regioes, autenticado por **OIDC**, com aprovacao manual antes de aplicar." |
| `.github/workflows/dr-drill.yml` | Botao que simula a queda e **mede o RTO**. | "Este workflow simula a falha e cronometra o tempo ate recuperar - e o meu numero de RTO real." |
| `docs/dr.md` | O **runbook**: como despoletar, observar e reverter. | "Tenho um runbook documentado para operar o failover." |

---

## 7. Os 5 criterios de avaliacao e como ganhas cada ponto

O recurso vale 20 valores. Estes sao os componentes da grelha:

1. **Standby infrastructure (Terraform) - 5 pts**
   -> "Toda a infra DR esta em Terraform, com um **modulo reutilizavel** usado
   nas duas regioes. O standby e multi-regiao (`eu-central-1`) e a primaria e
   Multi-AZ."

2. **Automated failover - 5 pts**
   -> "Failover **automatico** por health check do Route 53 + Lambda. **Zero**
   interacao com a consola."

3. **Data resilience (RPO) - 4 pts**
   -> "Read replica RDS cross-region, replicacao assincrona, **RPO <= 5 min**
   justificado e medivel pelo `ReplicaLag`."

4. **Pipeline & IaC quality - 3 pts**
   -> "**Um** pipeline provisiona as duas regioes, autenticado por **OIDC**
   (sem chaves de acesso de longa duracao), com modulos limpos."

5. **Live drill & defense - 3 pts**
   -> "Consigo correr o **drill ao vivo** (workflow_dispatch) e explicar os
   trade-offs de RTO/RPO." <- **Isto tens mesmo de conseguir demonstrar.**

---

## 8. As regras de ouro do enunciado (nao te esqueças)

- **Tudo codificado**: nenhum passo do failover depende de clicar na consola. OK.
- **OIDC, nao access keys**: o pipeline autentica por OIDC. OK.
- **Segredos no SSM/Secrets Manager**: a password do RDS vai para o **SSM
  Parameter Store** (SecureString) nas duas regioes, nunca hardcoded. OK.
- **Cost-aware**: pilot-light. OK.
- **Demonstrar ao vivo**: tens o `dr-drill.yml`. **Treina antes da defesa.**

---

## 9. Perguntas dificeis que o professor pode fazer (e respostas)

**"Porque nao warm-standby ou active-active?"**
"Custo. Active-active pagava tudo a dobrar e o enunciado pede cost-awareness.
Pilot-light da-me resiliencia real com custo minimo; aceito um RTO um pouco maior."

**"O teu RPO e zero?"**
"Nao. A replicacao do RDS e assincrona, por isso posso perder as transacoes dos
ultimos segundos antes da falha. O RPO alvo e <= 5 minutos, medido pelo ReplicaLag.
Zero RPO exigiria replicacao sincrona multi-regiao, que e cara e mais lenta."

**"Como sabes que o RTO e mesmo esse?"**
"Nao inventei o numero: o workflow `DR Drill` cronometra desde a queda simulada
ate o dominio voltar a responder 200, e imprime o valor. E um numero medido, nao
teorico."

**"Porque e que a Lambda esta em us-east-1?"**
"Porque as metricas dos health checks do Route 53 so existem em us-east-1. O
alarme CloudWatch que dispara a Lambda tem de estar la."

**"O que acontece a base de dados depois do failover?"**
"A replica e promovida a base independente e passa a aceitar escritas. Deixa de
estar ligada a primaria. Para voltar ao normal, reprovisiono a relacao de
replicacao com Terraform quando a primaria estiver de volta."

**"E se o failover disparar por engano (falso alarme)?"**
"O health check exige 3 falhas seguidas antes de marcar a primaria como down, o
que evita disparos por um soluco momentaneo. A promocao da Lambda tambem e
idempotente - se ja estiver promovida, nao repete."

---

## 10. Checklist para o dia da defesa

- [ ] Consigo desenhar o diagrama das duas regioes + Route 53 num quadro.
- [ ] Sei explicar RTO e RPO com a analogia da caixa registadora.
- [ ] Sei porque escolhi pilot-light (custo) e o seu trade-off.
- [ ] Sei os 3 passos do failover (health check -> DNS + Lambda -> standby serve).
- [ ] Corri o `DR Drill` pelo menos uma vez e sei o meu RTO medido.
- [ ] Sei apontar, no codigo, onde estao: modulo reutilizavel, OIDC, SSM, Lambda.

Boa sorte. Se souberes explicar as seccoes 1, 4, 5 e 9, defendes bem.
