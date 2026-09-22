---@module "sqlite-scratch.scope"
---Extracts exact SQL execution scopes from a query buffer.

local M = {}

---@param buffer integer
---@return string
function M.buffer(buffer)
    return table.concat(vim.api.nvim_buf_get_lines(buffer, 0, -1, false), "\n")
end

---@param buffer integer
---@param line integer 1-indexed buffer line
---@return string
function M.line(buffer, line) return vim.api.nvim_buf_get_lines(buffer, line - 1, line, false)[1] end

---@param first integer[] Position in getpos() format
---@param last integer[] Position in getpos() format
---@param selection_type string
---@return string
function M.region(first, last, selection_type)
    return table.concat(vim.fn.getregion(first, last, { type = selection_type }), "\n")
end

return M
