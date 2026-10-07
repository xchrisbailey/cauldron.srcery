# Nightly off-box backups of Postgres and the photo volume (deploy/README.md).
# Same Postgres major as the database, so pg_dump matches the server.
# Build context is this directory.
FROM postgres:17-alpine@sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24
RUN apk add --no-cache restic
COPY backup.sh nightly.sh restore.sh /usr/local/bin/
ENTRYPOINT []
CMD ["/usr/local/bin/nightly.sh"]
