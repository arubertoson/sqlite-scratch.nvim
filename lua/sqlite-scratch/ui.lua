---@module "sqlite-scratch.ui"
---Scratchpad tab, windows, and buffer lifecycle.

local M = {}

---@class SqliteScratch.SqlPreview
---@field buf integer
---@field win integer

---@class SqliteScratch.UI
---@field tabpage integer
---@field query_buf integer
---@field owned_query_buf integer|nil
---@field result_buf integer
---@field query_win integer
---@field result_win integer
---@field result_height integer
---@field augroup integer
---@field previous_tabline string
---@field sql_preview SqliteScratch.SqlPreview|nil

---@param result_win integer
---@param height integer
local function enforce_result_layout(result_win, height)
    if not vim.api.nvim_win_is_valid(result_win) then return end

    vim.api.nvim_win_call(result_win, function() vim.cmd("wincmd J") end)
    vim.wo[result_win].winfixheight = true
    vim.api.nvim_win_set_height(result_win, height)
end

local function tab_label(tabpage)
    local label = vim.t[tabpage].sqlite_scratch_tab_label
    if label then return label end

    local win = vim.api.nvim_tabpage_get_win(tabpage)
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    return name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":t")
end

---@return string
function M.tabline()
    local tabs = vim.api.nvim_list_tabpages()
    local current = vim.api.nvim_get_current_tabpage()
    local parts = {}

    for index, tabpage in ipairs(tabs) do
        local highlight = tabpage == current and "%#TabLineSel#" or "%#TabLine#"
        local label = tab_label(tabpage):gsub("%%", "%%%%"):gsub("[\r\n]", " ")
        parts[#parts + 1] = ("%s%%%dT %s "):format(highlight, index, label)
    end

    parts[#parts + 1] = "%#TabLineFill#%T"
    if #tabs > 1 then parts[#parts + 1] = "%=%#TabLine#%999X X " end
    return table.concat(parts)
end

---@param db_path string
---@param on_lost fun()
---@param on_query_changed fun(query_buf: integer)
---@return SqliteScratch.UI
function M.open(db_path, on_lost, on_query_changed)
    local previous_tabline = vim.o.tabline
    vim.cmd("tabnew")
    local tabpage = vim.api.nvim_get_current_tabpage()
    vim.t[tabpage].sqlite_scratch_tab_label = "SQLite: " .. vim.fs.basename(db_path)
    vim.o.tabline = "%!v:lua.require'sqlite-scratch.ui'.tabline()"
    local query_buf = vim.api.nvim_get_current_buf()
    local query_win = vim.api.nvim_get_current_win()

    vim.b[query_buf].sqlite_scratch_query = true
    vim.bo[query_buf].filetype = "sql"
    vim.bo[query_buf].modifiable = true

    local result_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[result_buf].buftype = "nofile"
    vim.bo[result_buf].bufhidden = "hide"
    vim.bo[result_buf].swapfile = false
    vim.bo[result_buf].modifiable = false

    vim.cmd("botright split")
    local result_win = vim.api.nvim_get_current_win()
    local result_height = math.max(3, math.floor(vim.o.lines * 0.4))
    vim.api.nvim_win_set_buf(result_win, result_buf)
    vim.wo[result_win].wrap = false
    vim.wo[result_win].cursorcolumn = false
    vim.wo[result_win].colorcolumn = ""
    enforce_result_layout(result_win, result_height)
    vim.api.nvim_set_current_win(query_win)

    local augroup = vim.api.nvim_create_augroup("SQLiteScratch", { clear = true })
    local loss_check_scheduled = false
    ---@type SqliteScratch.UI
    local opened_ui

    local function reconcile_scratchpad()
        if
            not vim.api.nvim_tabpage_is_valid(tabpage)
            or not vim.api.nvim_win_is_valid(query_win)
            or not vim.api.nvim_win_is_valid(result_win)
            or not vim.api.nvim_buf_is_valid(result_buf)
            or vim.api.nvim_win_get_tabpage(query_win) ~= tabpage
            or vim.api.nvim_win_get_tabpage(result_win) ~= tabpage
            or vim.api.nvim_win_get_buf(result_win) ~= result_buf
        then
            return false
        end

        local current_query_buf = vim.api.nvim_win_get_buf(query_win)
        if current_query_buf ~= query_buf then
            query_buf = current_query_buf
            opened_ui.query_buf = query_buf
            vim.b[query_buf].sqlite_scratch_query = true
            vim.bo[query_buf].filetype = "sql"
            on_query_changed(query_buf)
        elseif
            opened_ui.owned_query_buf == query_buf
            and vim.api.nvim_buf_get_name(query_buf) ~= ""
        then
            opened_ui.owned_query_buf = nil
            vim.b[query_buf].sqlite_scratch_query = true
            vim.bo[query_buf].filetype = "sql"
            on_query_changed(query_buf)
        end
        return true
    end

    local function check_for_loss()
        if loss_check_scheduled then return end
        loss_check_scheduled = true
        vim.schedule(function()
            loss_check_scheduled = false
            if not reconcile_scratchpad() then on_lost() end
        end)
    end

    vim.api.nvim_create_autocmd("WinNew", {
        group = augroup,
        callback = function()
            vim.schedule(function()
                if
                    vim.api.nvim_tabpage_is_valid(tabpage)
                    and vim.api.nvim_get_current_tabpage() == tabpage
                then
                    enforce_result_layout(result_win, result_height)
                end
            end)
        end,
    })
    vim.api.nvim_create_autocmd({ "TabClosed", "WinClosed" }, {
        group = augroup,
        callback = check_for_loss,
    })
    vim.api.nvim_create_autocmd({ "BufFilePost", "BufWinEnter", "BufWinLeave" }, {
        group = augroup,
        callback = check_for_loss,
    })

    opened_ui = {
        tabpage = tabpage,
        query_buf = query_buf,
        owned_query_buf = query_buf,
        result_buf = result_buf,
        query_win = query_win,
        result_win = result_win,
        result_height = result_height,
        augroup = augroup,
        previous_tabline = previous_tabline,
        sql_preview = nil,
    }
    return opened_ui
end

---@param lines string[]
---@return string[]
local function valid_buffer_lines(lines)
    local sanitized = {}
    for index, line in ipairs(lines) do
        sanitized[index] = tostring(line):gsub("[\r\n]", " ")
    end
    return sanitized
end

---@param ui SqliteScratch.UI
---@param lines string[]
function M.update_result(ui, lines)
    if not vim.api.nvim_buf_is_valid(ui.result_buf) then return end

    vim.bo[ui.result_buf].modifiable = true
    vim.api.nvim_buf_set_lines(ui.result_buf, 0, -1, false, valid_buffer_lines(lines))
    vim.bo[ui.result_buf].modifiable = false
end

---@param ui SqliteScratch.UI
local function close_sql_preview(ui)
    local preview = ui.sql_preview
    if not preview then return end

    ui.sql_preview = nil
    if vim.api.nvim_win_is_valid(preview.win) then vim.api.nvim_win_close(preview.win, true) end
    if vim.api.nvim_buf_is_valid(preview.buf) then
        vim.api.nvim_buf_delete(preview.buf, { force = true })
    end
end

---@param ui SqliteScratch.UI
---@param line_count integer
---@return vim.api.keyset.win_config
local function sql_preview_config(ui, line_count)
    local result_width = vim.api.nvim_win_get_width(ui.result_win)
    local result_height = vim.api.nvim_win_get_height(ui.result_win)
    return {
        relative = "win",
        win = ui.result_win,
        anchor = "NE",
        row = 0,
        col = result_width,
        width = math.max(1, math.min(60, result_width - 2)),
        height = math.max(1, math.min(line_count, result_height - 2)),
        style = "minimal",
        border = "rounded",
        title = " SQL ",
        title_pos = "left",
        focusable = false,
        zindex = 60,
    }
end

---@param ui SqliteScratch.UI
---@param sql string|nil
function M.update_sql_preview(ui, sql)
    local preview = ui.sql_preview
    if not preview then return end
    if not sql then
        close_sql_preview(ui)
        return
    end

    local lines = vim.split(sql, "\n", { plain = true })
    vim.bo[preview.buf].modifiable = true
    vim.api.nvim_buf_set_lines(preview.buf, 0, -1, false, valid_buffer_lines(lines))
    vim.bo[preview.buf].modifiable = false
    vim.api.nvim_win_set_config(preview.win, sql_preview_config(ui, #lines))
end

---@param ui SqliteScratch.UI
---@param sql string
function M.toggle_sql_preview(ui, sql)
    if ui.sql_preview then
        close_sql_preview(ui)
        return
    end

    local lines = vim.split(sql, "\n", { plain = true })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "sql"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, valid_buffer_lines(lines))
    vim.bo[buf].modifiable = false

    local win = vim.api.nvim_open_win(buf, false, sql_preview_config(ui, #lines))
    vim.wo[win].wrap = true
    vim.wo[win].cursorline = false
    ui.sql_preview = { buf = buf, win = win }
end

---@param ui SqliteScratch.UI
function M.close(ui)
    close_sql_preview(ui)
    vim.api.nvim_del_augroup_by_id(ui.augroup)
    vim.o.tabline = ui.previous_tabline
    if vim.api.nvim_tabpage_is_valid(ui.tabpage) then
        local tab_number = vim.api.nvim_tabpage_get_number(ui.tabpage)
        vim.cmd(tab_number .. "tabclose!")
    end
    if vim.api.nvim_buf_is_valid(ui.result_buf) then
        vim.api.nvim_buf_delete(ui.result_buf, { force = true })
    end
    if ui.owned_query_buf and vim.api.nvim_buf_is_valid(ui.owned_query_buf) then
        vim.api.nvim_buf_delete(ui.owned_query_buf, { force = true })
    end
end

return M
