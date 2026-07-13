# Arquitetura

## Diagrama




    Cliente --> OS[order-service :8083]

    OS -->|REST| US[user-service :8081]

    OS -->|REST| PS[product-service :8082]

    OS -->|publica| SQS[AWS SQS]

    SQS -->|consome| PS

    US & PS & OS --> RDS[(RDS PostgreSQL)]


## Infraestrutura
- VPC com subnets públicas (EC2s) e privada (RDS)
- 3 EC2s t3.micro com Docker
- RDS PostgreSQL em subnet privada
- SQS com DLQ para mensagens falhadas