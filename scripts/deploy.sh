#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOCAL_DIR="${REPO_ROOT}/site/"

DRY_RUN=""
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN="--dry-run"
fi

if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: Файл ${LOCAL_DIR}index.html не найден!" >&2
    exit 1
fi

if [[ -d "${REPO_ROOT}/.git" ]]; then
    if ! git -C "${REPO_ROOT}" diff --quiet || ! git -C "${REPO_ROOT}" diff --cached --quiet; then
        echo "Ошибка: В репозитории есть незафиксированные изменения!" >&2
        exit 1
    fi
fi

rsync -avz --delete --chmod=D755,F644 \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    ${DRY_RUN} "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

if [[ -n "${DRY_RUN}" ]]; then
    echo "План синхронизации успешно сформирован (--dry-run)."
    exit 0
fi

if [[ -f "${CA_CERT}" ]]; then
    curl -f -s --cacert "${CA_CERT}" -o /dev/null "${SITE_URL}" || {
        echo "Ошибка: Ресурс ${SITE_URL} недоступен!" >&2
        exit 1
    }
else
    curl -f -k -s -o /dev/null "${SITE_URL}" || {
        echo "Ошибка: Ресурс ${SITE_URL} недоступен!" >&2
        exit 1
    }
fi

COMMIT_HASH="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo "deployed")"
echo "Деплой успешно завершён. Версия: ${COMMIT_HASH}"
exit 0
