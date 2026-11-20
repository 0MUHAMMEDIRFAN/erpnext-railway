#!/usr/bin/env bash
set -Eeuo pipefail
cd /home/frappe/frappe-bench

for key in RFP_DOMAIN_NAME FRAPPE_DB_HOST FRAPPE_REDIS_CACHE FRAPPE_REDIS_QUEUE; do
    if [[ -z "${!key:-}" ]]; then
        echo "Set $key before starting ERPNext." >&2
        exit 1
    fi
done
if [[ ! "$RFP_DOMAIN_NAME" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ || ${#RFP_DOMAIN_NAME} -gt 253 ]]; then
    echo "RFP_DOMAIN_NAME must be a lowercase hostname without a scheme or port." >&2
    exit 1
fi

export PORT="${PORT:-8080}" FRAPPE_DB_PORT="${FRAPPE_DB_PORT:-3306}" FRAPPE_SOCKETIO_PORT=9000
for port in "$PORT" "$FRAPPE_DB_PORT"; do
    if [[ ! "$port" =~ ^[1-9][0-9]{0,4}$ ]] || (( port > 65535 )); then
        echo "PORT and FRAPPE_DB_PORT must be valid TCP ports." >&2
        exit 1
    fi
done

site_dir="sites/$RFP_DOMAIN_NAME"
state=sites/.bootstrap
if [[ ! -e "$site_dir" && ! -e "$state" ]]; then
    wait-for-it -q -s -t 120 "$FRAPPE_DB_HOST:$FRAPPE_DB_PORT" -- true || {
        echo "MariaDB did not become reachable within 120 seconds." >&2
        exit 1
    }
    runuser -u frappe -- /usr/local/bin/railway-setup.sh
elif [[ ! -s "$site_dir/site_config.json" || ! -f "$state" || "$(cat "$state")" != "ready $RFP_DOMAIN_NAME" ]]; then
    echo "Site is missing configuration or did not finish bootstrap. See the recovery runbook." >&2
    exit 1
fi
unset FRAPPE_DB_PASSWORD RFP_SITE_ADMIN_PASSWORD RFP_DB_ROOT_USER
export FRAPPE_SITE="$RFP_DOMAIN_NAME"
export BENCH_PATH NODE_PATH
BENCH_PATH=$(command -v bench)
NODE_PATH=$(command -v node)

envsubst '$RFP_DOMAIN_NAME $PORT' < /opt/erpnext/temp_nginx.conf > /etc/nginx/conf.d/default.conf
envsubst '$BENCH_PATH $NODE_PATH' < /opt/erpnext/temp_supervisor.conf > /run/erpnext-supervisor.conf
nginx -t
exec /usr/bin/supervisord -c /run/erpnext-supervisor.conf
