---@module "sqlite-scratch.history"
---In-memory result history for a SQLite scratchpad.

local M = {}

---@class SqliteScratch.Result
---@field sql string
---@field columns string[]
---@field rows any[][]
---@field error string|nil
---@field truncated boolean
---@field values_truncated boolean
---@field execution_ms number
---@field timestamp integer

---@class SqliteScratch.History
---@field entries SqliteScratch.Result[]
---@field index integer
---@field max_size integer

---@param max_size? integer
---@return SqliteScratch.History
function M.new(max_size) return { entries = {}, index = 0, max_size = max_size or 50 } end

---@param left SqliteScratch.Result
---@param right SqliteScratch.Result
---@return boolean
local function same_execution(left, right)
    return left.sql == right.sql
        and left.error == right.error
        and left.truncated == right.truncated
        and left.values_truncated == right.values_truncated
        and vim.deep_equal(left.columns, right.columns)
        and vim.deep_equal(left.rows, right.rows)
end

---@param history SqliteScratch.History
---@param entry SqliteScratch.Result
function M.append(history, entry)
    for index = #history.entries, 1, -1 do
        if same_execution(history.entries[index], entry) then
            table.remove(history.entries, index)
            break
        end
    end

    history.entries[#history.entries + 1] = entry
    if #history.entries > history.max_size then table.remove(history.entries, 1) end
    history.index = #history.entries
end

---@param history SqliteScratch.History
---@return SqliteScratch.Result|nil
function M.current(history)
    if history.index == 0 then return nil end
    return history.entries[history.index]
end

---@param history SqliteScratch.History
---@param delta integer
---@return boolean
function M.navigate(history, delta)
    local target = history.index + delta
    if target < 1 or target > #history.entries then return false end
    history.index = target
    return true
end

---@param history SqliteScratch.History
---@return boolean
function M.delete_current(history)
    if history.index == 0 then return false end

    table.remove(history.entries, history.index)
    if #history.entries == 0 then
        history.index = 0
    elseif history.index > #history.entries then
        history.index = #history.entries
    end
    return true
end

return M
