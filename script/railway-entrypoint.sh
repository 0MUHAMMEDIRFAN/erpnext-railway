#!/usr/bin/env bash
set -Eeuo pipefail
cd /home/frappe/frappe-bench

if [[ -n "${RAILWAY_ENVIRONMENT_ID:-}" && "${RAILWAY_VOLUME_MOUNT_PATH:-}" != "$PWD/sites" ]]; then
    echo "Mount the Railway sites volume at $PWD/sites before starting." >&2
    exit 1
fi

# Railway mounts the top-level volume directory as root.
install -d sites
chown frappe:0 sites
chmod 0750 sites
for item in assets apps.json apps.txt; do
    runuser -u frappe -- ln -sfnT "$PWD/built_sites/$item" "sites/$item"
done
exec "$@"
