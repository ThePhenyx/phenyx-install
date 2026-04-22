#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/docker-compose.template.yml"
OUTPUT="$SCRIPT_DIR/docker-compose.yml"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: no se encuentra $TEMPLATE" >&2
  exit 1
fi

echo "=== Generador de docker-compose.yml para Phenyx Health ==="
echo

missing=()
command -v docker >/dev/null 2>&1 || missing+=("docker")
docker compose version >/dev/null 2>&1 || missing+=("docker compose (v2)")
command -v aws >/dev/null 2>&1 || missing+=("aws")
if (( ${#missing[@]} > 0 )); then
  echo "AVISO: faltan las siguientes herramientas en este sistema:" >&2
  for m in "${missing[@]}"; do echo "  - $m" >&2; done
  echo "Puedes continuar generando el docker-compose.yml, pero necesitarás" >&2
  echo "instalarlas antes de hacer login en ECR y arrancar el sistema." >&2
  echo >&2
fi

prompt_default() {
  local label="$1" default="$2" var
  if [[ -n "$default" ]]; then
    read -r -p "$label [$default]: " var
    echo "${var:-$default}"
  else
    read -r -p "$label: " var
    echo "$var"
  fi
}

prompt_secret() {
  local label="$1" var
  read -r -s -p "$label: " var
  echo >&2
  echo "$var"
}

random_secret() (
  set +o pipefail
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 48
)

echo "--- Puerto del host ---"
echo "Puerto con el que Docker publica el frontend en esta máquina."
echo "El backend, rodaskernel y Postgres no se publican: solo son accesibles"
echo "desde dentro de la red interna de Docker (el frontend proxya /api/ al backend)."
FRONTEND_PORT=$(prompt_default "Puerto del frontend" "80")
echo

echo "--- JWT secret ---"
JWT_CHOICE=$(prompt_default "¿Generar uno aleatorio? (s/n)" "s")
if [[ "$JWT_CHOICE" =~ ^[sS]$ ]]; then
  JWT_SECRET=$(random_secret)
  echo "  Generado."
else
  JWT_SECRET=$(prompt_secret "JWT_SECRET")
  if [[ -z "$JWT_SECRET" ]]; then
    echo "ERROR: JWT_SECRET no puede estar vacío" >&2
    exit 1
  fi
fi
echo

echo "--- Usuario admin inicial ---"
echo "Credenciales con las que se creará el usuario admin la primera vez que"
echo "arranque el backend contra una BD vacía. Si la BD ya tiene usuarios,"
echo "estas variables se ignoran (no sobrescriben nada)."
echo
echo "AVISO: la contraseña que introduzcas quedará guardada EN CLARO dentro"
echo "del docker-compose.yml generado. Protege ese fichero (permisos,"
echo "copias de seguridad) y cambia la contraseña desde la propia aplicación"
echo "después del primer login."
DEFAULT_USER_NAME=$(prompt_default "Nombre de usuario admin" "admin")
DEFAULT_USER_PASSWORD=$(prompt_secret "Contraseña del admin")
if [[ -z "$DEFAULT_USER_PASSWORD" ]]; then
  echo "ERROR: la contraseña del admin no puede estar vacía" >&2
  exit 1
fi
echo

echo "--- Base de datos ---"
DB_CHOICE=$(prompt_default "¿Usar Postgres incluido (i) o base de datos propia (p)?" "i")
USE_INTERNAL_DB=false
if [[ "$DB_CHOICE" =~ ^[iI]$ ]]; then
  USE_INTERNAL_DB=true
  DB_HOST="phenyxdb"
  DB_PORT="5432"
  DB_NAME="postgres"
  DB_USER="postgres"
  PASS_CHOICE=$(prompt_default "¿Generar contraseña aleatoria para el Postgres incluido? (s/n)" "s")
  if [[ "$PASS_CHOICE" =~ ^[sS]$ ]]; then
    DB_PASS=$(random_secret)
    echo "  Contraseña generada."
  else
    DB_PASS=$(prompt_secret "Contraseña de Postgres")
    if [[ -z "$DB_PASS" ]]; then
      echo "ERROR: la contraseña no puede estar vacía" >&2
      exit 1
    fi
  fi
else
  DB_HOST=$(prompt_default "DB_HOST" "")
  DB_PORT=$(prompt_default "DB_PORT" "5432")
  DB_NAME=$(prompt_default "DB_NAME" "phenyx")
  DB_USER=$(prompt_default "DB_USER" "phenyx")
  DB_PASS=$(prompt_secret "DB_PASS")
  if [[ -z "$DB_HOST" || -z "$DB_PASS" ]]; then
    echo "ERROR: DB_HOST y DB_PASS son obligatorios" >&2
    exit 1
  fi
fi
echo

NODE_ENV="prod"

if [[ -f "$OUTPUT" ]]; then
  backup="$OUTPUT.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$OUTPUT" "$backup"
  echo "Backup del docker-compose.yml anterior: $backup"
fi

render() {
  local content
  content=$(cat "$TEMPLATE")

  if [[ "$USE_INTERNAL_DB" != "true" ]]; then
    content=$(printf '%s\n' "$content" | awk '
      /# >>> PHENYX_DB_BLOCK_START/ { skip=1; next }
      /# <<< PHENYX_DB_BLOCK_END/   { skip=0; next }
      /# >>> PHENYX_DB_DEPENDS_START/ { skip=1; next }
      /# <<< PHENYX_DB_DEPENDS_END/   { skip=0; next }
      !skip { print }
    ')
  else
    content=$(printf '%s\n' "$content" | grep -v '^# >>> PHENYX_DB_' | grep -v '^# <<< PHENYX_DB_')
  fi

  printf '%s' "$content" | awk -v jwt="$JWT_SECRET" \
                               -v dbhost="$DB_HOST" \
                               -v dbport="$DB_PORT" \
                               -v dbname="$DB_NAME" \
                               -v dbuser="$DB_USER" \
                               -v dbpass="$DB_PASS" \
                               -v nodeenv="$NODE_ENV" \
                               -v feport="$FRONTEND_PORT" \
                               -v adminuser="$DEFAULT_USER_NAME" \
                               -v adminpass="$DEFAULT_USER_PASSWORD" '
    {
      gsub(/\$\{JWT_SECRET\}/,            jwt)
      gsub(/\$\{DB_HOST\}/,               dbhost)
      gsub(/\$\{DB_PORT\}/,               dbport)
      gsub(/\$\{DB_NAME\}/,               dbname)
      gsub(/\$\{DB_USER\}/,               dbuser)
      gsub(/\$\{DB_PASS\}/,               dbpass)
      gsub(/\$\{NODE_ENV\}/,              nodeenv)
      gsub(/\$\{FRONTEND_PORT\}/,         feport)
      gsub(/\$\{DEFAULT_USER_NAME\}/,     adminuser)
      gsub(/\$\{DEFAULT_USER_PASSWORD\}/, adminpass)
      print
    }'
}

render > "$OUTPUT"
echo "docker-compose.yml generado en $OUTPUT"
echo

cat <<'EOF'
=== Siguientes pasos ===
1. Haz login en ECR (ver README, sección "Paso 2 — Login en ECR").
2. Arranca el sistema:
     docker compose up -d
     docker compose ps

Si más adelante quieres cambiar el puerto del frontend, el JWT_SECRET o la
configuración de la base de datos, vuelve a ejecutar este mismo script. La
contraseña del usuario admin no se puede cambiar así una vez creado el
usuario: hazlo desde la propia aplicación.
EOF
