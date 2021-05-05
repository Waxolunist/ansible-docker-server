#!/bin/bash

docker-compose exec grafana-pg pg_dump -c -U '{{ vault_grafana_pg_user }}' | gzip -9 > /backup/dump_grafana_`date +%d-%m-%Y"_"%H_%M_%S`.sql.zip

docker-compose exec portus-pg pg_dump -c -U '{{ vault_portus_pg_user }}'  | gzip -9 > /backup/dump_portus_`date +%d-%m-%Y"_"%H_%M_%S`.sql.zip