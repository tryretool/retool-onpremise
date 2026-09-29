# Migrating from MinIO to Garage

Retool has moved from MinIO to [Garage](https://garagehq.deuxfleurs.fr/) for
its bundled development object storage, since the open-source MinIO offering
has been abandoned.

There are three sections: First we setup Garage for existing installations,
next if MinIO was used for data it must be migrated, finally after all
verification is complete, we can cleanup the legacy MinIO install.

## Set up Garage on an existing deployment

### 1. Stop the stack and back up docker.env

```bash
docker compose --profile legacy down --remove-orphans
cp docker.env docker.env.pre-garage
```

### 2. Add the Garage settings to docker.env

```bash
cat >> docker.env << EOF
# Bundled Garage blob storage credentials
GARAGE_DEFAULT_BUCKET=retool-blob-storage
GARAGE_DEFAULT_ACCESS_KEY=GK$(openssl rand -hex 12)
GARAGE_DEFAULT_SECRET_KEY=$(openssl rand -hex 32)
GARAGE_RPC_SECRET=$(openssl rand -hex 32)
EOF
```

**Using an external object store?** Then there's no data to migrate and we
don't need to touch `RR_DEFAULT_S3_*` values, continue with upgrade:

```bash
./upgrade.sh
```

Otherwise, continue.

## Migrate MinIO data

### 3. Point Retool at Garage

Update the values in `docker.env`:

```
RR_DEFAULT_S3_ACCESS_KEY_ID=<the GARAGE_DEFAULT_ACCESS_KEY value>
RR_DEFAULT_S3_SECRET_ACCESS_KEY=<the GARAGE_DEFAULT_SECRET_KEY value>
RR_DEFAULT_S3_ENDPOINT=http://garage:9000
AWS_ENDPOINT_URL=http://garage:9000
```

If any other S3 values still point at MinIO, update them the same way. Leave
the `MINIO_` values alone, the copy needs them.

### 4. Copy the data

Start Garage and the old MinIO side by side, and wait for
`docker compose ps garage` to report `healthy`:

```bash
docker compose --profile legacy up -d garage minio
```

The `rclone` service in `compose.yaml` has both stores preconfigured as
remotes: `old:` is MinIO, `new:` is Garage. List what MinIO holds:

```bash
docker compose run --rm rclone lsf old:
```

It should list `retool-blob-storage`, which already exists in Garage. Sync it
(idempotent, so re-run it if interrupted):

```bash
docker compose run --rm rclone sync old:retool-blob-storage new:retool-blob-storage --progress
```

If any other buckets are present in MinIO, create each one in Garage, grant the
key access, and sync it:

```bash
docker compose exec garage /garage bucket create <bucket>
docker compose exec garage /garage bucket allow --read --write <bucket> --key <GARAGE_DEFAULT_ACCESS_KEY>
docker compose run --rm rclone sync old:<bucket> new:<bucket> --progress
```

### 5. Verify every byte

Re-reads every object from both stores and compares contents. It must report
`0 differences`:

```bash
docker compose run --rm rclone check --download old:retool-blob-storage new:retool-blob-storage
```

If you copied any other buckets, check each one the same way.

### 6. Stop the legacy MinIO and upgrade

```bash
docker compose --profile legacy stop minio
./upgrade.sh
```

Log in to Retool and confirm blob-backed features still read the old data: a
past workflow run's logs, or a previously uploaded file, etc.

## Clean up MinIO

When ready, we can clean up and permanently delete the MinIO service and data.
After, it will no longer be possible to rollback with a `git checkout` of the
previous release and restoring `docker.env.pre-garage`.

```bash
# Names assume an install in retool/. Otherwise, get the volume name with
# `docker compose --profile legacy volumes minio`.
docker compose --profile legacy rm minio
docker volume rm retool_minio-data
```

Then delete `MINIO_ROOT_USER` and `MINIO_ROOT_PASSWORD` from `docker.env`, and
remove `docker.env.pre-garage`, since it contains live secrets.
