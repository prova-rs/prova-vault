---@meta
-- LuaCATS stub for prova-vault — editor completion for consumers. Not executed.

---@class vault.Status
---@field initialized boolean
---@field sealed boolean
---@field version string

---@class vault.Client
local Client = {}

--- Write scalar key=values at `path` (KV v2, mount `secret/`).
---@param path string
---@param data table<string, string|number|boolean>
---@return vault.Client
function Client:kv_put(path, data) end

--- Read the secret at `path` as a flat table of strings, or nil if it does not exist.
---@param path string
---@return table<string, string>|nil
function Client:kv_get(path) end

--- List the entries directly under `path` (or the mount root when omitted); {} when none.
---@param path? string
---@return string[]
function Client:kv_list(path) end

--- Delete the latest version of the secret at `path`. Idempotent.
---@param path string
---@return vault.Client
function Client:kv_delete(path) end

--- `vault status` as parsed JSON. A dev-mode server is born initialized and unsealed.
---@return vault.Status
function Client:status() end

--- The generic escape hatch: run any vault CLI argv inside the container, return raw stdout.
---@param args string[]
---@param stdin? string
---@return string
function Client:cli(args, stdin) end

function Client:close() end

---@class vault.Resource
---@field client vault.Client
---@field url string          # http endpoint for the app under test
---@field token string        # the root token (default "prova-root"; opts.token overrides)
---@field container prova.Container

---@class vault.Opts
---@field token? string       # dev root token (default "prova-root")
---@field tag? string         # image tag override
---@field timeout? string     # readiness budget (default "60s")

local vault = {}

--- Provision an ephemeral dev-mode Vault container: in-memory, unsealed, KV v2 at `secret/`.
---@param ctx prova.Ctx
---@param opts? vault.Opts
---@return vault.Resource
function vault.container(ctx, opts) end

return vault
