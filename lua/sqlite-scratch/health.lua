---@module "sqlite-scratch.health"
---Environment diagnostics for the SQLite scratchpad.

local M = {}

---@param value string
---@return string
local function trim(value) return value:match("^%s*(.-)%s*$") or "" end

---@param command string[]
---@return boolean ok
---@return string output
local function run(command)
    local completed = vim.system(command, { text = true }):wait(5000)
    local output = trim(completed.stdout or "")
    if output == "" then output = trim(completed.stderr or "") end
    return completed.code == 0, output
end

---@param name string
---@return string|nil path
local function executable(name)
    local path = vim.fn.exepath(name)
    if path == "" then return nil end
    return path
end

function M.check()
    vim.health.start("SQLite scratchpad dependencies")

    local sqlite_path = executable("sqlite3")
    if not sqlite_path then
        vim.health.error("`sqlite3` was not found in $PATH", {
            "Install the SQLite CLI and ensure `sqlite3` is executable",
        })
    else
        local ok, version = run({ sqlite_path, "--version" })
        if ok then
            vim.health.ok(("sqlite3: %s (%s)"):format(version, sqlite_path))
        else
            vim.health.error("`sqlite3 --version` failed", { version })
        end
    end

    local sqls_path = executable("sqls")
    if not sqls_path then
        vim.health.error("`sqls` was not found in $PATH", {
            "Install sqls and ensure `sqls` is executable",
        })
        return
    end

    local ok, version = run({ sqls_path, "--version" })
    if ok then
        vim.health.ok(("sqls: %s (%s)"):format(version, sqls_path))
    else
        vim.health.error("`sqls --version` failed", { version })
    end
end

return M
