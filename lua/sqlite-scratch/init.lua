---@module "sqlite-scratch"
---Public commands for the SQLite scratchpad.

local session = require("sqlite-scratch.session")

local M = {}

---@param db_path string
---@return boolean
local function confirm_replacement(db_path)
    local active = session.current()
    if not active or not vim.api.nvim_buf_is_valid(active.query_buf) then return true end

    local lines = vim.api.nvim_buf_get_lines(active.query_buf, 0, -1, false)
    if not table.concat(lines, "\n"):find("%S") then return true end

    local choice = vim.fn.confirm(
        ("Discard the active query draft and open %s?"):format(db_path),
        "&Cancel\n&Discard and open",
        1,
        "Warning"
    )
    return choice == 2
end

local function open(path)
    if vim.fn.executable("sqlite3") ~= 1 then
        vim.notify("SQLiteOpen requires the sqlite3 executable", vim.log.levels.ERROR)
        return
    end

    local expanded = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
    local db_path = vim.fs.normalize(expanded)
    if not confirm_replacement(db_path) then return end

    session.open(db_path)
end

function M.setup()
    vim.api.nvim_create_user_command("SQLiteOpen", function(command) open(command.args) end, {
        nargs = 1,
        complete = "file",
        desc = "Open a SQLite scratchpad",
        force = true,
    })
    vim.api.nvim_create_user_command("SQLiteClose", session.close, {
        desc = "Close the SQLite scratchpad",
        force = true,
    })
    vim.api.nvim_create_user_command("SQLiteExport", function(command)
        local expanded = vim.fn.fnamemodify(vim.fn.expand(command.args), ":p")
        session.export(vim.fs.normalize(expanded), command.bang)
    end, {
        nargs = 1,
        bang = true,
        complete = "file",
        desc = "Rerun the selected SQLite result and export it as CSV",
        force = true,
    })
end

return M
