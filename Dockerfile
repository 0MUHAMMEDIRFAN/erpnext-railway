# syntax=docker/dockerfile:1
FROM frappe/build:version-16@sha256:554252f0cb51fe512456b201d8d2abd4712f0fc9c9b35a7262e74a5cef6245d5 AS builder
USER frappe
WORKDIR /home/frappe
COPY versions.json apps.json /opt/erpnext/
COPY --chmod=0755 script/build-apps.sh /usr/local/bin/

ARG APP_BUILD_CACHE_BUST=1

RUN --mount=type=secret,id=app_git_token,uid=1000,mode=0400 \
    build-apps.sh
    
FROM frappe/base:version-16@sha256:519d88a206f6d873be36b0cea28f5807461613156e1921b17bd4367cf31f2a44
USER root
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
        nginx supervisor gettext-base util-linux \
    && rm -rf /var/lib/apt/lists/* /etc/nginx/sites-enabled/default \
    && sed -i '/^user /d; /^worker_processes /d' /etc/nginx/nginx.conf \
    && sed -i '1i user frappe root;\nworker_processes 1;' /etc/nginx/nginx.conf
COPY --from=builder --chown=frappe:0 /home/frappe/frappe-bench /home/frappe/frappe-bench
COPY versions.json apps.json /opt/erpnext/
COPY template/*.conf /opt/erpnext/
COPY --chmod=0755 script/railway-*.sh /usr/local/bin/
WORKDIR /home/frappe/frappe-bench
RUN chmod 0711 /home/frappe /home/frappe/frappe-bench \
    && install -d -o frappe -g root logs
ENV HOME=/home/frappe
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["/usr/local/bin/railway-cmd.sh"]
