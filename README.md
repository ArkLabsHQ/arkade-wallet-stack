# Arkade Wallet Stack

A turnkey `docker compose` stack for **wallet providers who want to offer Arkade** to
their users. It bundles four provider-side services behind a single automatic-HTTPS
edge, configured by one `.env` and launched by one script.

This stack **connects to an existing, hosted Arkade Service** — it does not run its own.
You bring the endpoints of the Arkade Service you integrate with (from your operator, e.g.
Ark Labs); the stack runs the value-added services your wallet users talk to.

---

## What's in the stack

| Service | What it does | Public endpoint |
|---|---|---|
| **fulmine** (delegate mode) | Runs as a **delegate**: renews users' VTXOs so their funds don't expire while they're offline. | `delegate.<domain>` |
| **lnurl-server** | LNURL-pay / Lightning Address service. Users receive Lightning payments into their Arkade wallet. | `lnurl.<domain>` |
| **covclaimd** | Non-custodial covenant-claim daemon: automatically claims preimage-locked VTXOs. Holds no funds and no wallet. | `covclaim.<domain>` |
| **contract-backup** ([bucket-sync-server](https://github.com/Kukks/bucket-sync-server)) | End-to-end-encrypted backup sync. Stores only ciphertext; wallets authenticate with their own secp256k1 key. | `backup.<domain>` |

Supporting containers: **Caddy** (TLS/reverse proxy) and **Postgres** (storage for
contract-backup only).

Upstream projects: [fulmine](https://github.com/ArkLabsHQ/fulmine) ·
[lnurl-server](https://github.com/ArkLabsHQ/lnurl-server) ·
[covclaimd](https://github.com/arkade-os/covclaimd) ·
[bucket-sync-server](https://github.com/Kukks/bucket-sync-server)

## Architecture

```
                  ┌──────────── Caddy (:80/:443, automatic HTTPS) ────────────┐
 Internet ───────▶│ delegate.<d>   lnurl.<d>   backup.<d>   covclaim.<d>       │
                  └────┬────────────┬────────────┬────────────┬───────────────┘
                       ▼            ▼            ▼            ▼
                 fulmine:7002   lnurl:3000   backup:8080  covclaimd:7071
                 (delegate)     (LNURL/SSE)     │            (REST)
                 fulmine:7001 ── loopback only   ▼
                 (admin/UI)                   postgres:5432 (internal)
                       │                                     │
                       │  external — you set these in .env   │
                       ▼                                     ▼
             Arkade Service + Esplora            Arkade Service + Emulator
```

The services do **not** form a mesh — each is dialed into by the end-user wallet. The only
shared external dependencies are the **Arkade Service** (used by fulmine and covclaimd) and
an **Esplora** chain API (used by fulmine). Caddy is the sole ingress.

## Prerequisites

- A **Linux server** with a public IP (a small VPS is fine). Everything installs via
  `setup.sh`; you don't need Docker preinstalled.
- A **domain** you control, so you can create four subdomain DNS records.
- Endpoints for the **Arkade Service** you're integrating with:
  - its URL (for fulmine) and its gRPC address (for covclaimd),
  - a **covenant emulator** gRPC address (for covclaimd),
  - an **Esplora**-compatible chain API URL (a public one such as `https://mempool.space/api` works).

> **Architecture note:** the `contract-backup` image is published for `linux/amd64` only.
> On an `arm64` host, build it from source — see [Caveats](#caveats).

## Quickstart

```bash
git clone https://github.com/ArkLabsHQ/arkade-wallet-stack.git
cd arkade-wallet-stack
./setup.sh
```

`setup.sh` will:

1. Install any missing prerequisites (git, Docker Engine, the Compose plugin).
2. Prompt you for the required values and **generate all secrets** into `.env` and
   `secrets/fulmine_password`.
3. Pull the images and start the stack.

Then finish the two manual steps it prints: create the **DNS records** and perform the
**one-time fulmine wallet creation** (both detailed below).

Prefer to configure by hand? Copy `.env.example` to `.env`, fill it in, and run `make up`.

## Configuration

All configuration lives in `.env` (git-ignored). `setup.sh` writes it for you; these are the keys:

| Key | Required | Description |
|---|---|---|
| `BASE_DOMAIN` | yes | Base domain. All four service subdomains derive from it. |
| `ACME_EMAIL` | yes | Email Caddy uses to register Let's Encrypt certificates. |
| `ARKADE_SERVER_URL` | yes | Arkade Service as a URL (used by fulmine), e.g. `https://arkd.example.com`. |
| `COVCLAIM_ARK_URL` | yes | The **same** Arkade Service as a gRPC address (used by covclaimd), e.g. `arkd.example.com:7070`. |
| `COVCLAIM_EMULATOR_URL` | yes | Covenant emulator gRPC address (used by covclaimd). |
| `ESPLORA_URL` | yes | Esplora chain API base URL (used by fulmine). |
| `LNURL_TOKEN_ENCRYPTION_KEY` | generated | 32-byte hex key encrypting wallet tokens at rest in lnurl-server. |
| `COVCLAIM_SECRET_KEY` | generated | 32-byte hex secp256k1 key for covclaimd. |
| `POSTGRES_PASSWORD` | generated | Password for the bundled Postgres. |
| `FULMINE_DELEGATE_FEE` | default `0` | Fee, in satoshis, the delegate charges per delegation. |

The fulmine **wallet password** is not stored in `.env`; it lives in `secrets/fulmine_password`
(mode 600), which fulmine reads to auto-unlock on startup.

Advanced: pin or upgrade image versions by uncommenting the `*_IMAGE` overrides in
`.env.example`.

## DNS setup

Create four `A` records pointing at your server's public IP:

```
delegate.<BASE_DOMAIN>    →  <server IP>
lnurl.<BASE_DOMAIN>       →  <server IP>
backup.<BASE_DOMAIN>      →  <server IP>
covclaim.<BASE_DOMAIN>    →  <server IP>
```

Once they resolve, Caddy obtains and renews TLS certificates automatically. No certificate
files to manage.

## One-time fulmine wallet creation

The delegate stays offline until a wallet exists and is unlocked. This is a one-time step;
after it, fulmine **auto-unlocks on every restart** using `secrets/fulmine_password`.

The fulmine admin UI is bound to **loopback only** (`127.0.0.1:7001`) — it is never exposed
to the internet. Reach it over an SSH tunnel:

```bash
# your generated wallet password:
cat secrets/fulmine_password

# from your laptop, tunnel to the server's loopback:
ssh -L 7001:127.0.0.1:7001 <this-server>
# then open http://localhost:7001, create the wallet, and unlock it with that password
```

## Day-2 operations

```bash
make ps        # service status
make logs      # follow logs
make update    # pull latest pinned images and recreate changed containers
make down      # stop (keeps volumes / data)
make config    # render the effective compose configuration
make help      # all targets
```

## Security notes

This stack ships **mainnet-safe defaults**:

- **fulmine** keeps macaroon auth **on**. Its admin/API surface is loopback-only; only the
  public delegate API is exposed (through Caddy).
- **lnurl-server** always encrypts wallet tokens at rest — the insecure-storage shortcut is
  never enabled. Its unauthenticated admin API (`:3001`) is **not** exposed.
- **Postgres** is never published to the host; it is reachable only on the internal network.
- Secrets are strong-random and written with tight permissions; `.env` and `secrets/` are
  git-ignored. **Never commit them.**
- All public traffic is TLS-terminated by Caddy.

## Caveats

- **`contract-backup` is `linux/amd64`-only.** On `arm64`, build it from source and point the
  stack at your local image:
  ```bash
  git clone https://github.com/Kukks/bucket-sync-server.git
  docker build -t bucket-sync-server:local -f bucket-sync-server/Dockerfile bucket-sync-server
  # then set BUCKET_SYNC_IMAGE=bucket-sync-server:local in .env
  ```
- **`contract-backup` has no in-container healthcheck.** Its image ships no shell, so health
  is observed at the Caddy edge rather than by Docker.
- **`covclaimd` has no `:latest` tag** — it is pinned to a prerelease (`v0.0.1-rc.0`). Bump
  `COVCLAIMD_IMAGE` when a newer tag is published.
- **Lightning Addresses** default to `user@lnurl.<BASE_DOMAIN>`. To serve bare
  `user@<BASE_DOMAIN>` addresses, add a Caddy route on the apex domain proxying
  `/.well-known/lnurlp/*` to `lnurl-server:3000`.

## Using your own reverse proxy

Caddy is bundled for turnkey TLS. If you already run an edge (Traefik, nginx, etc.), remove
the `caddy` service from `docker-compose.yml`, publish the service ports you need, and route
to them from your existing proxy. The internal service ports are: fulmine delegate `7002`,
lnurl `3000`, contract-backup `8080`, covclaimd REST `7071`.

## Troubleshooting

- **A subdomain won't get a certificate** — confirm its DNS `A` record resolves to this server
  and that ports 80/443 are open. Check `make logs` for Caddy ACME errors.
- **`docker compose up` fails immediately with a variable error** — a required `.env` value or
  the `secrets/fulmine_password` file is missing. Re-run `./setup.sh`.
- **The delegate isn't responding** — verify the fulmine wallet was created and unlocked once
  (see above), and check `docker compose logs fulmine`.

## License

[MIT](LICENSE)
