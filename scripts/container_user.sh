#!/bin/bash

ssh devops@v-collaborate.com "
    printf '%-30s %-6s %s\n' 'CONTAINER' 'UID' 'USER'
    printf '%-30s %-6s %s\n' '---------' '---' '----'
    docker ps --format '{{.Names}}' | while read name; do
      uid=\$(docker exec \$name id -u 2>/dev/null || echo '?')
      user=\$(docker exec \$name id -un 2>/dev/null || echo '?')
      printf '%-30s %-6s %s\n' \"\$name\" \"\$uid\" \"\$user\"
    done
  "