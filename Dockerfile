ARG CRYSTAL_VERSION=1.19.1

FROM crystallang/crystal:${CRYSTAL_VERSION} AS builder

WORKDIR /app
COPY shard.yml shard.lock ./
RUN shards install --production --frozen
COPY src ./src
COPY samples ./samples
RUN mkdir -p /app/bin
RUN crystal build --release src/mzap_cli.cr -o /app/bin/mzap

FROM debian:bookworm-slim

RUN groupadd -r mzap && useradd -r -g mzap -d /app -s /sbin/nologin mzap
WORKDIR /app
COPY --from=builder /app/bin/mzap /app/mzap
COPY --from=builder /app/samples /app/samples
RUN chown -R mzap:mzap /app
USER mzap
ENTRYPOINT ["/app/mzap"]
