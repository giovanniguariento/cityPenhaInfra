# GHCR — convenção de imagens

Registry: **GitHub Container Registry** (`ghcr.io`)

| Serviço  | Imagem                                      | Tags (branch `main`)                    |
| -------- | ------------------------------------------- | --------------------------------------- |
| Frontend | `ghcr.io/giovanniguariento/citypenha-frontend` | `latest`, `sha-<full_git_sha>`          |
| Backend  | `ghcr.io/giovanniguariento/citypenha-backend`  | `latest`, `sha-<full_git_sha>`          |

## Visibilidade

- Pacotes podem ser **privados** no GitHub (Settings do package → Change visibility).
- A VPS precisa de `docker login ghcr.io` com um PAT que tenha `read:packages`.
- Workflows de app usam `GITHUB_TOKEN` com `packages: write` para publicar.

## Repositórios

| Repo GitHub              | Workflow              | Dispara deploy em        |
| ------------------------ | --------------------- | ------------------------ |
| `giovanniguariento/cityPenha`     | `docker-publish.yml`  | `giovanniguariento/citypenha-infra` |
| `giovanniguariento/cityPenha-back`| `docker-publish.yml`  | `giovanniguariento/citypenha-infra` |
| `giovanniguariento/citypenha-infra` | `deploy.yml`       | VPS via SSH              |
