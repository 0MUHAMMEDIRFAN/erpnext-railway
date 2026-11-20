#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
cd /home/frappe/frappe-bench

site=$RFP_DOMAIN_NAME
state=sites/.bootstrap
trap 'echo "Site bootstrap failed. Check the logs and the persistent bootstrap marker before retrying." >&2' ERR

required=(RFP_SITE_ADMIN_PASSWORD FRAPPE_DB_PASSWORD)
for key in "${required[@]}"; do
    if [[ -z "${!key:-}" ]]; then
        echo "Set $key for first-time site creation." >&2
        exit 1
    fi
done

# Reserve the attempt before touching the database. Failed attempts require operator review.
(set -o noclobber; printf 'in-progress %s\n' "$site" > "$state")
if [[ ! -e sites/common_site_config.json ]]; then
    printf '%s\n' '{"webserver_host":"http://127.0.0.1","webserver_port":8000}' > sites/common_site_config.json
fi

export FRAPPE_SOCKETIO_PORT=9000
# FRAPPE_DB_PASSWORD overrides site DB credentials in Frappe v16. Save it
# for provisioning and remove it before Bench starts so the site uses its own password.
db_root_password=$FRAPPE_DB_PASSWORD
unset FRAPPE_DB_PASSWORD
bench new-site "$site" --db-type mariadb \
    --db-host "$FRAPPE_DB_HOST" --db-port "$FRAPPE_DB_PORT" \
    --db-root-username "${RFP_DB_ROOT_USER:-root}" --db-root-password "$db_root_password" \
    --mariadb-user-host-login-scope='%' --admin-password "$RFP_SITE_ADMIN_PASSWORD" \
    --install-app erpnext

install_apps=$(jq -r '.apps[] | select(.install_on_site) | .name' /opt/erpnext/apps.json)
while IFS= read -r app; do
    [[ -z "$app" ]] || bench --site "$site" install-app "$app"
done <<< "$install_apps"

bench use "$site"
bench --site "$site" enable-scheduler
printf 'ready %s\n' "$site" > "$state.ready"
mv -f -- "$state.ready" "$state"
echo "Site bootstrap complete for $site."
