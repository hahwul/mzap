FROM crystallang/crystal:1.19.1 AS builder

WORKDIR /app
COPY shard.yml ./
RUN shards install --production
COPY src ./src
COPY samples ./samples
RUN crystal build --release src/mzap_cli.cr -o /app/bin/mzap

FROM crystallang/crystal:1.19.1

WORKDIR /app
COPY --from=builder /app/bin/mzap /app/mzap
COPY --from=builder /app/samples /app/samples
COPY github-action/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /app/mzap
ENTRYPOINT ["/entrypoint.sh"]
