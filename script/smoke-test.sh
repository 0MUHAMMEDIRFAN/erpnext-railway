#!/usr/bin/env bash
set -Eeuo pipefail

image=$1
site=erpnext.test
export FRAPPE_DB_PASSWORD=$(openssl rand -hex 24)
export RFP_SITE_ADMIN_PASSWORD="$(openssl rand -hex 24) !\$&"
export RFP_DOMAIN_NAME=$site FRAPPE_DB_HOST=db
export FRAPPE_REDIS_CACHE=redis://redis:6379/0 FRAPPE_REDIS_QUEUE=redis://redis:6379/1
export MARIADB_ROOT_PASSWORD=$FRAPPE_DB_PASSWORD

cleanup() {
    if [[ $1 != 0 ]]; then
        docker logs erpnext-smoke 2>&1 || true
        docker logs erpnext-smoke-db 2>&1 || true
    fi
    docker rm -f -v erpnext-smoke erpnext-smoke-redis erpnext-smoke-db >/dev/null 2>&1 || true
    docker volume rm erpnext-smoke-sites >/dev/null 2>&1 || true
    docker network rm erpnext-smoke >/dev/null 2>&1 || true
}
trap 'cleanup "$?"' EXIT

echo "::add-mask::$FRAPPE_DB_PASSWORD"
echo "::add-mask::$RFP_SITE_ADMIN_PASSWORD"
docker network create erpnext-smoke
docker volume create erpnext-smoke-sites
docker run -d --network erpnext-smoke --network-alias db --name erpnext-smoke-db \
    -e MARIADB_ROOT_PASSWORD -e MARIADB_ROOT_HOST=% mariadb:11.8 \
    --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
docker run -d --network erpnext-smoke --network-alias redis --name erpnext-smoke-redis redis:6.2-alpine

start_app() {
    docker run -d --network erpnext-smoke --name erpnext-smoke -p 127.0.0.1:18080:8080 \
        -v erpnext-smoke-sites:/home/frappe/frappe-bench/sites \
        -e RFP_DOMAIN_NAME -e RFP_SITE_ADMIN_PASSWORD -e FRAPPE_DB_HOST -e FRAPPE_DB_PASSWORD \
        -e FRAPPE_REDIS_CACHE -e FRAPPE_REDIS_QUEUE "$image"
}

check_app() {
    local base=http://127.0.0.1:18080
    local attempts=0 asset
    until curl -fsS -H "Host: $site" "$base/api/method/ping" 2>/dev/null | jq -e '.message == "pong"' >/dev/null; do
        (( attempts += 1 ))
        [[ $attempts -lt 150 && $(docker inspect -f '{{.State.Running}}' erpnext-smoke) == true ]] || return 1
        sleep 4
    done
    docker exec erpnext-smoke env -u FRAPPE_DB_PASSWORD runuser -u frappe -- bench --site "$site" list-apps | tee /tmp/erpnext-installed-apps
    grep -Eq '^erpnext[[:space:]]' /tmp/erpnext-installed-apps
    grep -Eq '^hrms[[:space:]]' /tmp/erpnext-installed-apps
    asset=$(docker exec erpnext-smoke find -L sites/assets/hrms/dist -name '*.js' -type f -print -quit)
    curl -fsS -H "Host: $site" -o /dev/null "$base/${asset#sites/}"
    curl -fsS -H "Host: $site" "$base/socket.io/?EIO=4&transport=polling" | grep -q '"sid"'
}

start_app
check_app
docker rm -f erpnext-smoke
unset RFP_SITE_ADMIN_PASSWORD FRAPPE_DB_PASSWORD
start_app
check_app
