#!/bin/bash

retooldbPostgresPassword=$(cat /dev/urandom | base64 | head -c 64)

if [ -f ./retooldb.env ]; then
  echo "RetoolDB credentials have already been set"
  exit 1
fi
touch retooldb.env

echo '## Set and generate retooldb postgres credentials' >> docker.env
echo 'RETOOLDB_POSTGRES_HOST=retooldb-postgres' >> docker.env
echo 'RETOOLDB_POSTGRES_DB=postgres' >> docker.env
echo 'RETOOLDB_POSTGRES_USER=root' >> docker.env
echo 'RETOOLDB_POSTGRES_PORT=5432' >> docker.env
echo "RETOOLDB_POSTGRES_PASSWORD=${retooldbPostgresPassword}" >> docker.env
echo '' >> docker.env

echo '## Set and generate retooldb postgres credentials' >> retooldb.env
echo 'POSTGRES_HOST=retooldb-postgres' >> retooldb.env
echo 'POSTGRES_DB=postgres' >> retooldb.env
echo 'POSTGRES_USER=root' >> retooldb.env
echo "POSTGRES_PASSWORD=${retooldbPostgresPassword}" >> retooldb.env
echo 'POSTGRES_PORT=5432' >> retooldb.env
echo '' >> retooldb.env

echo "RetoolDB upgrade script has been run"
