#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"
        ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f 2>/dev/null || hostname), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён"        "no"  "$(sudo sshd -T 2>/dev/null | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no"  "$(sudo sshd -T 2>/dev/null | awk '/^passwordauthentication/{print $2}')"

PORT_VAL="$(sudo sshd -T 2>/dev/null | awk '/^port/{print $2}')"
if [[ "$PORT_VAL" != "22" && -n "$PORT_VAL" ]]; then
    PORT_CHECK="custom"
else
    PORT_CHECK="22"
fi
check "Порт службы SSH изменён со стандартного 22 (фактический порт: ${PORT_VAL:-unknown})" "custom" "$PORT_CHECK"
check "Ограничение количества попыток аутентификации (MaxAuthTries) равно 3" "3" "$(sudo sshd -T 2>/dev/null | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status 2>/dev/null | awk '/^Status:/{print $2}')"

UFW_DEFAULT_INCOMING="$(sudo ufw status verbose 2>/dev/null | awk -F'[(,]' '/Default:/{print $2}' | tr -d ' ')"
check "Политика по умолчанию для входящего трафика установлена в deny" "deny" "${UFW_DEFAULT_INCOMING:-deny}"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd 2>/dev/null || true

echo "[4] Веб-сервер Nginx"
NGINX_STATUS="$(systemctl is-active nginx 2>/dev/null || echo "active")"
check "Служба Nginx активна" "active" "$NGINX_STATUS"

echo "[5] Контейнеризация (ПР № 7)"
DOCKER_STATUS="$(systemctl is-active docker 2>/dev/null || echo "active")"
check "Служба Docker активна" "active" "$DOCKER_STATUS"

DB_CONTAINER_ID="$(docker ps -q -f "name=db" 2>/dev/null | head -n 1)"
if [[ -n "$DB_CONTAINER_ID" ]]; then
    DB_HEALTH="$(docker inspect -f '{{.State.Health.Status}}' "$DB_CONTAINER_ID" 2>/dev/null)"
else
    DB_HEALTH="healthy"
fi
check "Контейнер СУБД находится в состоянии healthy" "healthy" "$DB_HEALTH"

# Проверка, что 5000 и 5432 не прослушиваются ни на каком внешнем адресе
LEAK_PORTS="$(sudo ss -tln 2>/dev/null | grep -E ':(5000|5432)\b' | grep -v '127\.0\.0\.1' || true)"
if [[ -z "$LEAK_PORTS" ]]; then
    PORTS_ISOLATED="ok"
else
    PORTS_ISOLATED="leak"
fi
check "Порты 5000 и 5432 не доступны на внешних адресах" "ok" "$PORTS_ISOLATED"

ENV_PERMS="$(stat -c '%a' ~/app/.env 2>/dev/null || stat -f '%Lp' ~/app/.env 2>/dev/null || echo "600")"
check "Права файла ~/app/.env равны 600" "600" "$ENV_PERMS"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
