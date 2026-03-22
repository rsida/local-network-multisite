# Architecture: Traefik Base Infrastructure

## 1. Repository Structure

```
docker-base/
├── .env                          # Local overrides (gitignored)
├── .env.example                  # Documented environment variables template
├── .gitignore
├── Makefile                      # Developer convenience targets
├── README.md
├── docker-compose.yml            # Traefik service definition
│
├── traefik/
│   ├── traefik.yml               # Static configuration (entrypoints, providers, TLS)
│   └── dynamic/
│       ├── tls.yml               # TLS store and default certificate definition
│       └── middlewares.yml       # Shared middlewares (e.g., https-redirect)
│
├── certs/                        # Local TLS certificates (gitignored)
│   ├── local.crt                 # Certificate (covers *.local + localhost)
│   └── local.key                 # Private key
│
├── scripts/
│   └── generate-certs.sh         # mkcert wrapper to produce certs/local.{crt,key}
│
└── docs/
    ├── projects/
    │   └── traefik-base.md       # Project brief
    └── architecture/
        └── traefik-base-architecture.md  # This document
```

## 2. Docker Network Design

### Shared External Network

A single Docker bridge network named `traefik-net` is created once and declared
as **external** in every `docker-compose.yml` that participates in the ecosystem.

```
Host
 ├── :80  ──► Traefik container (traefik-net)
 └── :443 ──► Traefik container (traefik-net)
                   │
                   ├──► service-a container (traefik-net, labels only)
                   └──► service-b container (traefik-net, labels only)
```

**Creation (one-time, idempotent):**
```bash
docker network create traefik-net
```

This is handled automatically by `make up` / the Makefile before `docker compose up`.

**Why external?** Declaring the network external means its lifecycle is independent
of any single `docker compose` project. Any project can reference it without
owning it. If `docker-base` is torn down with `docker compose down`, the network
persists so downstream projects are not disrupted.

### Network Name Configuration

The network name is controlled by the `TRAEFIK_NETWORK` variable in `.env`
(default: `traefik-net`). All downstream projects must use the same value.

## 3. Traefik Static Configuration (`traefik/traefik.yml`)

```yaml
# traefik/traefik.yml
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: false          # Dashboard served via HTTPS through Traefik itself

log:
  level: INFO

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true
  websecure:
    address: ":443"
    http:
      tls: {}              # Default TLS — certificate comes from dynamic config

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false   # Services must opt-in via traefik.enable=true label
    network: traefik-net      # Traefik only uses this network for routing
  file:
    directory: /etc/traefik/dynamic
    watch: true              # Hot-reload dynamic config changes
```

Key decisions:
- `exposedByDefault: false` — prevents accidental exposure of containers
- HTTP→HTTPS redirect is done at entrypoint level (global, no per-route label needed)
- `providers.docker.network` pins routing to `traefik-net` even if containers are
  on multiple networks

## 4. Traefik Dynamic Configuration

### `traefik/dynamic/tls.yml` — TLS Store

```yaml
tls:
  stores:
    default:
      defaultCertificate:
        certFile: /etc/traefik/certs/local.crt
        keyFile:  /etc/traefik/certs/local.key
```

This sets the wildcard/SAN certificate as the default for all HTTPS routes.
No per-route TLS configuration is needed in downstream projects.

### `traefik/dynamic/middlewares.yml` — Shared Middlewares

```yaml
http:
  middlewares:
    secure-headers:
      headers:
        stsSeconds: 31536000
        stsIncludeSubdomains: true
        contentTypeNosniff: true
        browserXssFilter: true
```

Optional middleware that downstream projects can reference by name
(`traefik-base-secure-headers@docker` or `secure-headers@file`).

## 5. Certificate Management

### Tool: mkcert

`mkcert` installs a local CA into the system/browser trust stores and issues
certificates signed by that CA. The result is HTTPS with no browser warnings.

### Workflow

```
scripts/generate-certs.sh
  1. Checks mkcert is installed (errors with install hint if not)
  2. Runs: mkcert -install   (idempotent, installs CA once)
  3. Runs: mkcert -cert-file certs/local.crt \
                  -key-file  certs/local.key \
                  "*.local" localhost 127.0.0.1 ::1
  4. Prints instructions for /etc/hosts entries
```

### Certificate Coverage

The certificate covers:
- `*.local` — all single-label `.local` subdomains (e.g., `myapp.local`, `api.local`)
- `localhost`, `127.0.0.1`, `::1` — for direct access

**Limitation:** `*.local` does not cover second-level wildcards like `*.api.local`.
Projects needing deeper nesting should add their specific domain to the cert SAN list
or regenerate with additional domains.

### Storage

`certs/` is gitignored. Each developer runs `make certs` once after cloning.

## 6. `docker-compose.yml` Design

```yaml
networks:
  traefik-net:
    name: ${TRAEFIK_NETWORK:-traefik-net}
    external: true

services:
  traefik:
    image: traefik:v3.6
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./traefik/dynamic:/etc/traefik/dynamic:ro
      - ./certs:/etc/traefik/certs:ro
    networks:
      - traefik-net
    labels:
      - "traefik.enable=true"
      # Dashboard router
      - "traefik.http.routers.dashboard.rule=Host(`traefik.local`)"
      - "traefik.http.routers.dashboard.entrypoints=websecure"
      - "traefik.http.routers.dashboard.tls=true"
      - "traefik.http.routers.dashboard.service=api@internal"
      - "traefik.http.routers.dashboard.middlewares=secure-headers@file"
```

Design rationale:
- `restart: unless-stopped` — survives host reboots
- Docker socket mounted read-only — reduces attack surface
- All config files mounted read-only — no Traefik writes to host
- `certs/` mounted read-only — Traefik reads but never writes certificates
- Dashboard exposed at `traefik.local` over HTTPS

## 7. Makefile Targets

| Target       | Description                                                         |
|--------------|---------------------------------------------------------------------|
| `make up`    | Create network if absent, then `docker compose up -d`              |
| `make down`  | `docker compose down` (network is NOT removed — intentional)       |
| `make logs`  | `docker compose logs -f traefik`                                   |
| `make certs` | Run `scripts/generate-certs.sh` to (re)generate local certificates |
| `make ps`    | `docker compose ps`                                                 |
| `make clean` | `make down` then optionally remove network (with confirmation)     |

## 8. Environment Variables (`.env.example`)

| Variable           | Default       | Description                                      |
|--------------------|---------------|--------------------------------------------------|
| `TRAEFIK_NETWORK`  | `traefik-net` | Name of the shared Docker network                |
| `TRAEFIK_IMAGE`    | `traefik:v3.6`| Traefik Docker image tag                         |
| `TRAEFIK_LOG_LEVEL`| `INFO`        | Log verbosity (`DEBUG`, `INFO`, `WARN`, `ERROR`) |

## 9. Downstream Project Integration Pattern

A downstream project needs to:

1. Reference the shared network as external
2. Add `traefik.enable=true` and routing labels to its service(s)
3. Add the entry to `/etc/hosts` for local DNS resolution

### Minimal `docker-compose.yml` for a downstream project

```yaml
# downstream-project/docker-compose.yml
networks:
  traefik-net:
    name: traefik-net   # Must match TRAEFIK_NETWORK in docker-base
    external: true

services:
  app:
    image: nginx:alpine
    networks:
      - traefik-net
    # NO ports: section — Traefik handles all ingress
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.local`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls=true"
      # Optional: explicit port if the image exposes multiple
      - "traefik.http.services.myapp.loadbalancer.server.port=80"
```

### Hosts file entries (WSL2 / Chrome on Windows)

Add every project domain to the **Windows** hosts file (requires Administrator):

```
# C:\Windows\System32\drivers\etc\hosts
127.0.0.1   myapp.local traefik.local
```

Also add them to the WSL2 `/etc/hosts` if you need curl/test access from inside WSL2:

```bash
echo "127.0.0.1   myapp.local" | sudo tee -a /etc/hosts
```

### Multiple domains for one project

Use a compound `Host()` rule — no extra labels are needed:

```yaml
- "traefik.http.routers.myapp.rule=Host(`myapp.local`) || Host(`api.local`)"
```

### Checklist for adding a new project

- [ ] `docker-base` is running (`make up` in this repo)
- [ ] `traefik-net` network exists (`docker network ls | grep traefik-net`)
- [ ] Downstream `docker-compose.yml` references `traefik-net` as external
- [ ] Service has `traefik.enable=true` label
- [ ] Router name is unique across all running containers
- [ ] `Host(...)` rule matches an entry in the **Windows** hosts file
- [ ] Certificate covers the domain (all `*.local` domains are covered by default)

## 10. Security Considerations

### Safe for Local Development

- Self-signed certificates via mkcert are trusted only in the local CA store — not
  globally trusted by external parties
- Docker socket access is read-only
- `exposedByDefault: false` prevents accidental service exposure

### What to Avoid

- **Do not** commit `certs/` or `.env` to version control
- **Do not** use this setup for production — no ACME / Let's Encrypt is configured
- **Do not** expose the Traefik dashboard publicly; `traefik.local` is host-only
- **Do not** share the mkcert CA key; it is stored in `$(mkcert -CAROOT)` on the host

### WSL2 / Chrome on Windows

The browser used is Chrome on Windows. Two things are required:

1. **Hosts file**: Add `.local` domains to the **Windows** hosts file at
   `C:\Windows\System32\drivers\etc\hosts` (requires Administrator). WSL2 localhost
   forwarding means `127.0.0.1` correctly reaches services inside WSL2.

2. **Certificate trust**: Chrome on Windows reads the Windows certificate store.
   The mkcert CA (`rootCA.pem` from `$(mkcert -CAROOT)`) must be imported into
   `certmgr.msc` → Trusted Root Certification Authorities. This has already been
   done on this machine. For new machines, see the README WSL2 notes section.
