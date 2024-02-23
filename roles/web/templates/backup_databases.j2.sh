#!/bin/bash

cd {{ docker_base_path }}

docker-compose exec grafana-pg pg_dump -c -U '{{ vault_grafana_pg_user }}' | gzip -9 > /backup/dump_grafana_`date +%d-%m-%Y"_"%H_%M_%S`.sql.zip

docker-compose exec portus-pg pg_dump -c -U '{{ vault_portus_pg_user }}'  | gzip -9 > /backup/dump_portus_`date +%d-%m-%Y"_"%H_%M_%S`.sql.zip

# https://www.liquidweb.com/kb/mysql-backup-database/
# cat backup.sql | docker exec -i CONTAINER /usr/bin/mysql -u root --password=root DATABASE
docker-compose exec scmatzen-db mysqldump -u "{{ vault_scmatzen_db_user }}" --password="{{ vault_scmatzen_db_password }}" scmatzen | gzip -9 > /backup/dump_scmatzen_`date +%d-%m-%Y"_"%H_%M_%S`.sql.zip

# find /backup -type f -mtime +30 -delete 