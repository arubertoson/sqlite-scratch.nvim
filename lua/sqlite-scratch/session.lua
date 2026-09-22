---@module "sqlite-scratch.session"
---Owns the active SQLite scratchpad session.

local adapter = require("sqlite-scratch.adapters.sqlite")
local history = require("sqlite-scratch.history")
local render = require("sqlite-scratch.render")
local scope = require("sqlite-scratch.scope")
local ui = require("sqlite-scratch.ui")

local M = {}

---@class SqliteScratch.InactiveState
---@field kind "inactive"

---@class SqliteScratch.ActiveState
---@field kind "active"
---@field db_path string
---@field query_buf integer
---@field result_buf integer
---@field query_win integer
---@field result_win integer
---@field history SqliteScratch.History
---@field adapter SqliteScratch.Adapter
---@field ui SqliteScratch.UI
---@field lsp_client_id integer
---@field process vim.SystemObj|nil

---@alias SqliteScratch.State SqliteScratch.InactiveState|SqliteScratch.ActiveState

---@type SqliteScratch.State
local state = { kind = "inactive" }

---@param query_buf integer
local function configure_query_buffer(query_buf)
    local options = { buffer = query_buf, silent = true }

    vim.keymap.set(
        "n",
        "<leader>rr",
        function() M.execute(scope.buffer(query_buf)) end,
        vim.tbl_extend("force", options, { desc = "Execute SQLite buffer" })
    )
    vim.keymap.set(
        "x",
        "<leader>rr",
        function() M.execute(scope.region(vim.fn.getpos("v"), vim.fn.getpos("."), vim.fn.mode())) end,
        vim.tbl_extend("force", options, { desc = "Execute SQLite selection" })
    )
    vim.keymap.set("n", "<leader>rl", function()
        local line = vim.api.nvim_win_get_cursor(0)[1]
        M.execute(scope.line(query_buf, line))
    end, vim.tbl_extend("force", options, { desc = "Execute SQLite line" }))
    vim.keymap.set(
        "n",
        "[r",
        function() M.navigate(-1) end,
        vim.tbl_extend("force", options, { desc = "Previous SQLite result" })
    )
    vim.keymap.set(
        "n",
        "]r",
        function() M.navigate(1) end,
        vim.tbl_extend("force", options, { desc = "Next SQLite result" })
    )
    vim.keymap.set(
        "n",
        "<leader>rd",
        M.delete_current,
        vim.tbl_extend("force", options, { desc = "Delete current SQLite result" })
    )
    vim.keymap.set(
        "n",
        "<leader>rs",
        M.toggle_sql_preview,
        vim.tbl_extend("force", options, { desc = "Toggle SQLite execution SQL" })
    )
end

---@param active SqliteScratch.ActiveState
local function render_current(active)
    local entry = history.current(active.history)
    if not entry then
        ui.update_result(active.ui, render.empty())
        ui.update_sql_preview(active.ui, nil)
        return
    end
    ui.update_result(
        active.ui,
        render.result(entry, active.history.index, #active.history.entries)
    )
    ui.update_sql_preview(active.ui, entry.sql)
end

---@param db_path string
---@return integer query_buf
function M.open(db_path)
    if state.kind == "active" then M.close() end

    local db_adapter = adapter.new(db_path)
    local scratch_ui
    scratch_ui = ui.open(db_path, function()
        if state.kind == "active" and state.ui == scratch_ui then M.close() end
    end, function(query_buf)
        if state.kind ~= "active" or state.ui ~= scratch_ui then return end
        state.query_buf = query_buf
        vim.lsp.buf_attach_client(query_buf, state.lsp_client_id)
        configure_query_buffer(query_buf)
    end)
    local lsp_client_id = vim.lsp.start(db_adapter:lsp_config(), {
        bufnr = scratch_ui.query_buf,
        reuse_client = function() return false end,
    })
    if not lsp_client_id then
        ui.close(scratch_ui)
        error("Failed to start sqls")
    end

    state = {
        kind = "active",
        db_path = db_path,
        query_buf = scratch_ui.query_buf,
        result_buf = scratch_ui.result_buf,
        query_win = scratch_ui.query_win,
        result_win = scratch_ui.result_win,
        history = history.new(50),
        adapter = db_adapter,
        ui = scratch_ui,
        lsp_client_id = lsp_client_id,
        process = nil,
    }
    configure_query_buffer(state.query_buf)
    render_current(state)
    return state.query_buf
end

function M.close()
    if state.kind == "inactive" then return end

    local active = state
    state = { kind = "inactive" }
    if active.process then pcall(active.process.kill, active.process, 15) end
    local client = vim.lsp.get_client_by_id(active.lsp_client_id)
    if client then client:stop(true) end
    ui.close(active.ui)
end

---@param sql string
function M.execute(sql)
    if state.kind == "inactive" then return end
    local active = state
    if active.process then
        vim.notify("A SQLite operation is already running", vim.log.levels.WARN)
        return
    end
    if not sql:find("%S") then
        vim.notify("No SQL to execute", vim.log.levels.WARN)
        return
    end
    if not vim.api.nvim_buf_is_valid(active.query_buf) then
        M.close()
        return
    end

    ui.update_result(active.ui, render.executing())
    active.process = active.adapter:execute(sql, function(result)
        if state ~= active then return end
        active.process = nil
        history.append(active.history, {
            sql = sql,
            columns = result.columns,
            rows = result.rows,
            error = result.error,
            truncated = result.truncated,
            values_truncated = result.values_truncated,
            execution_ms = result.execution_ms,
            timestamp = result.timestamp,
        })
        render_current(active)
    end)
end

---@param path string
---@param overwrite boolean
function M.export(path, overwrite)
    if state.kind == "inactive" then return end
    local active = state
    if active.process then
        vim.notify("A SQLite operation is already running", vim.log.levels.WARN)
        return
    end

    local entry = history.current(active.history)
    if not entry then
        vim.notify("No SQLite result to export", vim.log.levels.WARN)
        return
    end

    active.process = active.adapter:export(entry.sql, path, overwrite, function(result)
        if state ~= active then return end
        active.process = nil
        if result.error then
            vim.notify("SQLite export failed: " .. result.error, vim.log.levels.ERROR)
            return
        end
        vim.notify("Exported SQLite results to " .. path)
    end)
end

---@param delta integer
function M.navigate(delta)
    if state.kind == "inactive" then return end
    if history.navigate(state.history, delta) then render_current(state) end
end

function M.delete_current()
    if state.kind == "inactive" then return end
    if history.delete_current(state.history) then render_current(state) end
end

function M.toggle_sql_preview()
    if state.kind == "inactive" then return end
    local entry = history.current(state.history)
    if not entry then
        vim.notify("No SQLite execution to preview", vim.log.levels.WARN)
        return
    end
    ui.toggle_sql_preview(state.ui, entry.sql)
end

---@return boolean
function M.is_active() return state.kind == "active" end

---@return SqliteScratch.ActiveState|nil
function M.current()
    if state.kind == "inactive" then return nil end
    return state
end

return M
