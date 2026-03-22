# Dokcer Base (docker-base) for local development

A shared Docker infrastructure providing a single [Traefik v3](https://traefik.io/traefik/)
reverse proxy for local development. All your independent projects route through this
instance — no project ever binds host ports directly.

```
Browser (Chrome on Windows)
  └── 127.0.0.1:443  ──►  Traefik (docker-base)
                               ├──► myapp.local   → project-a container
                               ├──► api.local      → project-b container
                               └──► traefik.local  → Traefik dashboard
```

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [First-time setup](#first-time-setup)
3. [Daily usage](#daily-usage)
4. [Connecting another project](#connecting-another-project)
5. [Makefile reference](#makefile-reference)
6. [Configuration](#configuration)
7. [Directory structure](#directory-structure)
8. [WSL2 notes](#wsl2-notes)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Tool | Minimum version | Install |
|------|----------------|---------|
| Docker Engine | 24+ | https://docs.docker.com/engine/install/ |
| Docker Compose v2 | 2.20+ | bundled with Docker Desktop / `docker compose` plugin |
| mkcert | any | `sudo apt install mkcert` / `brew install mkcert` |

Check your versions:

```bash
docker --version
docker compose version
mkcert --version
```

---

## First-time setup

### 1. Clone this repository

```bash
git clone <repo-url> ~/docker-base
cd ~/docker-base
```

### 2. Copy the environment file

```bash
cp .env.example .env
```

Edit `.env` if you need to change the network name or Traefik image tag. The defaults
work for most setups.

### 3. Generate local TLS certificates

```bash
make certs
```

This runs `mkcert -install` (installs a local CA into your OS/browser trust stores)
and generates `certs/local.crt` and `certs/local.key` covering `*.local`, `localhost`,
`127.0.0.1`, and `::1`.

You only need to do this once per machine. The certificates are gitignored.

> **WSL2 / Chrome on Windows:** `mkcert -install` in WSL2 only installs the CA for
> Linux tools. To make Chrome on Windows trust the certificates, you must also install
> the mkcert CA into the **Windows** certificate store — see [WSL2 notes](#wsl2-notes).

### 4. Add the Traefik dashboard domain to the hosts file

**On WSL2 (for Chrome on Windows)** — edit the Windows hosts file as Administrator:

```
C:\Windows\System32\drivers\etc\hosts
```

Add:

```
127.0.0.1   traefik.local
```

**In WSL2 (for Linux tools):**

```bash
echo "127.0.0.1   traefik.local" | sudo tee -a /etc/hosts
```

### 5. Start Traefik

```bash
make up
```

This creates the shared Docker network (`traefik-net`) if it does not exist, then
starts Traefik in detached mode.

### 6. Verify

Open [https://traefik.local](https://traefik.local) in Chrome. You should see the
Traefik dashboard without a certificate warning.

---

## Daily usage

```bash
make up      # Start Traefik
make down    # Stop Traefik (network is kept — downstream projects are unaffected)
make logs    # Follow Traefik logs
make ps      # Check service status
```

---

## Connecting another project

Each independent project needs the following four steps. A complete working example
is available in [`examples/whoami/`](examples/whoami/docker-compose.yml).

### Step 1 — Reference the shared network

In your project's `docker-compose.yml`, declare `traefik-net` as an **external** network:

```yaml
networks:
  traefik-net:
    name: traefik-net   # must match TRAEFIK_NETWORK in docker-base/.env
    external: true
```

### Step 2 — Add Traefik labels to your service

```yaml
services:
  app:
    image: your-image
    networks:
      - traefik-net
    # NO ports: section — Traefik handles all ingress
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.local`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls=true"
      - "traefik.http.services.myapp.loadbalancer.server.port=8080"
      # Optional: apply shared security headers (HSTS, X-Content-Type, etc.)
      - "traefik.http.routers.myapp.middlewares=secure-headers@file"
```

Replace `myapp` with a unique name for your project (must be unique across all
running containers), and `8080` with the port your container actually listens on.

### Step 3 — Add the domain to the Windows hosts file

> On WSL2, your browser runs on Windows. You must add the domain to the **Windows**
> hosts file, not only to the WSL2 `/etc/hosts`.

Open `C:\Windows\System32\drivers\etc\hosts` as **Administrator** and add:

```
127.0.0.1   myapp.local
```

If you also need to reach the domain from within WSL2 (e.g., curl, tests):

```bash
echo "127.0.0.1   myapp.local" | sudo tee -a /etc/hosts
```

### Step 4 — Start your project

```bash
docker compose up -d
```

Visit [https://myapp.local](https://myapp.local) in Chrome.

---

### Complete docker-compose.yml example

```yaml
# myproject/docker-compose.yml

networks:
  traefik-net:
    name: traefik-net
    external: true

services:
  app:
    image: nginx:alpine
    container_name: myapp
    restart: unless-stopped
    networks:
      - traefik-net
    # NO ports: section
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.local`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls=true"
      - "traefik.http.services.myapp.loadbalancer.server.port=80"
      - "traefik.http.routers.myapp.middlewares=secure-headers@file"
```

### Multiple domains for the same project

To expose a project on more than one domain, use a compound `Host()` rule:

```yaml
- "traefik.http.routers.myapp.rule=Host(`myapp.local`) || Host(`api.local`)"
```

Add each domain separately to the Windows hosts file:

```
127.0.0.1   myapp.local
127.0.0.1   api.local
```

### The `secure-headers@file` middleware

This middleware is defined in `traefik/dynamic/middlewares.yml` and is available to
all downstream projects. It adds the following headers to every response:

| Header | Value |
|--------|-------|
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` |
| `X-Content-Type-Options` | `nosniff` |
| `X-XSS-Protection` | `1; mode=block` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |

Reference it in any router label:

```yaml
- "traefik.http.routers.<name>.middlewares=secure-headers@file"
```

### Working example

A complete, ready-to-run example is in [`examples/whoami/`](examples/whoami/docker-compose.yml).

```bash
# 1. Add to the Windows hosts file: 127.0.0.1   whoami.local
# 2. Run:
cd examples/whoami
docker compose up -d
# 3. Visit https://whoami.local in Chrome
```

### Checklist for every new project

- [ ] `docker-base` is running: `make ps`
- [ ] `traefik-net` exists: `docker network ls | grep traefik-net`
- [ ] `traefik-net` declared as external in `docker-compose.yml`
- [ ] Service has `traefik.enable=true` label
- [ ] Router name is unique (not reused by another container)
- [ ] `loadbalancer.server.port` matches the port the container listens on
- [ ] Domain added to the **Windows** hosts file
- [ ] Certificate covers the domain (all `*.local` domains are covered by default)

---

## Makefile reference

| Target | Description |
|--------|-------------|
| `make up` | Create network if absent + start Traefik detached |
| `make down` | Stop Traefik (network is preserved) |
| `make logs` | Follow Traefik container logs |
| `make certs` | Generate / regenerate local TLS certificates |
| `make ps` | Show service status |
| `make clean` | Stop Traefik and optionally remove the shared network |
| `make help` | List all targets |

---

## Configuration

All configuration is done via `.env` (copy from `.env.example`).

| Variable | Default | Description |
|----------|---------|-------------|
| `TRAEFIK_NETWORK` | `traefik-net` | Shared Docker network name |
| `TRAEFIK_IMAGE` | `traefik:v3.6` | Traefik image tag |
| `TRAEFIK_LOG_LEVEL` | `INFO` | Log level (`DEBUG`, `INFO`, `WARN`, `ERROR`) |

### Changing the network name

If you change `TRAEFIK_NETWORK`, you must use the same value in every downstream
project's `docker-compose.yml`:

```yaml
networks:
  traefik-net:
    name: your-custom-network-name   # matches TRAEFIK_NETWORK
    external: true
```

### Adding more domains to the TLS certificate

The default certificate covers `*.local`. If you need domains outside this wildcard
(e.g., `myapp.dev`), edit `scripts/generate-certs.sh` to add them to the `mkcert`
command, then re-run `make certs` and restart Traefik (`make down && make up`).

---

## Directory structure

```
docker-base/
├── .env.example              # Environment variable template
├── .gitignore
├── Makefile
├── README.md
├── docker-compose.yml        # Traefik service definition
│
├── traefik/
│   ├── traefik.yml           # Static configuration (entrypoints, providers)
│   └── dynamic/
│       ├── tls.yml           # Default TLS certificate store
│       └── middlewares.yml   # Shared HTTP middlewares (secure-headers)
│
├── certs/                    # Generated certificates (gitignored)
│   ├── local.crt
│   └── local.key
│
├── scripts/
│   └── generate-certs.sh     # mkcert wrapper
│
├── examples/
│   └── whoami/
│       └── docker-compose.yml  # Minimal downstream project example
│
└── docs/
    ├── projects/
    │   └── traefik-base.md   # Project brief
    └── architecture/
        └── traefik-base-architecture.md
```

---

## WSL2 notes

This setup runs on Windows with WSL2. The browser is **Chrome on Windows**.

### 1. Hosts file — Windows (required for browser access)

Chrome resolves DNS on the Windows side. Add every `.local` domain to the
**Windows** hosts file, not the WSL2 one:

```
C:\Windows\System32\drivers\etc\hosts
```

Open that file in Notepad (or any editor) **as Administrator** and add lines such as:

```
127.0.0.1   traefik.local
127.0.0.1   myapp.local
127.0.0.1   api.local
```

WSL2 localhost forwarding means `127.0.0.1` in the Windows hosts file correctly
reaches services listening inside WSL2.

### 2. mkcert CA — Windows certificate store (required for Chrome to trust the cert)

`mkcert -install` inside WSL2 only installs the CA for Linux tools. Chrome on Windows
reads the **Windows** certificate store. The CA root is already installed there for
this machine (the `rootCA.pem` from `$(mkcert -CAROOT)` was imported into
`certmgr.msc` → Trusted Root Certification Authorities).

If you are setting this up on a new machine:

1. Inside WSL2, find the CA root path:
   ```bash
   mkcert -CAROOT
   # e.g. /home/romain/.local/share/mkcert
   ```
2. Copy `rootCA.pem` to a Windows-accessible location (e.g., your Windows Desktop).
3. Open `certmgr.msc` on Windows (Win+R → `certmgr.msc`).
4. Navigate to **Trusted Root Certification Authorities → Certificates**.
5. Right-click → **All Tasks → Import** and import the `rootCA.pem` file.
6. Restart Chrome.

### 3. Docker context

Ensure you are using Docker Desktop with the WSL2 backend, or a native Docker Engine
installed inside WSL2.

---

## Troubleshooting

### `make up` fails with "port is already allocated"

Another service is already using port 80 or 443. Find and stop it:

```bash
sudo ss -tlnp | grep -E ':80|:443'
```

Common culprits: Apache, nginx, another Traefik instance.

### Certificate warning in Chrome despite running `make certs`

- Confirm the mkcert CA is installed in the **Windows** certificate store
  (see [WSL2 notes](#wsl2-notes) above)
- Restart Chrome completely after importing the CA
- Confirm `make certs` completed without errors

### A downstream project is not being picked up by Traefik

1. Confirm `docker-base` is running: `make ps`
2. Confirm the downstream container is on `traefik-net`:
   ```bash
   docker inspect <container-name> | grep -A5 Networks
   ```
3. Confirm `traefik.enable=true` label is set on the container
4. Check Traefik logs: `make logs`
5. Open the dashboard at `https://traefik.local` and look under HTTP → Routers

### The Traefik dashboard shows no routers for my service

- The `Host(...)` rule hostname must exactly match what is in the **Windows** hosts file
- The container must be on the `traefik-net` network (not just a project-local network)
- The `traefik.http.services.<name>.loadbalancer.server.port` must match the port
  the container actually listens on
- The router name (e.g., `myapp` in `traefik.http.routers.myapp`) must be unique
  across all containers

### `make clean` — I accidentally removed the network

Re-create it and restart everything:

```bash
docker network create traefik-net
make up
# Restart all downstream projects
```
