# prova-vault

A HashiCorp Vault plugin for [Prova](https://github.com/prova-rs/prova): an ephemeral **dev-mode
Vault** (in-memory, unsealed, root token known) provisioned per suite, driven over the `vault`
CLI already in the image — zero native code. Seed secrets, point the app under test at the URL +
token, assert what it wrote.

```lua
local vault = require("vault")

local v = prova.fixture("vault", Scope.File, function(ctx)
  return vault.container(ctx)                 -- { client, url, token, container }
end)

prova.test("the app reads its database credentials from vault", { requires = { "docker" } },
  function(t)
  local secrets = t:use(v)
  secrets.client:kv_put("app/db", { username = "svc", password = "hunter2" })
  -- boot the app with VAULT_ADDR = secrets.url, VAULT_TOKEN = secrets.token …
  t:expect(secrets.client:kv_get("app/db").password):equals("hunter2")
end)
```

## Install

```bash
prova plugins add vault        # pins [plugins] vault = { git = …, tag = "…" }
```

or pin it manually in `prova.toml`:

```toml
[plugins]
vault = { git = "https://github.com/prova-rs/prova-vault", tag = "v1.0" }
```

## API

`vault.container(ctx, opts?)` → `{ client, url, token, container }` — `opts.token` sets the dev
root token (default `"prova-root"`); `opts.tag`/`opts.timeout` override the image tag and
readiness budget.

The client wraps KV v2 at the dev-mode `secret/` mount:

| verb | behavior |
|---|---|
| `kv_put(path, data)` | write scalar `k=v`s; keys sorted for deterministic argv |
| `kv_get(path)` | flat table of strings, or `nil` on a miss |
| `kv_list(path?)` | entries directly under the prefix; `{}` when none |
| `kv_delete(path)` | latest version; idempotent |
| `status()` | parsed `vault status` (initialized/sealed/version) |
| `cli(args, stdin?)` | the escape hatch: any vault CLI argv, raw stdout |

Values are scalars (string/number/boolean) — the CLI `k=v` form. Nested secrets: store a JSON
string and decode on read.

## Proofs

The plugin proves itself: `proofs/vault_test.lua` runs every verb against a real container
(`requires = { "docker" }` — skips cleanly without a daemon).

```bash
prova
```
