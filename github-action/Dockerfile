ARG CRYSTAL_VERSION=1.19.1

FROM crystallang/crystal:${CRYSTAL_VERSION} AS builder

WORKDIR /app
COPY shard.yml shard.lock ./
RUN shards install --production --frozen
COPY src ./src
COPY samples ./samples
RUN mkdir -p /app/bin
RUN crystal build --release src/mzap_cli.cr -o /app/bin/mzap

FROM crystallang/crystal:${CRYSTAL_VERSION}

WORKDIR /app
COPY --from=builder /app/bin/mzap /app/mzap
COPY --from=builder /app/samples /app/samples
COPY github-action/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /app/mzap
ENTRYPOINT ["/entrypoint.sh"]
