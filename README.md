# citypenha-infra

Stack Docker de produção (nginx, frontend, backend, WordPress, MariaDB). A VPS **não faz build** das apps — apenas puxa imagens do [GHCR](GHCR.md).

## Repositórios

| Repo | Função |
|------|--------|
| [cityPenha](https://github.com/giovanniguariento/cityPenha) | Build + push `citypenha-frontend` |
| [cityPenha-back](https://github.com/giovanniguariento/cityPenha-back) | Build + push `citypenha-backend` |
| **este repo** | Compose, nginx, deploy SSH |

## Bootstrap na VPS (uma vez)

### 1. Pré-requisitos

- Docker Engine + Compose v2
- Domínio apontando para o IP da VPS
- Usuário `deploy` (ou similar) no grupo `docker`

### 2. Login no GHCR

Crie um PAT (classic ou fine-grained) com `read:packages`:

```bash
echo "SEU_PAT" | docker login ghcr.io -u SEU_USUARIO_GITHUB --password-stdin
```

Salve credenciais em `~/.docker/config.json` (persiste entre reboots).

### 3. Clonar só este repositório

```bash
sudo mkdir -p /opt/citypenha
sudo chown deploy:deploy /opt/citypenha
git clone https://github.com/giovanniguariento/citypenha-infra.git /opt/citypenha/infra
cd /opt/citypenha/infra
```

Não é necessário clonar `cityPenha` nem `cityPenha-back` na VPS.

### 4. Configurar `.env`

```bash
cp .env.example .env
# Editar: senhas, Firebase, FRONTEND_IMAGE, BACKEND_IMAGE, etc.
```

Imagens padrão (após primeiro push no CI):

```bash
FRONTEND_IMAGE=ghcr.io/giovanniguariento/citypenha-frontend:latest
BACKEND_IMAGE=ghcr.io/giovanniguariento/citypenha-backend:latest
```

### 5. SSH para GitHub Actions

No usuário da VPS (`deploy`):

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
# Colar a chave pública correspondente ao secret VPS_SSH_KEY do repo infra
nano ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 6. Primeiro deploy (stack completa)

Ordem manual — ver também [INFRA_DEPLOY.md](../INFRA_DEPLOY.md) no monorepo local ou documentação equivalente:

```bash
cd /opt/citypenha/infra

docker compose pull
docker compose up -d mariadb
# aguardar healthy
./scripts/restore-backups.sh   # primeira vez
docker compose up -d wordpress wordpress-nginx
docker compose up -d backend
docker compose up -d frontend
docker compose up -d nginx
```

TLS: Certbot conforme runbook de produção.

## CI/CD automático

1. Push em `main` em `cityPenha` ou `cityPenha-back` → workflow publica imagem no GHCR.
2. `repository_dispatch` dispara `deploy.yml` neste repo.
3. Job SSH na VPS: `docker compose pull` + `up -d` do serviço alterado (`backend` antes de `frontend` quando ambos).

### Secrets (repo `citypenha-infra`)

| Secret | Descrição |
|--------|-----------|
| `VPS_HOST` | IP ou hostname |
| `VPS_USER` | ex. `deploy` |
| `VPS_SSH_KEY` | chave privada (sem passphrase) |
| `VPS_DEPLOY_PATH` | ex. `/opt/citypenha/infra` |

### Secrets (repos `cityPenha` e `cityPenha-back`)

| Secret / Variable | Repo | Descrição |
|-------------------|------|-----------|
| `INFRA_DISPATCH_TOKEN` | ambos | PAT com acesso ao repo `citypenha-infra` |
| `API_URL` (variable) | cityPenha | URL pública da API no build do frontend |

### Deploy manual / rollback

Actions → **Deploy to VPS** → `workflow_dispatch`:

- `frontend_tag` / `backend_tag`: `latest` ou `sha-<commit>` (tag imutável do CI)
- `deploy_service`: `frontend`, `backend` ou `both`

## Comandos úteis na VPS

```bash
cd /opt/citypenha/infra

# Atualizar apps (equivalente ao que o CI faz)
docker compose pull backend frontend
docker compose up -d backend
docker compose up -d frontend

docker compose ps
docker compose logs -f nginx backend frontend
```

## Estrutura

```
infra/
├── docker-compose.yml
├── .env.example
├── GHCR.md
├── nginx/
├── mariadb/
├── wordpress/
├── scripts/restore-backups.sh
└── .github/workflows/deploy.yml
```
