FROM mcr.microsoft.com/devcontainers/base:ubuntu

ARG PG_VERSION=18

# Install Postgres
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        postgresql-${PG_VERSION} \
        postgresql-${PG_VERSION}-pgtap \
        postgresql-${PG_VERSION}-plpgsql-check \
    && rm -rf /var/lib/apt/lists/*
 
# Listen on all interfaces, and trust loopback connections so connecting
# from inside the container is password-free. The default 'postgres'
# superuser and 'postgres' database are already created by the package.
RUN service postgresql start \
    && PGCONF=$(find /etc/postgresql -name postgresql.conf) \
    && PGHBA=$(find /etc/postgresql -name pg_hba.conf) \
    && echo "listen_addresses = '*'" >> "$PGCONF" \
    && sed -i '1i local all all trust\nhost all all 127.0.0.1/32 trust\nhost all all ::1/128 trust' "$PGHBA" \
    && service postgresql stop
 
# Let the 'vscode' user start/stop postgres without a password prompt
RUN echo "vscode ALL=(ALL) NOPASSWD: /usr/sbin/service postgresql *" \
    > /etc/sudoers.d/vscode-postgres
 
# Default PGUSER so bare `psql` works without -U flags
ENV PGUSER=postgres
 
EXPOSE 5432
