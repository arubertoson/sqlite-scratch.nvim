---@module "sqlite-scratch.adapters.sqlite"
---Asynchronous sqlite3 CLI adapter.

local M = {}
local ROW_LIMIT = 30
local CELL_BYTE_LIMIT = 64 * 1024
local STDERR_BYTE_LIMIT = 64 * 1024

---@class SqliteScratch.AdapterResult
---@field columns string[]
---@field rows any[][]
---@field error string|nil
---@field truncated boolean
---@field values_truncated boolean
---@field execution_ms number
---@field timestamp integer

---@class SqliteScratch.ExportResult
---@field error string|nil
---@field execution_ms number

---@class SqliteScratch.Adapter
---@field db_path string
local Adapter = {}
Adapter.__index = Adapter

---@class SqliteScratch.CsvParser
---@field records string[][]
---@field record string[]
---@field field string[]
---@field field_bytes integer
---@field field_truncated boolean
---@field record_started boolean
---@field quoted boolean
---@field pending_quote boolean
---@field pending_lf boolean
---@field max_records integer
---@field max_cell_bytes integer
---@field truncated boolean
---@field values_truncated boolean
---@field discard boolean

---@param value string
---@return string
local function trim(value) return value:match("^%s*(.-)%s*$") or "" end

---@param value string
---@return string
local function valid_utf8_prefix(value)
    local length = #value
    if length == 0 then return value end

    local start = length
    while start > 1 do
        local byte = value:byte(start)
        if byte < 0x80 or byte >= 0xC0 then break end
        start = start - 1
    end

    local lead = value:byte(start)
    local expected
    if lead < 0x80 then
        expected = 1
    elseif lead < 0xE0 then
        expected = 2
    elseif lead < 0xF0 then
        expected = 3
    elseif lead < 0xF8 then
        expected = 4
    else
        return value:sub(1, start - 1)
    end

    if length - start + 1 < expected then return value:sub(1, start - 1) end
    return value
end

---@param max_records integer
---@param max_cell_bytes integer
---@return SqliteScratch.CsvParser
local function new_csv_parser(max_records, max_cell_bytes)
    return {
        records = {},
        record = {},
        field = {},
        field_bytes = 0,
        field_truncated = false,
        record_started = false,
        quoted = false,
        pending_quote = false,
        pending_lf = false,
        max_records = max_records,
        max_cell_bytes = max_cell_bytes,
        truncated = false,
        values_truncated = false,
        discard = false,
    }
end

---@param parser SqliteScratch.CsvParser
---@param character string
local function append_character(parser, character)
    parser.record_started = true
    parser.field_bytes = parser.field_bytes + 1
    if parser.field_bytes <= parser.max_cell_bytes then
        parser.field[#parser.field + 1] = character
    else
        parser.field_truncated = true
        parser.values_truncated = true
    end
end

---@param parser SqliteScratch.CsvParser
local function finish_field(parser)
    local value = valid_utf8_prefix(table.concat(parser.field))
    if parser.field_truncated then value = value .. "…" end
    parser.record[#parser.record + 1] = value
    parser.field = {}
    parser.field_bytes = 0
    parser.field_truncated = false
end

---@param parser SqliteScratch.CsvParser
local function finish_record(parser)
    finish_field(parser)
    parser.records[#parser.records + 1] = parser.record
    parser.record = {}
    parser.record_started = false
end

---@param parser SqliteScratch.CsvParser
---@param character string
local function process_csv_character(parser, character)
    local unquoted = not parser.quoted
    if parser.quoted then
        if parser.pending_quote then
            if character == '"' then
                append_character(parser, character)
                parser.pending_quote = false
            else
                parser.quoted = false
                parser.pending_quote = false
                unquoted = true
            end
        elseif character == '"' then
            parser.pending_quote = true
        else
            append_character(parser, character)
        end
    end

    if not unquoted then return end

    if character == '"' and parser.field_bytes == 0 then
        parser.quoted = true
        parser.record_started = true
    elseif character == "," then
        parser.record_started = true
        finish_field(parser)
    elseif character == "\n" then
        finish_record(parser)
    elseif character == "\r" then
        finish_record(parser)
        parser.pending_lf = true
    else
        append_character(parser, character)
    end
end

---@param parser SqliteScratch.CsvParser
---@param input string
local function feed_csv(parser, input)
    if input == "" or parser.discard then return end

    local index = 1
    while index <= #input do
        local character = input:sub(index, index)
        if parser.pending_lf then
            parser.pending_lf = false
            if character == "\n" then
                index = index + 1
                character = input:sub(index, index)
            end
        end
        if character == "" then return end

        if #parser.records == parser.max_records then
            parser.truncated = true
            parser.discard = true
            return
        end

        process_csv_character(parser, character)
        index = index + 1
    end
end

---@param parser SqliteScratch.CsvParser
---@return string[][]|nil records
---@return string|nil error
local function finish_csv(parser)
    if parser.discard then return parser.records, nil end
    if parser.quoted and not parser.pending_quote then
        return nil, "sqlite3 returned malformed CSV"
    end
    if parser.record_started then finish_record(parser) end
    return parser.records, nil
end

---@param input string
---@param max_records integer
---@return string[][]|nil
---@return string|nil
local function parse_csv(input, max_records)
    local parser = new_csv_parser(max_records, CELL_BYTE_LIMIT)
    feed_csv(parser, input)
    return finish_csv(parser)
end

---@param stderr string
---@return string
local function sqlite_error(stderr)
    local message = trim(stderr)
    message = message:gsub("^Error:%s*", "")
    message = message:gsub("^in prepare,%s*", "")
    return message ~= "" and message or "sqlite3 exited without an error message"
end

---@param db_path string
---@return SqliteScratch.Adapter
function M.new(db_path) return setmetatable({ db_path = db_path }, Adapter) end

---@return string[]
function M.lsp_command() return { "sqls" } end

---@return vim.lsp.Config
function Adapter:lsp_config()
    return {
        name = "sqls",
        cmd = M.lsp_command(),
        root_dir = vim.fs.dirname(self.db_path),
        filetypes = { "sql" },
        settings = {
            sqls = {
                lowercaseKeywords = true,
                connections = {
                    {
                        alias = vim.fs.basename(self.db_path),
                        driver = "sqlite3",
                        dataSourceName = self.db_path,
                    },
                },
            },
        },
    }
end

---@param sql string
---@param callback fun(result: SqliteScratch.AdapterResult)
---@return vim.SystemObj
function Adapter:execute(sql, callback)
    local started_at = vim.uv.hrtime()
    local null_value = ("__SQLITE_SCRATCH_NULL_%x__"):format(started_at)
    local command = {
        "sqlite3",
        "-batch",
        "-csv",
        "-nullvalue",
        null_value,
        self.db_path,
    }
    local parser = new_csv_parser(ROW_LIMIT + 1, CELL_BYTE_LIMIT)
    local stdout_error
    local stderr = {}
    local stderr_bytes = 0

    local input = ".headers on\n" .. sql
    return vim.system(command, {
        text = true,
        stdin = input,
        stdout = function(err, data)
            if err then
                stdout_error = err
            elseif data then
                feed_csv(parser, data)
            end
        end,
        stderr = function(_, data)
            if not data or stderr_bytes >= STDERR_BYTE_LIMIT then return end
            local remaining = STDERR_BYTE_LIMIT - stderr_bytes
            local chunk = data:sub(1, remaining)
            stderr[#stderr + 1] = chunk
            stderr_bytes = stderr_bytes + #chunk
        end,
    }, function(completed)
        local execution_ms = (vim.uv.hrtime() - started_at) / 1000000
        local result = {
            columns = {},
            rows = {},
            error = nil,
            truncated = parser.truncated,
            values_truncated = parser.values_truncated,
            execution_ms = execution_ms,
            timestamp = os.time(),
        }

        if stdout_error then
            result.error = "Failed to read sqlite3 output: " .. stdout_error
        elseif completed.code ~= 0 then
            result.error = sqlite_error(table.concat(stderr))
        else
            local records, parse_error = finish_csv(parser)
            if parse_error then
                result.error = parse_error
            elseif #records > 0 then
                result.columns = records[1]
                for record_index = 2, #records do
                    local row = records[record_index]
                    for column_index, value in ipairs(row) do
                        if value == null_value then row[column_index] = vim.NIL end
                    end
                    result.rows[#result.rows + 1] = row
                end
            end
        end

        vim.schedule(function() callback(result) end)
    end)
end

---@param sql string
---@param path string
---@param overwrite boolean
---@param callback fun(result: SqliteScratch.ExportResult)
---@return vim.SystemObj|nil
function Adapter:export(sql, path, overwrite, callback)
    local started_at = vim.uv.hrtime()
    if not overwrite and vim.uv.fs_stat(path) then
        vim.schedule(
            function()
                callback({
                    error = "File already exists (use :SQLiteExport! to overwrite): " .. path,
                    execution_ms = 0,
                })
            end
        )
        return nil
    end

    local temporary_path = ("%s.sqlite-scratch-%x.tmp"):format(path, started_at)
    local file, open_error = io.open(temporary_path, "wb")
    if not file then
        vim.schedule(
            function()
                callback({
                    error = "Failed to open export file: " .. tostring(open_error),
                    execution_ms = 0,
                })
            end
        )
        return nil
    end

    local command = { "sqlite3", "-batch", "-csv", self.db_path }
    local stderr = {}
    local stderr_bytes = 0
    local write_error

    return vim.system(command, {
        stdin = ".headers on\n" .. sql,
        stdout = function(err, data)
            if write_error then return end
            if err then
                write_error = tostring(err)
            elseif data then
                local written, message = file:write(data)
                if not written then write_error = tostring(message) end
            end
        end,
        stderr = function(_, data)
            if not data or stderr_bytes >= STDERR_BYTE_LIMIT then return end
            local remaining = STDERR_BYTE_LIMIT - stderr_bytes
            local chunk = data:sub(1, remaining)
            stderr[#stderr + 1] = chunk
            stderr_bytes = stderr_bytes + #chunk
        end,
    }, function(completed)
        local execution_ms = (vim.uv.hrtime() - started_at) / 1000000
        local closed, close_error = file:close()
        local export_error

        if completed.code ~= 0 then
            export_error = sqlite_error(table.concat(stderr))
        elseif write_error then
            export_error = "Failed to write export: " .. write_error
        elseif not closed then
            export_error = "Failed to close export file: " .. tostring(close_error)
        else
            local renamed, rename_error = vim.uv.fs_rename(temporary_path, path)
            if not renamed then
                export_error = "Failed to finish export: " .. tostring(rename_error)
            end
        end

        if export_error then os.remove(temporary_path) end
        vim.schedule(
            function() callback({ error = export_error, execution_ms = execution_ms }) end
        )
    end)
end

M._test = {
    new_csv_parser = new_csv_parser,
    feed_csv = feed_csv,
    finish_csv = finish_csv,
    parse_csv = parse_csv,
}

return M
