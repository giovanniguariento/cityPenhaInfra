#!/usr/bin/env bash
# Restaura backups de banco (MariaDB) e arquivos WordPress a partir de backups/.
# Uso: cd infra && ./scripts/restore-backups.sh [opções]
set -euo pipefail

OLD_URL="https://primary-production-c4be9.up.railway.app"
LOCAL_URL="http://localhost/blog"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${INFRA_DIR}/.." && pwd)"
BACKUPS_DIR="${REPO_ROOT}/backups"

YES=false
NO_BACKUP=false
SKIP_DB=false
SKIP_WORDPRESS=false
FROM_TAR=false
REPLACE_URLS=false
LOCAL=false
NEW_URL=""

log_info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
log_ok()   { printf '\033[1;32m[OK]\033[0m   %s\n' "$*"; }
log_warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
log_err()  { printf '\033[1;31m[ERR]\033[0m  %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Restaura backups de banco e WordPress do diretório backups/.

Uso: ./scripts/restore-backups.sh [opções]

Opções:
  -y, --yes              Pula confirmação interativa
      --no-backup        Não cria dump preventivo antes de sobrescrever
      --skip-db          Restaura apenas arquivos WordPress
      --skip-wordpress   Restaura apenas o banco
      --from-tar         Usa arquivos .tar.gz em vez das pastas extraídas
      --local            Substitui URLs → http://localhost/blog (dev local)
      --replace-urls     Substitui URLs → WORDPRESS_PUBLIC_URL ou https://PUBLIC_DOMAIN/blog
      --url URL          Substitui URLs para URL explícita (implica --replace-urls)
  -h, --help             Exibe esta ajuda

Exemplos:
  ./scripts/restore-backups.sh
  ./scripts/restore-backups.sh --yes --local
  ./scripts/restore-backups.sh --yes --replace-urls
  ./scripts/restore-backups.sh --yes --url http://localhost/blog
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes) YES=true ;;
      --no-backup) NO_BACKUP=true ;;
      --skip-db) SKIP_DB=true ;;
      --skip-wordpress) SKIP_WORDPRESS=true ;;
      --from-tar) FROM_TAR=true ;;
      --local) LOCAL=true; REPLACE_URLS=true ;;
      --replace-urls) REPLACE_URLS=true ;;
      --url)
        shift
        [[ $# -gt 0 ]] || { log_err "--url requer um valor"; exit 1; }
        NEW_URL="$1"
        REPLACE_URLS=true
        ;;
      -h|--help) usage; exit 0 ;;
      *) log_err "Opção desconhecida: $1"; usage; exit 1 ;;
    esac
    shift
  done

  if [[ "$SKIP_DB" == true && "$SKIP_WORDPRESS" == true ]]; then
    log_err "Use no máximo um de: --skip-db, --skip-wordpress"
    exit 1
  fi
}

load_env() {
  local env_file="${INFRA_DIR}/.env"
  if [[ ! -f "$env_file" ]]; then
    log_err "Arquivo .env não encontrado em ${INFRA_DIR}"
    log_err "Copie .env.example para .env e configure as variáveis."
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a

  : "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD não definido em .env}"
  : "${MYSQL_DATABASE:?MYSQL_DATABASE não definido em .env}"

  if [[ "$REPLACE_URLS" == true && -z "$NEW_URL" ]]; then
    if [[ "$LOCAL" == true ]]; then
      NEW_URL="$LOCAL_URL"
    elif [[ -n "${WORDPRESS_PUBLIC_URL:-}" ]]; then
      NEW_URL="${WORDPRESS_PUBLIC_URL}"
    else
      : "${PUBLIC_DOMAIN:?PUBLIC_DOMAIN não definido em .env (necessário para --replace-urls)}"
      NEW_URL="https://${PUBLIC_DOMAIN}/blog"
    fi
  fi

  NEW_URL="${NEW_URL%/}"
}

collect_old_urls() {
  OLD_URLS=("$OLD_URL" "$LOCAL_URL")

  if [[ -n "${PUBLIC_DOMAIN:-}" ]]; then
    OLD_URLS+=("https://${PUBLIC_DOMAIN}")
    OLD_URLS+=("https://${PUBLIC_DOMAIN}/blog")
    OLD_URLS+=("http://${PUBLIC_DOMAIN}/blog")
  fi

  if [[ -n "${WORDPRESS_PUBLIC_URL:-}" ]]; then
    OLD_URLS+=("${WORDPRESS_PUBLIC_URL%/}")
  fi
}

check_prerequisites() {
  command -v docker >/dev/null 2>&1 || { log_err "docker não encontrado no PATH"; exit 1; }
  docker compose version >/dev/null 2>&1 || { log_err "docker compose v2 não disponível"; exit 1; }

  if [[ "$SKIP_DB" == false && ! -f "${BACKUPS_DIR}/backup_db.sql" ]]; then
    log_err "Dump não encontrado: ${BACKUPS_DIR}/backup_db.sql"
    exit 1
  fi

  if [[ "$SKIP_WORDPRESS" == false ]]; then
    if [[ "$FROM_TAR" == true ]]; then
      for archive in backup_configs.tar.gz backup_plugins.tar.gz backup_uploads.tar.gz; do
        [[ -f "${BACKUPS_DIR}/${archive}" ]] || {
          log_err "Arquivo não encontrado: ${BACKUPS_DIR}/${archive}"
          exit 1
        }
      done
    else
      [[ -f "${INFRA_DIR}/wordpress/wp-config.php" ]] || {
        log_err "wp-config.php não encontrado em ${INFRA_DIR}/wordpress/"
        exit 1
      }
      [[ -d "${BACKUPS_DIR}/backup_plugins/wp-content/plugins" ]] || {
        log_err "Plugins não encontrados em ${BACKUPS_DIR}/backup_plugins/wp-content/plugins"
        exit 1
      }
      [[ -d "${BACKUPS_DIR}/backup_uploads/wp-content/uploads" ]] || {
        log_err "Uploads não encontrados em ${BACKUPS_DIR}/backup_uploads/wp-content/uploads"
        exit 1
      }
    fi
  fi
}

confirm_restore() {
  if [[ "$YES" == true ]]; then
    return 0
  fi

  cat <<EOF

╔══════════════════════════════════════════════════════════════╗
║  RESTAURAÇÃO DE BACKUPS — CityPenha                          ║
╚══════════════════════════════════════════════════════════════╝

Origem: ${BACKUPS_DIR}

EOF

  if [[ "$SKIP_DB" == false ]]; then
    echo "  • Banco MariaDB (schema: ${MYSQL_DATABASE}) ← backup_db.sql"
  fi
  if [[ "$SKIP_WORDPRESS" == false ]]; then
    echo "  • Volume wordpress_data ← plugins, uploads, wp-config.php"
  fi
  if [[ "$REPLACE_URLS" == true ]]; then
    echo "  • Substituir URLs do WordPress → ${NEW_URL}"
  fi
  if [[ "$NO_BACKUP" == false && "$SKIP_DB" == false ]]; then
    echo "  • Backup preventivo será criado em backups/pre_restore_*.sql"
  fi

  echo
  log_warn "Esta operação SOBRESCREVE dados existentes."
  echo -n "Digite RESTORE para continuar: "
  read -r answer
  if [[ "$answer" != "RESTORE" ]]; then
    log_info "Operação cancelada."
    exit 0
  fi
}

compose() {
  docker compose -f "${INFRA_DIR}/docker-compose.yml" --project-directory "${INFRA_DIR}" "$@"
}

wait_for_mariadb() {
  log_info "Aguardando MariaDB ficar healthy..."
  local i
  for i in $(seq 1 30); do
    if compose ps mariadb 2>/dev/null | grep -q "(healthy)"; then
      log_ok "MariaDB healthy"
      return 0
    fi
    sleep 2
  done
  log_err "MariaDB não ficou healthy em 60s"
  compose ps mariadb || true
  exit 1
}

stop_dependent_services() {
  log_info "Parando serviços dependentes do banco..."
  compose stop backend wordpress wordpress-nginx 2>/dev/null || true
}

start_mariadb() {
  log_info "Subindo MariaDB..."
  compose up -d mariadb
  wait_for_mariadb
}

create_pre_restore_backup() {
  if [[ "$NO_BACKUP" == true || "$SKIP_DB" == true ]]; then
    return 0
  fi

  local outfile="${BACKUPS_DIR}/pre_restore_$(date +%Y%m%d_%H%M%S).sql"
  log_info "Criando backup preventivo: ${outfile}"
  compose exec -T mariadb mariadb-dump \
    -u root -p"${MYSQL_ROOT_PASSWORD}" \
    "${MYSQL_DATABASE}" > "$outfile"
  log_ok "Backup preventivo salvo ($(du -h "$outfile" | cut -f1))"
}

restore_database() {
  log_info "Restaurando banco a partir de backup_db.sql..."
  compose exec -T mariadb mariadb \
    -u root -p"${MYSQL_ROOT_PASSWORD}" \
    "${MYSQL_DATABASE}" < "${BACKUPS_DIR}/backup_db.sql"
  log_ok "Banco restaurado"
}

resolve_wordpress_volume() {
  local volume
  volume="$(docker volume ls --filter "name=wordpress_data" --format '{{.Name}}' | head -1)"
  if [[ -z "$volume" ]]; then
    log_info "Volume wordpress_data ainda não existe; criando via docker compose..."
    compose up -d mariadb wordpress 2>/dev/null || compose up -d wordpress
    compose stop wordpress wordpress-nginx 2>/dev/null || true
    volume="$(docker volume ls --filter "name=wordpress_data" --format '{{.Name}}' | head -1)"
  fi
  if [[ -z "$volume" ]]; then
    log_err "Não foi possível localizar o volume wordpress_data"
    exit 1
  fi
  echo "$volume"
}

restore_wordpress_files() {
  local wp_volume source_dir
  wp_volume="$(resolve_wordpress_volume)"
  source_dir="$(mktemp -d)"

  cleanup_temp() {
    rm -rf "$source_dir"
  }
  trap cleanup_temp RETURN

  log_info "Restaurando arquivos WordPress no volume ${wp_volume}..."
  local infra_wp_config="${INFRA_DIR}/wordpress/wp-config.php"
  [[ -f "$infra_wp_config" ]] || {
    log_err "wp-config.php não encontrado em ${infra_wp_config}"
    exit 1
  }

  if [[ "$FROM_TAR" == true ]]; then
    log_info "Extraindo arquivos de .tar.gz..."
    tar -xzf "${BACKUPS_DIR}/backup_configs.tar.gz" -C "$source_dir"
    tar -xzf "${BACKUPS_DIR}/backup_plugins.tar.gz" -C "$source_dir"
    tar -xzf "${BACKUPS_DIR}/backup_uploads.tar.gz" -C "$source_dir"

    docker run --rm \
      -v "${wp_volume}:/var/www/html" \
      -v "${source_dir}:/backups:ro" \
      -v "${infra_wp_config}:/wp-config.php:ro" \
      alpine sh -c '
        cp /wp-config.php /var/www/html/wp-config.php
        mkdir -p /var/www/html/wp-content/plugins /var/www/html/wp-content/uploads
        cp -a /backups/wp-content/plugins/. /var/www/html/wp-content/plugins/
        cp -a /backups/wp-content/uploads/. /var/www/html/wp-content/uploads/
        chown -R 33:33 /var/www/html/wp-content /var/www/html/wp-config.php
      '
  else
    docker run --rm \
      -v "${wp_volume}:/var/www/html" \
      -v "${BACKUPS_DIR}:/backups:ro" \
      -v "${infra_wp_config}:/wp-config.php:ro" \
      alpine sh -c '
        cp /wp-config.php /var/www/html/wp-config.php
        mkdir -p /var/www/html/wp-content/plugins /var/www/html/wp-content/uploads
        cp -a /backups/backup_plugins/wp-content/plugins/. /var/www/html/wp-content/plugins/
        cp -a /backups/backup_uploads/wp-content/uploads/. /var/www/html/wp-content/uploads/
        chown -R 33:33 /var/www/html/wp-content /var/www/html/wp-config.php
      '
  fi

  log_ok "Arquivos WordPress restaurados"
}

replace_urls() {
  collect_old_urls
  log_info "Substituindo URLs do WordPress → ${NEW_URL}"

  local sql old
  sql="UPDATE wp_options SET option_value='${NEW_URL}' WHERE option_name IN ('siteurl','home');"

  for old in "${OLD_URLS[@]}"; do
    [[ "$old" == "$NEW_URL" ]] && continue
    sql+="
UPDATE wp_options
SET option_value = REPLACE(option_value, '${old}', '${NEW_URL}')
WHERE option_value LIKE '%${old}%';

UPDATE wp_posts
SET guid = REPLACE(guid, '${old}', '${NEW_URL}'),
    post_content = REPLACE(post_content, '${old}', '${NEW_URL}')
WHERE guid LIKE '%${old}%' OR post_content LIKE '%${old}%';

UPDATE wp_postmeta
SET meta_value = REPLACE(meta_value, '${old}', '${NEW_URL}')
WHERE meta_value LIKE '%${old}%';"
  done

  compose exec -T mariadb mariadb \
    -u root -p"${MYSQL_ROOT_PASSWORD}" \
    "${MYSQL_DATABASE}" <<< "$sql"

  log_ok "URLs substituídas (siteurl/home = ${NEW_URL})"
}

skip_admin_email_confirm_for_local() {
  if [[ "$LOCAL" != true ]]; then
    return 0
  fi

  log_info "Adiando verificação de e-mail do admin (dev local)..."
  compose exec -T mariadb mariadb \
    -u root -p"${MYSQL_ROOT_PASSWORD}" \
    "${MYSQL_DATABASE}" <<< "
UPDATE wp_options
SET option_value = CAST(UNIX_TIMESTAMP() + 31536000 AS CHAR)
WHERE option_name = 'admin_email_lifespan';
"
  log_ok "admin_email_lifespan atualizado (+1 ano)"
}

start_services() {
  log_info "Subindo wordpress, wordpress-nginx e backend..."
  compose up -d wordpress wordpress-nginx backend
  log_ok "Serviços iniciados"
}

print_summary() {
  cat <<EOF

Restauração concluída.

Verificação sugerida:
  cd infra
  docker compose logs backend --tail 20
  curl -s http://localhost/api/home | head -c 200
  curl -sI http://localhost/blog/wp-login.php | head -5

Para subir o restante da stack:
  docker compose up -d frontend nginx

WordPress admin (local): http://localhost/blog/wp-login.php

EOF
}

main() {
  parse_args "$@"
  cd "$INFRA_DIR"
  load_env
  check_prerequisites
  confirm_restore

  stop_dependent_services
  start_mariadb

  if [[ "$SKIP_DB" == false ]]; then
    create_pre_restore_backup
    restore_database
    if [[ "$REPLACE_URLS" == true ]]; then
      replace_urls
      skip_admin_email_confirm_for_local
    fi
  fi

  if [[ "$SKIP_WORDPRESS" == false ]]; then
    restore_wordpress_files
  fi

  start_services
  print_summary
}

main "$@"
