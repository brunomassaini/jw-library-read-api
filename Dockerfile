FROM rust:1.85-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y build-essential pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*

# Cache dependencies by building a dummy binary first
COPY Cargo.toml ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs && \
    cargo build --release && \
    rm -rf src target/release/deps/jw_library_read_api*

# Build actual source
COPY src ./src
RUN touch src/main.rs && cargo build --release

FROM debian:bookworm-slim

WORKDIR /app

RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/jw-library-read-api .

RUN mkdir -p /app/data

ENV DATABASE_URL=sqlite:///./data/read_status.db

EXPOSE 8000

CMD ["./jw-library-read-api"]
