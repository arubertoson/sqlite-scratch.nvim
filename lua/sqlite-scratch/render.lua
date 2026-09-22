---@module "sqlite-scratch.render"
---Renders structured query results as plain text tables.

local M = {}
local MAX_CELL_WIDTH = 40

---@param value any
---@return string
local function display_value(value)
    if value == vim.NIL then return "NULL" end
    return tostring(value):gsub("[\r\n]", " ")
end

---@param value string
---@return string
local function truncate(value)
    if vim.fn.strchars(value) <= MAX_CELL_WIDTH then return value end
    return vim.fn.strcharpart(value, 0, MAX_CELL_WIDTH - 1) .. "…"
end

---@param value string
---@param width integer
---@return string
local function pad(value, width)
    return value .. string.rep(" ", width - vim.fn.strdisplaywidth(value))
end

---@param execution_ms number
---@return string
local function duration(execution_ms) return ("%.1fms"):format(execution_ms):gsub("%.0ms$", "ms") end

---@param entry SqliteScratch.Result
---@param index integer
---@param count integer
---@return string[]
function M.result(entry, index, count)
    local position = ("[%d/%d]"):format(index, count)
    if entry.error then
        return {
            position .. " SQLite error · " .. duration(entry.execution_ms),
            "",
            entry.error,
        }
    end

    if #entry.columns == 0 then
        return { position .. " Completed · no result set · " .. duration(entry.execution_ms) }
    end

    local row_count = tostring(#entry.rows) .. (entry.truncated and "+" or "")
    local summary = ("%s %s %s"):format(
        position,
        row_count,
        #entry.rows == 1 and not entry.truncated and "row" or "rows"
    )
    if entry.values_truncated then summary = summary .. " · values limited" end

    local lines = {
        summary .. " · " .. duration(entry.execution_ms),
        "",
    }
    local columns = {}
    local widths = {}
    for column_index, column in ipairs(entry.columns) do
        columns[column_index] = truncate(display_value(column))
        widths[column_index] = vim.fn.strdisplaywidth(columns[column_index])
    end

    local rows = {}
    for row_index, row in ipairs(entry.rows) do
        rows[row_index] = {}
        for column_index = 1, #columns do
            local value = truncate(display_value(row[column_index]))
            rows[row_index][column_index] = value
            widths[column_index] = math.max(widths[column_index], vim.fn.strdisplaywidth(value))
        end
    end

    local function render_row(row)
        local cells = {}
        for column_index, value in ipairs(row) do
            cells[column_index] = pad(value, widths[column_index])
        end
        return table.concat(cells, " │ ")
    end

    local separators = {}
    for column_index, width in ipairs(widths) do
        separators[column_index] = string.rep("─", width)
    end

    lines[#lines + 1] = render_row(columns)
    lines[#lines + 1] = table.concat(separators, "─┼─")
    for _, row in ipairs(rows) do
        lines[#lines + 1] = render_row(row)
    end
    return lines
end

---@return string[]
function M.empty() return { "No query results yet." } end

---@return string[]
function M.executing() return { "Executing…" } end

return M
