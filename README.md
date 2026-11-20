# ERPNext v16 and HRMS on Railway

GitHub Actions builds and tests the Linux amd64 image and publishes it to GHCR. Railway runs Nginx, Gunicorn, Socket.IO, a worker serving short/default/long queues, and the scheduler under Supervisor. MariaDB and Redis run separately. The app volume holds site configuration, files, and bootstrap state. MariaDB needs its own persistent storage.

| App | Latest stable v16 on November 20, 2026 | Dependency check |
| --- | --- | --- |
| [Frappe](https://github.com/frappe/frappe/releases/tag/v16.60.2) | 16.60.2 | Python 3.14 |
| [ERPNext](https://github.com/frappe/erpnext/releases/tag/v16.60.0) | 16.60.0 | Frappe >=16.60.0,<17 |
| [HRMS](https://github.com/frappe/hrms/releases/tag/v16.60.0) | 16.60.0 | Frappe >=16.60.0,<17 and ERPNext >=16.50.0,<17 |

The [HRMS release requirements](https://github.com/frappe/hrms/blob/v16.60.0/pyproject.toml) and [version-16 branch requirements](https://github.com/frappe/hrms/blob/version-16/pyproject.toml) matched when selected. Builds verify checkout commits from `versions.json` and `apps.json`. Builder and runtime images are pinned by digest. Package resolution through apt, pip, and Yarn can still vary where upstream dependencies are unlocked. Use the published image digest when exact artifact identity matters.

This repo adapts [SpaceCode's separated Railway setup](https://github.com/thspacecode/erpnext-docker/tree/975a8c506a2e33f50899dbb897edced423c852d7/setup-railway-separated) and the [official Frappe layered build](https://github.com/frappe/frappe_docker/blob/main/images/layered/Containerfile). The separated recipe uses a moving prebuilt tag. Using pinned official builder/runtime images lets the build verify both core app commits and compile all assets with HRMS. Startup preserves the `built_sites` links, adds failure tracking for first-time provisioning, and runs Nginx under Supervisor. Root sets the top-level volume ownership and starts Supervisor and the Nginx master. Nginx workers and all Frappe processes run as `frappe`. One worker reduces memory use. A long job can delay short jobs.

## Build and publish

Enable GitHub Actions. Repository or organization policy must permit the workflow's `contents: read` and `packages: write` permissions and the actions it references. The automatic `GITHUB_TOKEN` publishes to GHCR. If the package already exists, grant this repository write access under the package's Actions access settings.

```powershell
git branch -M main
git add --all
git commit -m "Build pinned ERPNext v16 and HRMS image for Railway"
git push -u origin main
```

Pushes to `main` trigger **Actions → Build and publish ERPNext**. To run it manually, select **Run workflow → main**. CI builds the image and tests fresh MariaDB-backed provisioning, ERPNext/HRMS installation, static assets, Socket.IO, and a new container on the same sites volume without bootstrap credentials. CI publishes after those checks pass. Copy `ghcr.io/<owner>/erpnext-railway:sha-<full-git-sha>` or the digest from the run summary. The version and `latest` tags move. A rerun of the same commit can update its SHA tag, so record the digest.

Railway Free, Trial, and Hobby require an anonymously pullable image. In **GitHub → Packages → erpnext-railway → Package settings**, make the package public only if all bundled code can be shared. **A public image exposes every bundled app and asset, including private app source.** For a private package, Railway Pro supports a GitHub classic PAT with `read:packages` and access to the package. [Railway private registry documentation](https://docs.railway.com/builds/private-registries)

## Set up a new Railway project

Free allows three services, 512 MB RAM per service, and one 0.5 GB volume per project. The fully persistent all-Railway layout needs Hobby or above. To try Free, use the app volume, one Redis service, and a new persistent external MariaDB reachable over a trusted private network. A public external DB requires separately configured and verified MariaDB TLS. CI verifies the private-network topology. Bootstrap may exceed Free memory, and continuous queue polling can consume the Free credit. [Free limits](https://docs.railway.com/pricing/free-plan) · [Volume limits](https://docs.railway.com/volumes/reference)

1. In the **new** Railway project, add a Docker Image service named `MariaDB` using `mariadb:11.8`. Mount a volume at `/var/lib/mysql`. Set a new random `MARIADB_ROOT_PASSWORD` and set `MARIADB_ROOT_HOST=%` for provisioning over private TCP. Keep public networking disabled. MariaDB initializes its system tables on the empty volume. Bench creates the site database and scoped database user.
2. Create `RedisCache` and `RedisQueue` from Railway's Redis template, or create one service named `Redis` for both. Keep public TCP proxies disabled and use the template's private authenticated `REDIS_URL`. For shared Redis, use database 0 for the cache and database 1 for the queue, and use the `noeviction` policy so queue entries cannot be evicted. Use AOF and persistent storage at `/data` if pending jobs must survive Redis replacement. CI uses Redis 6.2. Pin validated DB and Redis image digests for production.
3. Add `ERPNext` as a Docker Image service with the GHCR SHA tag. Attach a volume at `/home/frappe/frappe-bench/sites`. Set one replica, health check path `/api/method/ping`, and timeout 900 seconds. Generate a public domain under **Settings → Networking** and target port 8080, or the configured `PORT`. Set the variables below and deploy. Keep the original site name stable after provisioning.
4. The GHCR image supplies the entrypoint and command. Configure health checks and replica count in the Railway dashboard. For an optional repository build, the included `railway.json` uses root `/` and Dockerfile `./Dockerfile`. Use the GHCR source for the requested GitHub Actions build path.

| ERPNext variable | When needed | Railway value |
| --- | --- | --- |
| `RFP_DOMAIN_NAME` | Always | Public hostname, lowercase without scheme or port |
| `FRAPPE_DB_HOST` | Always | `${{MariaDB.RAILWAY_PRIVATE_DOMAIN}}` or new external DB hostname |
| `FRAPPE_DB_PORT` | Optional | Defaults to `3306` |
| `FRAPPE_DB_PASSWORD` | Bootstrap only, secret | `${{MariaDB.MARIADB_ROOT_PASSWORD}}` |
| `RFP_DB_ROOT_USER` | Optional at bootstrap | Defaults to `root`. Needs create database and grant privileges. |
| `RFP_SITE_ADMIN_PASSWORD` | Bootstrap only, secret | New strong password for Administrator |
| `FRAPPE_REDIS_CACHE` | Always, secret | `${{RedisCache.REDIS_URL}}` |
| `FRAPPE_REDIS_QUEUE` | Always, secret | `${{RedisQueue.REDIS_URL}}`. Socket.IO uses the same Redis endpoint. |
| `PORT` | Optional/platform supplied | Defaults to `8080`. Match domain target port. |

With one Redis service use `${{Redis.REDIS_URL}}/0` and `${{Redis.REDIS_URL}}/1`, provided the template URL ends at the port. If the URL already includes a path, construct two complete private URLs with the intended DB numbers. Leave `FRAPPE_DB_USER`, `FRAPPE_DB_NAME`, and `FRAPPE_DB_SOCKET` unset. Bench stores the generated site database credentials in the mounted `site_config.json`. The startup script removes the provisioning password from the application process environment because Frappe treats it as a DB override. Remove both bootstrap password variables from the app service after successful provisioning and redeploy to verify persistence.

## Verify the site

Sign in at the Railway HTTPS domain as `Administrator`, complete the setup wizard, and open the HR workspace. In an ERPNext Railway SSH session, run:

```bash
cd /home/frappe/frappe-bench
unset FRAPPE_DB_PASSWORD
site="$RFP_DOMAIN_NAME"
runuser -u frappe -- bench --site "$site" list-apps
curl -fsS "https://$site/api/method/ping"
```

Expect `frappe`, `erpnext`, `hrms`, and a pong response. Check that assets load and the browser establishes a Socket.IO connection.

## Add apps and upgrade

Add ordered entries in `apps.json` with `name` (Bench app directory name), `url` (HTTPS GitHub URL without credentials or a `.git` suffix), `ref` (tag or named Git ref), `commit` (the full SHA), and `install_on_site` (boolean for fresh sites). List app dependencies first. For a private GitHub repo, set the repository Actions secret `APP_GIT_TOKEN` to a narrowly scoped read-only token. BuildKit mounts the token and Git reads it through a GitHub-only credential helper. The final image contains the app code.

For a core upgrade, verify upstream requirements and change the refs and SHAs in `versions.json`. Mirror HRMS changes in `apps.json`. Push to `main` and save the tested SHA tag and digest. CI exercises fresh initialization. Rehearse any upgrade against a restored copy of your site before changing production.

1. Schedule downtime. Enable maintenance mode with `bench --site "$site" set-maintenance-mode on`, disable the scheduler with `bench --site "$site" disable-scheduler`, and allow in-flight jobs to finish. Run these Bench commands as `frappe`, as in the examples below. Take the backups below after writes have stopped.
2. In Railway, select the new SHA image while preserving the volume. Temporarily clear the HTTP health check and set Start Command to `/usr/local/bin/railway-entrypoint.sh sleep infinity`. If the service retains the image entrypoint with the override, `sleep infinity` alone is sufficient. Deploy and confirm SSH access to the new container.
3. Run the migration once, then explicitly install any newly added app you want on this existing site.

   ```bash
   cd /home/frappe/frappe-bench
   unset FRAPPE_DB_PASSWORD
   site="$RFP_DOMAIN_NAME"
   runuser -u frappe -- bench --site "$site" migrate
   # Only for a newly added app:
   # runuser -u frappe -- bench --site "$site" install-app YOUR_APP
   runuser -u frappe -- bench --site "$site" list-apps
   runuser -u frappe -- bench --site "$site" enable-scheduler
   runuser -u frappe -- bench --site "$site" set-maintenance-mode off
   ```

4. Clear the Start Command override, restore the health check, and redeploy the same SHA. Verify login, HRMS, and a queued job. If rolling back before schema or app changes, switch back to the old image and restore maintenance and scheduler settings. After database changes, restore the matching pre-upgrade DB and site files under the previous image.

## Back up and restore

Run in ERPNext Railway SSH. Copy backups, the site configuration including its encryption key, and the bootstrap marker to encrypted storage outside Railway. Record the image digest. Configure Railway snapshots where available and stop writes when taking paired app and database snapshots.

```bash
cd /home/frappe/frappe-bench
unset FRAPPE_DB_PASSWORD
site="$RFP_DOMAIN_NAME"
runuser -u frappe -- bench --site "$site" backup --with-files
ls -lh "sites/$site/private/backups"
```

Test restores in an isolated project with the matching image and site name. Provision a fresh destination and keep it in maintenance with scheduling stopped. Copy the SQL and archives into a directory readable by `frappe`. Preserve the destination DB connection settings and restore the original encryption key from the protected configuration backup. Run the restore below. Bench may prompt for the destination database provisioning credentials. Verify files, login, and encrypted fields before switching traffic or enabling scheduling.

```bash
cd /home/frappe/frappe-bench
unset FRAPPE_DB_PASSWORD
runuser -u frappe -- bench --site "$RFP_DOMAIN_NAME" restore /tmp/backup.sql.gz \
  --with-public-files /tmp/public-files.tar --with-private-files /tmp/private-files.tar
```

## Troubleshoot

- **Image pull denied** — Verify the exact tag, package visibility, and any Pro registry credentials.
- **Site fails before first start** — Check the volume mount, DB TCP access and privileges, Redis URLs, and provisioning secrets. For a partial first attempt, inspect the marker `sites/.bootstrap` and the DB using a maintenance shell. Snapshot before recovery. For a disposable failed test, retry with a fresh volume and DB. To recover a partial site, complete missing steps and write `ready <site>` to the marker only after verifying the apps, default site, and scheduler.
- **502 or health check timeout** — Check Supervisor output for Gunicorn and Redis failures, the public port, and available memory. A killed bootstrap can leave partial state.
- **Asset 403 or 404** — Verify the links in `sites/` target `built_sites/`. Use `namei -l` on the affected path. Nginx workers run as `frappe`. Correct only the affected permissions. Missing compiled assets require a new image.
- **Delayed jobs** — Check Redis connectivity, scheduler state, queue depth, and service memory. A long job can occupy the shared worker.
