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

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён"        "no"  "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no"  "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

# TODO 1: проверьте, что значение параметра port отлично от 22
PORT_VAL="$(sudo sshd -T | awk '/^port/{print $2}')"
if [[ "$PORT_VAL" != "22" && -n "$PORT_VAL" ]]; then
    PORT_CHECK="custom"
else
    PORT_CHECK="22"
fi
check "Порт службы SSH изменён со стандартного 22 (фактический порт: $PORT_VAL)" "custom" "$PORT_CHECK"

# TODO 2: проверьте, что значение параметра maxauthtries равно 3
check "Ограничение количества попыток аутентификации (MaxAuthTries) равно 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"

# TODO 3: проверьте, что политика по умолчанию для входящего трафика равна deny
#         источник данных: sudo ufw status verbose | grep Default
UFW_DEFAULT_INCOMING="$(sudo ufw status verbose | awk -F'[(,]' '/Default:/{print $2}' | tr -d ' ')"
check "Политика по умолчанию для входящего трафика установлена в deny" "deny" "$UFW_DEFAULT_INCOMING"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
