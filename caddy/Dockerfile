# Caddy with the rate-limit plugin (github.com/mholt/caddy-ratelimit), used to
# throttle the public payment-push /register endpoint at the edge.
FROM caddy:2-builder AS builder
RUN xcaddy build --with github.com/mholt/caddy-ratelimit

FROM caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
