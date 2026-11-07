# herdr-unraid

Run **Herdr / herdr-core** (the terminal runtime for coding agents) in Docker on Unraid, with:

- **SSH** so the Herdr app / TUI on any PC can connect (`herdr --remote`, `herdr machine add`, `hc machine add`)
- **Web GUI** in the browser or on a phone: [Ovis](https://github.com/devswha/ovis) (the community web UI that used to be called `herdr-web-ui`)
- **Fallback web terminal**: `ttyd`, a plain shell in the browser
- Everything persistent in `/mnt/user/appdata/herdr`

---

## 1. What runs where

| Thing | What it is | Installed to (home volume) |
|---|---|---|
| `herdr` | TUI + headless server (`herdr server`) with plugins | `~/.local/bin/herdr` |
| `hc` (herdr-core) | Terminal runtime the Herdr desktop app is built on | `~/.local/bin/herdr-core` + `hc` symlink |
| Ovis | Community web UI: chat + live terminal per agent, PWA, push alerts | `~/.local/share/ovis/app` (git checkout, run with Bun) |
| ttyd | Raw shell in the browser | in the image |
| Node 22 | For the agents (`npm i -g ...`) | in the image, npm globals in `~/.npm-global` |

herdr, hc, Bun and Ovis are downloaded **on first start** into the home volume. That means `herdr update` / `hc update` work, and updates survive an image rebuild.

## 2. Architecture

```
PC (Herdr app / TUI) ──ssh :2222──┐
                                  ▼
Browser / phone ──https──> reverse proxy ──> forward-auth portal
                                  │
                                  ▼
                 ┌──────── container: herdr ─────────┐
                 │ tini → supervisord                │
                 │   sshd            :22  (→ 2222)   │
                 │   herdr server    (+ hc core)     │
                 │   Ovis            :7317 (token)   │
                 │   ttyd            :7681 (opt.)    │
                 │ agents: claude, codex, ...        │
                 └───────────────────────────────────┘
                   volumes: home, config, projects
```

Ovis binds `0.0.0.0:7317` **inside the container** and always runs with a token (`OVIS_TOKEN`). Without a token anyone who can reach it can type into your terminals. Still: don't publish it to the internet; put it behind your reverse proxy + auth.

## 3. Repo layout

```
herdr-unraid/
├── Dockerfile
├── docker-compose.yml
├── .env.example
├── rootfs/
│   ├── entrypoint.sh                       # user, ssh keys, token, first-run install
│   └── etc/
│       ├── ssh/sshd_config.d/10-herdr.conf # key-only ssh
│       └── supervisor/herdr.conf           # sshd, herdr, webui, ttyd
├── scripts/
│   ├── env.sh            # HOME/PATH for user herdr
│   ├── install-herdr.sh  # idempotent install of herdr, hc, bun, Ovis
│   ├── run-herdr.sh      # herdr server
│   ├── run-webui.sh      # Ovis
│   ├── run-ttyd.sh       # ttyd (+ basic auth)
│   └── healthcheck.sh
├── unraid/
│   ├── herdr.xml             # Unraid Docker template
│   └── build-on-server.sh    # build on Unraid + recreate container
└── .github/workflows/build.yml  # builds + smoke-tests + pushes to GHCR
```

## 4. Settings

| Variable | Default | Meaning |
|---|---|---|
| `PUID` / `PGID` | `99` / `100` | ids of user `herdr` (Unraid nobody:users, clean appdata perms) |
| `TZ` | `Etc/UTC` | timezone |
| `AUTHORIZED_KEYS` | – | SSH public key(s), separate with `;`. Added to `home/.ssh/authorized_keys` |
| `OVIS_TOKEN` | auto | web UI token. Empty = generated once into `config/ovis_token` (never logged) |
| `TTYD_CREDENTIAL` | – | `user:password` basic auth for ttyd. Set it. |
| `ENABLE_WEBUI` | `true` | run Ovis |
| `ENABLE_TTYD` | `true` | run ttyd |
| `ENABLE_SUDO` | `true` | passwordless sudo for `herdr` inside the container |
| `AUTO_UPDATE` | `false` | `herdr update`, `hc update`, `git pull` Ovis on every start |
| `OVIS_REF` | – | Ovis branch/tag for the first clone |

| Port | What |
|---|---|
| `22` (→ 2222) | SSH, key-only, user `herdr`, no root, no passwords |
| `7317` | Ovis web UI |
| `7681` | ttyd |

| Volume | What |
|---|---|
| `/home/herdr` | herdr, hc, Bun, Ovis, agent logins/API keys, npm globals |
| `/config` | SSH host keys (no "host key changed" after rebuild), `ovis_token` |
| `/home/herdr/projects` | your code (one share only) |

## 5. Install on Unraid

**Template (recommended):** copy `unraid/herdr.xml` to
`/boot/config/plugins/dockerMan/templates-user/my-herdr.xml`, then Docker tab → Add Container → pick `herdr`, fill in your SSH public key, ttyd login and the projects path → Apply.

**Compose (Compose Manager plugin):**
```bash
cp .env.example .env   # fill in AUTHORIZED_KEYS, TTYD_CREDENTIAL
docker compose up -d --build
docker logs -f herdr
```

The first start takes a few minutes (downloads + `bun install`). The healthcheck allows 10 min.

**Build on the server (what Tower uses):** the GHCR image is private, so instead of pulling, the image is built on the server itself. `rebuild_container` doesn't pull, so the template works with the local image.

From the PC, in this repo:
```bash
git archive --format=tar.gz -o /tmp/herdr-src.tgz HEAD
scp /tmp/herdr-src.tgz root@<unraid-ip>:/tmp/
ssh root@<unraid-ip> 'rm -rf /mnt/user/appdata/herdr/src && mkdir -p /mnt/user/appdata/herdr/src && tar xzf /tmp/herdr-src.tgz -C /mnt/user/appdata/herdr/src && bash /mnt/user/appdata/herdr/src/unraid/build-on-server.sh'
```
`build-on-server.sh` builds the image, recreates the container from `templates-user/my-herdr.xml` and removes the old image. herdr, hc and Ovis themselves update inside the container (`herdr update`, `hc update`, or `AUTO_UPDATE=true`), so a rebuild is only needed when this repo changes.

## 6. Usage

**Log agents in once**
```bash
docker exec -it -u herdr herdr bash -l
npm i -g @anthropic-ai/claude-code @openai/codex
claude    # log in
```

**From your PC** (`~/.ssh/config`)
```
Host unraid-herdr
  HostName <unraid-ip>
  Port 2222
  User herdr
```
- TUI, one-off: `herdr --remote unraid-herdr`
- TUI, saved machine: `herdr machine add unraid-herdr --label "Unraid"`
- herdr-core / desktop app: `hc machine add unraid-herdr --name unraid`, then `hc run --on unraid --bg claude`

If the herdr version on your PC differs, interactive attach offers to install a matching one into the container's `~/.local/bin`. That's fine; it lives in the home volume.

**Browser:** `http://<unraid-ip>:7317` on the LAN, or `https://herdr.example.com` via your reverse proxy (websockets ON, forward auth in front). Sign in with the token from `appdata/herdr/config/ovis_token`. Phones need HTTPS for the PWA and push alerts.

**SSH tunnel instead of publishing 7317:** `ssh -L 7317:127.0.0.1:7317 unraid-herdr`, then open `http://localhost:7317`.

## 7. Build plan

| # | Step | Status |
|---|---|---|
| 1 | Fix the spec (real install commands, Ovis rename, `herdr server`, token instead of socat) | ✅ |
| 2 | Image: Ubuntu 24.04, sshd, supervisord, tini, ttyd, Node 22 | ✅ |
| 3 | Entrypoint: PUID/PGID user, keys, host keys, token, first-run install | ✅ |
| 4 | CI: shellcheck, build, smoke test (healthy + herdr/hc work + sshd settings), push to GHCR | ✅ |
| 5 | Deploy on Unraid via template, check pull from private GHCR | ⏳ |
| 6 | Acceptance checklist below on the real server | ⏳ |
| 7 | Reverse proxy host + forward auth for the web UI | ⏳ |
| 8 | Own GUI, only if Ovis falls short (§9) | later |

## 8. Acceptance checklist

- [ ] Container starts healthy from empty appdata
- [ ] `ssh unraid-herdr` works with the key; password and root login refused
- [ ] `herdr --version` / `hc ls` work inside, and still work after an image update
- [ ] Herdr client on the PC connects and shows the container's agents
- [ ] Ovis on :7317 asks for the token, shows the live terminal, can send input to an agent
- [ ] Web UI not reachable from outside without the auth portal
- [ ] ttyd on :7681 asks for the login and gives a shell
- [ ] Agents keep running after closing all clients and after `hc update`
- [ ] Files in `projects` are owned by 99:100 on the array

## 9. Later: own GUI (only if needed)

If Ovis doesn't fit, build a small one:
- Backend: herdr-core API (`hc schema` → OpenRPC, with streams/events) or herdr's socket API
- Frontend: agent list with status (working / done / needs you), xterm.js terminal per agent, "send message", start-agent button
- Same container, same port, same auth

## 10. Security notes

- Agents have sudo inside the container → mount only the projects share, never all of `/mnt/user`. Set `ENABLE_SUDO=false` if you don't need it.
- Don't expose 2222 / 7317 / 7681 to the internet. Web via reverse proxy + auth only; SSH via LAN, Tailscale or WireGuard.
- Agent logins / API keys and the web token live in appdata → back it up, keep it private.

## Changes compared to the first spec

- `herdr-web-ui` is now **Ovis** (`devswha/ovis`). It runs from a git checkout with `bun run start`; settings are `HOST`, `PORT`, `OVIS_TOKEN`, `HERDR_SOCKET`, `OVIS_STATE_DIR`. `HERDR_WEB_NO_OPEN` is now `OVIS_NO_OPEN`. It doesn't need Node.
- No socat proxy: Ovis listens on `0.0.0.0` inside the container and is protected by its token.
- herdr install = `curl -fsSL https://herdr.dev/install.sh | sh` → `~/.local/bin/herdr`. Headless server = `herdr server`.
- herdr-core installs to `~/.local/bin/herdr-core` with an `hc` symlink; its daemon starts on first use.
- ttyd gets basic auth (`TTYD_CREDENTIAL`); tini is PID 1 so daemonized children get reaped.
- Default projects path is inside appdata; point it at your projects share in the template.

## Sources
- https://herdr.dev/ · https://herdr.dev/core/ · https://herdr.dev/docs/connecting-machines/ · https://herdr.dev/docs/persistence-remote/
- https://github.com/herdrdev/herdr · https://github.com/herdrdev/herdr-core
- https://github.com/devswha/ovis (INSTALL.md, docs/guide.md)
