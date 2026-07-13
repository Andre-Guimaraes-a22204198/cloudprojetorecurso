# Valores NAO-secretos usados pelo pipeline (plan/apply).
# A db_password NAO esta aqui: e injetada via TF_VAR_db_password
# (secret DB_PASSWORD do GitHub) e guardada no SSM Parameter Store.
project        = "cloudprojetofinal"
primary_region = "eu-west-1"
standby_region = "eu-central-1"
domain_name    = "app.recurso-andre.click"
hosted_zone_id = "Z035029930HOTWOYTGMLI"
