-- prova-vault — a HashiCorp Vault plugin via docker-exec over the `vault` CLI (zero native code).
-- Provisions an ephemeral dev-mode Vault (in-memory, unsealed, root token known) and drives it
-- with the CLI already in the image. The KV v2 engine is mounted at `secret/` by dev mode, which
-- is exactly the surface an app under test needs: seed secrets, point the app at the URL + token,
-- assert what it wrote.
--
--   local vault = require("vault")
--   local v = vault.container(ctx)              -- { client, url, token, container }
--   v.client:kv_put("app/db", { username = "svc", password = "hunter2" })
--   v.client:kv_get("app/db").password          -- "hunter2"
--   v.client:kv_list("app")                     -- { "db" }
--   v.client:kv_delete("app/db")
--
-- Values are scalars (string/number/boolean) — the `vault kv put k=v` CLI form. An app needing
-- nested JSON secrets writes them as a JSON string value and decodes on read.

local DEFAULT_TOKEN = "prova-root"

-- Run the vault CLI inside the container. The CLI reads its target and credentials from env, and
-- `container:run` has no env option — so the in-container `env` binary prefixes the argv (argv
-- form: no shell, no quoting). Raises on non-zero exit (checked-exec).
local function cli(container, token, args, stdin)
  local argv = {
    "env", "VAULT_ADDR=http://127.0.0.1:8200", "VAULT_TOKEN=" .. token, "vault",
  }
  for _, a in ipairs(args) do argv[#argv + 1] = a end
  return container:run(argv, stdin ~= nil and { stdin = stdin } or nil)
end

local function make_client(container, token)
  local client = {}

  -- The generic escape hatch: run any vault CLI argv, return raw stdout.
  function client:cli(args, stdin) return cli(container, token, args, stdin) end

  -- `vault status` as parsed JSON — initialized/sealed/version. Dev mode is born unsealed.
  function client:status()
    return json.decode(cli(container, token, { "status", "-format=json" }))
  end

  -- Write scalar key=values at `path` (KV v2, mount `secret/`). Keys are sorted so the argv —
  -- and therefore any recorded interaction — is deterministic.
  function client:kv_put(path, data)
    local args = { "kv", "put", "-mount=secret", path }
    local keys = {}
    for k in pairs(data) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      args[#args + 1] = k .. "=" .. tostring(data[k])
    end
    cli(container, token, args)
    return self
  end

  -- Read the secret at `path` as a flat table, or nil if it does not exist. CLI values are
  -- strings; numbers/booleans written by kv_put read back as their string spellings.
  function client:kv_get(path)
    local ok, out = pcall(cli, container, token, { "kv", "get", "-format=json", "-mount=secret", path })
    if not ok then return nil end
    return json.decode(out).data.data
  end

  -- List the entries directly under `path` (or the mount root when omitted); {} when none.
  function client:kv_list(path)
    local args = { "kv", "list", "-format=json", "-mount=secret" }
    if path then args[#args + 1] = path end
    local ok, out = pcall(cli, container, token, args)
    if not ok then return {} end
    return json.decode(out)
  end

  -- Delete the latest version of the secret at `path`. Idempotent — deleting a miss is a no-op.
  function client:kv_delete(path)
    pcall(cli, container, token, { "kv", "delete", "-mount=secret", path })
    return self
  end

  function client:close() end
  return client
end

local vault = prova.containerized{
  name = "vault", image = "hashicorp/vault", port = 8200, timeout = "60s",
  -- The image's entrypoint runs `vault server -dev` by default: in-memory, unsealed, KV v2 at
  -- secret/, root token from env. The listen address must leave localhost for the port mapping.
  env = function(opts)
    return {
      VAULT_DEV_ROOT_TOKEN_ID = opts.token or DEFAULT_TOKEN,
      VAULT_DEV_LISTEN_ADDRESS = "0.0.0.0:8200",
    }
  end,
  url = function(hp) return "http://127.0.0.1:" .. hp end,
  -- The token is a resource field beyond the trio — the app under test needs it to reach Vault.
  extra = function(_url, opts)
    return { token = opts.token or DEFAULT_TOKEN }
  end,
  -- `vault status` is the readiness gate: the CLI exits non-zero until the server answers, so
  -- container:run raises and prova.retry loops until it holds — and dev mode must be unsealed.
  client = function(_url, opts, container)
    local token = opts.token or DEFAULT_TOKEN
    local client = make_client(container, token)
    if client:status().sealed then error("vault dev server came up sealed") end
    return client
  end,
}

return vault
