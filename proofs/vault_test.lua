-- The prova-vault proof suite: every exported client verb (kv_put/kv_get/kv_list/kv_delete/
-- status/cli), miss and idempotence semantics, value fidelity through the k=v CLI form, and the
-- options surface (custom root token) — all against a real dev-mode Vault container.
-- Requires docker; skips otherwise.

local vault = prova.fixture("vault", Scope.File, function(ctx)
  return require("vault").container(ctx)
end)

-- A second container proving the options surface: a custom root token, end to end.
local custom = prova.fixture("vault-custom", Scope.File, function(ctx)
  return require("vault").container(ctx, { token = "acceptance-root" })
end)

prova.group("vault", { requires = { "docker" } }, function(g)
  g:test("kv put/get/list/delete round-trips a secret", function(t)
    local c = t:use(vault).client
    c:kv_put("app/db", { username = "svc", password = "hunter2" })

    local secret = c:kv_get("app/db")
    t:expect(secret.username):equals("svc")
    t:expect(secret.password):equals("hunter2")

    t:expect(c:kv_list("app")):equals({ "db" })

    c:kv_delete("app/db")
    t:expect(c:kv_get("app/db")):is_falsy()
  end)

  g:test("a miss reads as nil, an empty prefix lists as {}, delete is idempotent", function(t)
    local c = t:use(vault).client
    t:expect(c:kv_get("nowhere/nothing")):is_falsy()
    t:expect(c:kv_list("nowhere")):equals({})
    c:kv_delete("nowhere/nothing")   -- no raise: deleting a miss is a no-op
  end)

  g:test("values survive spaces, quotes, and unicode through the k=v form", function(t)
    local c = t:use(vault).client
    local tricky = 'pass "word" with spaces — unicode: ✓'
    c:kv_put("app/tricky", { secret = tricky })
    t:expect(c:kv_get("app/tricky").secret):equals(tricky)
    c:kv_delete("app/tricky")
  end)

  g:test("an overwrite wins: the latest version is what reads back", function(t)
    local c = t:use(vault).client
    c:kv_put("app/rotating", { key = "v1" })
    c:kv_put("app/rotating", { key = "v2" })
    t:expect(c:kv_get("app/rotating").key):equals("v2")
    c:kv_delete("app/rotating")
  end)

  g:test("status reports an initialized, unsealed dev server", function(t)
    local s = t:use(vault).client:status()
    t:expect(s.initialized):is_true()
    t:expect(s.sealed):is_falsy()
  end)

  g:test("cli is the escape hatch; url and token are exposed for the app under test", function(t)
    local v = t:use(vault)
    t:expect(v.url):matches("^http://")
    t:expect(v.token):equals("prova-root")
    -- the raw CLI surface, for anything the client doesn't wrap
    t:expect(v.client:cli({ "token", "lookup", "-format=json" })):contains('"root"')
  end)
end)

prova.group("vault with custom options", { requires = { "docker" } }, function(g)
  g:test("a custom root token is honored end-to-end", function(t)
    local v = t:use(custom)
    t:expect(v.token):equals("acceptance-root")
    -- The client authenticates WITH that token, so a round-trip proves it was plumbed through.
    v.client:kv_put("smoke/one", { ok = "yes" })
    t:expect(v.client:kv_get("smoke/one").ok):equals("yes")
  end)
end)
