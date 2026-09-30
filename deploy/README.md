# Deploying unotes

The image holds the binary, the Mojo runtime libraries beside it, and no
Python. Everything here runs from the PROJECT ROOT, which is the build
context.

## The image

```sh
uv sync                                         # once; commit uv.lock
uv run m0 image                                 # docker build -f deploy/Dockerfile -t unotes .
docker run --rm -p 8080:8080 -e UNOTES_KEY -e UNOTES_PASSWORD -e UNOTES_SECURE=0 unotes
```

The login's variables go into the container too: `UNOTES_KEY` and
`UNOTES_PASSWORD` from the shell that exported them, and `UNOTES_SECURE=0`
because this is plain http. The image states none of the three, so a
platform that states nothing is refused (exit 78) rather than served with
the session cookie in clear.

The builder stage runs `uv run m0 build --release`: the platform's baseline
CPU, never the builder's own. `/app/about.json` in the image is what the
image measured about itself (its size, and that no interpreter is in it);
`m0 image` prints it last. `--tag T` names the image, `--target-cpu CPU`
compiles for something newer than the baseline, and whatever follows a bare
`--` goes to `docker build` as it is (`-- --platform linux/amd64`). `m0
image` needs docker and nothing else: the compiler runs in the builder.

The runtime stage installs `libsqlite3-0`, which `m0_sqlite` opens at run
time (`about.json`'s `libs` says so), and copies `data/` in: the sample
always, and the real `notes.sqlite` and `theme-map.md` when the working
directory holds them (the README has the copy). The app reads its database
and never writes it, so unlike `m0 0.3.0`'s template the image sets no
`M0_DB` and wants no volume. The build fails if the old export
(`data/notes.jsonl`, `data/themes.jsonl`) is in the context.

An image built with the real files holds the whole database — every column
and the full-text index, not only what the app shows — so it belongs in
Fly's private registry and nowhere else.

## Fly.io

```sh
fly apps create unotes
fly deploy -c deploy/fly.toml --remote-only
fly scale count 1 -a unotes
```

- `--remote-only`: an image built on an Apple Silicon laptop is built under
  emulation for Fly's x86-64 machines, and the Mojo compiler does not
  survive that.
- `scale count 1`: the first deploy creates two machines. State held in
  the process is one machine's; see the comment in `fly.toml`.
- The login's secrets are set once, before the first deploy, and never
  written in `fly.toml`: `fly secrets set -a unotes
  UNOTES_KEY="$(openssl rand -hex 32)" UNOTES_PASSWORD='choose one'`.
  `fly.toml` already states `UNOTES_SECURE = "1"`, since the proxy serves
  HTTPS; on another platform, state it there, or the server refuses to
  start (exit 78, naming it).
- One loop. On one shared vCPU a second worker or thread cannot run beside
  the first, so `M0_WORKERS`/`M0_THREADS` stay unset. On more than one
  vCPU, set `M0_THREADS` to the count.
