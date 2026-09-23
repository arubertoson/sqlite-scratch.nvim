local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            require("sqlite-scratch.session").close()
            require("sqlite-scratch").setup({ keymaps = true })
            vim.cmd("silent! %bwipeout!")
        end,
        post_case = function()
            require("sqlite-scratch.session").close()
            vim.cmd("silent! %bwipeout!")
        end,
    },
})

T["history"] = MiniTest.new_set()

T["history"]["caps, navigates, and deletes entries"] = function()
    local history = require("sqlite-scratch.history")
    local value = history.new(2)
    local function entry(sql)
        return {
            sql = sql,
            columns = {},
            rows = {},
            error = nil,
            truncated = false,
            values_truncated = false,
            execution_ms = 1,
            timestamp = 0,
        }
    end

    history.append(value, entry("one"))
    history.append(value, entry("two"))
    history.append(value, entry("three"))

    MiniTest.expect.equality(#value.entries, 2)
    MiniTest.expect.equality(history.current(value).sql, "three")
    MiniTest.expect.equality(history.navigate(value, -1), true)
    MiniTest.expect.equality(history.current(value).sql, "two")
    MiniTest.expect.equality(history.delete_current(value), true)
    MiniTest.expect.equality(history.current(value).sql, "three")
end

T["history"]["promotes identical executions instead of duplicating them"] = function()
    local history = require("sqlite-scratch.history")
    local value = history.new()
    local function entry(sql, rows, timestamp)
        return {
            sql = sql,
            columns = { "value" },
            rows = rows,
            error = nil,
            truncated = false,
            values_truncated = false,
            execution_ms = timestamp,
            timestamp = timestamp,
        }
    end

    history.append(value, entry("SELECT 1", { { "1" } }, 1))
    history.append(value, entry("SELECT 2", { { "2" } }, 2))
    history.append(value, entry("SELECT 1", { { "1" } }, 3))

    MiniTest.expect.equality(#value.entries, 2)
    MiniTest.expect.equality(value.entries[1].sql, "SELECT 2")
    MiniTest.expect.equality(value.entries[2].sql, "SELECT 1")
    MiniTest.expect.equality(value.entries[2].timestamp, 3)
    MiniTest.expect.equality(value.index, 2)

    history.append(value, entry("SELECT 1", { { "changed" } }, 4))
    MiniTest.expect.equality(#value.entries, 3)
end

T["scope"] = MiniTest.new_set()

T["scope"]["extracts buffer, line, and characterwise selection"] = function()
    local scope = require("sqlite-scratch.scope")
    local buffer = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
        "SELECT one,",
        "two FROM example;",
    })

    MiniTest.expect.equality(scope.buffer(buffer), "SELECT one,\ntwo FROM example;")
    MiniTest.expect.equality(scope.line(buffer, 2), "two FROM example;")
    MiniTest.expect.equality(scope.region({ 0, 1, 8, 0 }, { 0, 2, 3, 0 }, "v"), "one,\ntwo")
end

T["adapter"] = MiniTest.new_set()

T["adapter"]["configures sqls for its database"] = function()
    local db_path = "/tmp/example.db"
    local config = require("sqlite-scratch.adapters.sqlite").new(db_path):lsp_config()

    MiniTest.expect.equality(config.name, "sqls")
    MiniTest.expect.equality(config.cmd, { "sqls" })
    MiniTest.expect.equality(config.root_dir, "/tmp")
    MiniTest.expect.equality(config.settings.sqls.lowercaseKeywords, true)
    MiniTest.expect.equality(config.settings.sqls.connections, {
        {
            alias = "example.db",
            driver = "sqlite3",
            dataSourceName = db_path,
        },
    })
end

T["adapter"]["streams quoted CSV and discards records beyond its limit"] = function()
    local helpers = require("sqlite-scratch.adapters.sqlite")._test
    local parser = helpers.new_csv_parser(2, 1024)

    helpers.feed_csv(parser, 'name,note\nAlice,"hello, ')
    helpers.feed_csv(parser, '""world"""\nignored,row\n')
    local records, err = helpers.finish_csv(parser)

    MiniTest.expect.equality(err, nil)
    MiniTest.expect.equality(records, {
        { "name", "note" },
        { "Alice", 'hello, "world"' },
    })
    MiniTest.expect.equality(parser.truncated, true)
    MiniTest.expect.equality(parser.discard, true)
end

T["adapter"]["limits retained cell bytes"] = function()
    local helpers = require("sqlite-scratch.adapters.sqlite")._test
    local parser = helpers.new_csv_parser(2, 5)

    helpers.feed_csv(parser, "value\nabcdefgh\n")
    local records, err = helpers.finish_csv(parser)

    MiniTest.expect.equality(err, nil)
    MiniTest.expect.equality(records, {
        { "value" },
        { "abcde…" },
    })
    MiniTest.expect.equality(parser.values_truncated, true)
end

T["render"] = MiniTest.new_set()

T["render"]["renders successful execution without a result set"] = function()
    local lines = require("sqlite-scratch.render").result({
        sql = "UPDATE users SET active = 0",
        columns = {},
        rows = {},
        error = nil,
        truncated = false,
        values_truncated = false,
        execution_ms = 2,
        timestamp = 0,
    }, 1, 1)

    MiniTest.expect.equality(lines, { "[1/1] Completed · no result set · 2ms" })
end

T["render"]["renders tables, nulls, and errors"] = function()
    local render = require("sqlite-scratch.render")
    local lines = render.result({
        sql = "select 1",
        columns = { "id", "value" },
        rows = { { "1", vim.NIL } },
        error = nil,
        truncated = false,
        values_truncated = false,
        execution_ms = 8,
        timestamp = 0,
    }, 1, 1)

    MiniTest.expect.equality(lines[1], "[1/1] 1 row · 8ms")
    MiniTest.expect.equality(lines[3], "id │ value")
    MiniTest.expect.equality(lines[5], "1  │ NULL ")

    lines = render.result({
        sql = "select banana",
        columns = {},
        rows = {},
        error = "no such column: banana",
        truncated = false,
        values_truncated = false,
        execution_ms = 2,
        timestamp = 0,
    }, 2, 3)
    MiniTest.expect.equality(lines, {
        "[2/3] SQLite error · 2ms",
        "",
        "no such column: banana",
    })
end

T["session"] = MiniTest.new_set()

T["session"]["default scratchpad mappings can be disabled"] = function()
    require("sqlite-scratch").setup({ keymaps = false })
    local session = require("sqlite-scratch.session")
    session.open(vim.fn.tempname() .. ".db")
    local active = session.current()
    for _, buf in ipairs({ active.query_buf, active.result_buf }) do
        for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
            MiniTest.expect.equality(mapping.lhs ~= "[r" and mapping.lhs ~= "]r", true)
        end
    end
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(active.query_buf, "n")) do
        MiniTest.expect.equality(mapping.desc ~= "Execute SQLite buffer", true)
    end
end

T["session"]["executes asynchronously without moving query focus"] = function()
    local db_path = vim.fn.tempname() .. ".db"
    local session = require("sqlite-scratch.session")
    local initial_tab_count = #vim.api.nvim_list_tabpages()
    local initial_tabline = vim.o.tabline
    local query_buf = session.open(db_path)
    local active = session.current()
    local scratchpad_tab = active.ui.tabpage
    MiniTest.expect.equality(require("sqlite-scratch").is_visible(), true)
    vim.cmd("tabnew")
    MiniTest.expect.equality(require("sqlite-scratch").is_visible(), false)
    vim.cmd("tabclose")
    MiniTest.expect.equality(require("sqlite-scratch").is_visible(), true)
    local lsp_client = vim.lsp.get_client_by_id(active.lsp_client_id)

    MiniTest.expect.equality(lsp_client ~= nil, true)
    MiniTest.expect.equality(
        lsp_client.config.settings.sqls.connections[1].dataSourceName,
        db_path
    )
    MiniTest.expect.equality(vim.b[query_buf].sqlite_scratch_query, true)
    MiniTest.expect.equality(vim.api.nvim_buf_get_name(query_buf), "")
    MiniTest.expect.equality(
        vim.t[scratchpad_tab].sqlite_scratch_tab_label,
        "SQLite: " .. vim.fs.basename(db_path)
    )
    MiniTest.expect.equality(
        require("sqlite-scratch.ui").tabline():find("SQLite:", 1, true) ~= nil,
        true
    )

    session.execute(" \n\t")
    MiniTest.expect.equality(active.process, nil)
    MiniTest.expect.equality(#active.history.entries, 0)

    local first_sql = table.concat({
        "-- A leading comment must be sent as SQL, not parsed as a CLI option.",
        "SELECT 1 AS id, NULL AS value",
        "UNION ALL SELECT 2, 'hello';",
    }, "\n")
    vim.api.nvim_buf_set_lines(query_buf, 0, -1, false, vim.split(first_sql, "\n"))
    vim.api.nvim_set_current_win(active.query_win)
    session.execute(first_sql)

    local completed = vim.wait(3000, function()
        local current = session.current()
        return current ~= nil and #current.history.entries == 1
    end)
    MiniTest.expect.equality(completed, true)

    active = session.current()
    MiniTest.expect.equality(vim.api.nvim_get_current_win(), active.query_win)
    MiniTest.expect.equality(active.history.entries[1].sql, first_sql)
    MiniTest.expect.equality(active.history.entries[1].columns, { "id", "value" })
    MiniTest.expect.equality(active.history.entries[1].rows, {
        { "1", vim.NIL },
        { "2", "hello" },
    })

    session.toggle_sql_preview()
    local preview = active.ui.sql_preview
    MiniTest.expect.equality(preview ~= nil, true)
    MiniTest.expect.equality(vim.api.nvim_win_is_valid(preview.win), true)
    MiniTest.expect.equality(vim.api.nvim_win_get_config(preview.win).anchor, "NE")
    MiniTest.expect.equality(
        vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false),
        vim.split(first_sql, "\n", { plain = true })
    )

    local second_sql = table.concat({
        "-- Output is bounded without rewriting this SQL.",
        "WITH RECURSIVE numbers(value) AS (",
        "  SELECT 1 UNION ALL SELECT value + 1 FROM numbers WHERE value < 40",
        ") SELECT value FROM numbers;",
    }, "\n")
    vim.api.nvim_buf_set_lines(query_buf, 0, -1, false, vim.split(second_sql, "\n"))
    session.execute(second_sql)
    completed = vim.wait(3000, function()
        local current = session.current()
        return current ~= nil and #current.history.entries == 2
    end)
    MiniTest.expect.equality(completed, true)

    active = session.current()
    MiniTest.expect.equality(#active.history.entries[2].rows, 30)
    MiniTest.expect.equality(active.history.entries[2].truncated, true)
    MiniTest.expect.equality(
        vim.api.nvim_buf_get_lines(active.ui.sql_preview.buf, 0, -1, false),
        vim.split(second_sql, "\n", { plain = true })
    )
    MiniTest.expect.equality(
        vim.api.nvim_buf_get_lines(active.result_buf, 0, 1, false)[1]:find("30+ rows", 1, true)
            ~= nil,
        true
    )

    local function press(lhs)
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, false, true), "xt", false)
    end
    for _, win in ipairs({ active.query_win, active.result_win }) do
        vim.api.nvim_set_current_win(win)
        press("[r")
        MiniTest.expect.equality(active.history.index, 1)
        press("]r")
        MiniTest.expect.equality(active.history.index, 2)
        MiniTest.expect.equality(vim.api.nvim_get_current_win(), win)
        for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(vim.api.nvim_win_get_buf(win), "n")) do
            MiniTest.expect.equality(mapping.lhs ~= "<M-h>" and mapping.lhs ~= "<M-l>", true)
        end
    end
    vim.api.nvim_set_current_win(active.query_win)

    local export_path = vim.fn.tempname() .. ".csv"
    session.export(export_path, false)
    local exported = vim.wait(3000, function()
        local current = session.current()
        return current ~= nil and current.process == nil and vim.fn.filereadable(export_path) == 1
    end)
    MiniTest.expect.equality(exported, true)
    local exported_lines = vim.fn.readfile(export_path)
    MiniTest.expect.equality(#exported_lines, 41)
    MiniTest.expect.equality(exported_lines[1], "value")
    MiniTest.expect.equality(exported_lines[41], "40")
    os.remove(export_path)

    MiniTest.expect.equality(vim.bo[active.result_buf].modifiable, false)
    MiniTest.expect.equality(vim.wo[active.result_win].wrap, false)
    MiniTest.expect.equality(vim.wo[active.result_win].cursorcolumn, false)

    vim.cmd("topleft vnew")
    local layout_updated = vim.wait(1000, function()
        local layout = vim.fn.winlayout()
        return layout[1] == "col"
            and layout[2][2][1] == "leaf"
            and layout[2][2][2] == active.result_win
    end)
    MiniTest.expect.equality(layout_updated, true)
    MiniTest.expect.equality(vim.api.nvim_win_get_width(active.result_win), vim.o.columns)
    MiniTest.expect.equality(
        vim.api.nvim_win_get_height(active.result_win),
        active.ui.result_height
    )
    MiniTest.expect.equality(vim.wo[active.result_win].winfixheight, true)

    session.close()
    MiniTest.expect.equality(session.is_active(), false)
    MiniTest.expect.equality(vim.api.nvim_tabpage_is_valid(scratchpad_tab), false)
    MiniTest.expect.equality(#vim.api.nvim_list_tabpages(), initial_tab_count)
    MiniTest.expect.equality(vim.o.tabline, initial_tabline)
    MiniTest.expect.equality(vim.api.nvim_buf_is_valid(query_buf), false)
end

T["session"]["closing the scratchpad tab cleans up the active session"] = function()
    local session = require("sqlite-scratch.session")
    local history = require("sqlite-scratch.history")
    local initial_tabline = vim.o.tabline
    local initial_tab_count = #vim.api.nvim_list_tabpages()
    session.open(vim.fn.tempname() .. ".db")
    local active = session.current()

    history.append(active.history, {
        sql = "SELECT 1;",
        columns = { "1" },
        rows = { { "1" } },
        error = nil,
        truncated = false,
        values_truncated = false,
        execution_ms = 1,
        timestamp = 0,
    })
    session.toggle_sql_preview()
    local preview_buf = active.ui.sql_preview.buf
    local process_killed = false
    active.process = {
        kill = function(_, signal) process_killed = signal == 15 end,
    }

    local tab_number = vim.api.nvim_tabpage_get_number(active.ui.tabpage)
    vim.cmd(tab_number .. "tabclose!")

    local cleaned = vim.wait(1000, function() return not session.is_active() end)
    MiniTest.expect.equality(cleaned, true)
    MiniTest.expect.equality(process_killed, true)
    MiniTest.expect.equality(vim.api.nvim_buf_is_valid(active.query_buf), false)
    MiniTest.expect.equality(vim.api.nvim_buf_is_valid(active.result_buf), false)
    MiniTest.expect.equality(vim.api.nvim_buf_is_valid(preview_buf), false)
    MiniTest.expect.equality(#vim.api.nvim_list_tabpages(), initial_tab_count)
    MiniTest.expect.equality(vim.o.tabline, initial_tabline)
end

T["session"]["losing an owned window or result buffer closes the scratchpad"] = function()
    local session = require("sqlite-scratch.session")
    local initial_tab_count = #vim.api.nvim_list_tabpages()

    local cases = {
        {
            name = "query window",
            lose = function(active) vim.api.nvim_win_close(active.query_win, true) end,
        },
        {
            name = "result window",
            lose = function(active) vim.api.nvim_win_close(active.result_win, true) end,
        },
        {
            name = "result buffer",
            lose = function(active)
                vim.api.nvim_win_set_buf(active.result_win, vim.api.nvim_create_buf(false, true))
            end,
        },
    }

    for _, case in ipairs(cases) do
        session.open(vim.fn.tempname() .. ".db")
        local active = session.current()
        local tabpage = active.ui.tabpage
        case.lose(active)

        local cleaned = vim.wait(1000, function() return not session.is_active() end)
        MiniTest.expect.equality(cleaned, true, case.name)
        MiniTest.expect.equality(vim.api.nvim_tabpage_is_valid(tabpage), false, case.name)
        MiniTest.expect.equality(#vim.api.nvim_list_tabpages(), initial_tab_count, case.name)
    end
end

T["session"]["editing a file in the query window keeps the scratchpad active"] = function()
    local session = require("sqlite-scratch.session")
    local sql_path = vim.fn.tempname() .. ".sql"
    vim.fn.writefile({ "SELECT 42;" }, sql_path)

    session.open(vim.fn.tempname() .. ".db")
    local active = session.current()
    vim.api.nvim_set_current_win(active.query_win)
    vim.cmd("edit " .. vim.fn.fnameescape(sql_path))

    local adopted = vim.wait(1000, function()
        local current = session.current()
        return current ~= nil
            and vim.api.nvim_buf_get_name(current.query_buf) == vim.fs.normalize(sql_path)
            and vim.b[current.query_buf].sqlite_scratch_query == true
    end)
    MiniTest.expect.equality(adopted, true)

    active = session.current()
    local file_buf = active.query_buf
    MiniTest.expect.equality(active.ui.query_buf, file_buf)
    MiniTest.expect.equality(vim.b[file_buf].sqlite_scratch_query, true)
    MiniTest.expect.equality(vim.bo[file_buf].filetype, "sql")
    MiniTest.expect.equality(vim.fn.maparg("<leader>rr", "n", false, true).buffer, 1)

    session.close()
    MiniTest.expect.equality(vim.api.nvim_buf_is_valid(file_buf), true)
    MiniTest.expect.equality(vim.b[file_buf].sqlite_scratch_query, nil)
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(file_buf, "n")) do
        MiniTest.expect.equality(mapping.lhs ~= "[r" and mapping.lhs ~= "]r", true)
    end
    os.remove(sql_path)
end

T["session"]["requires a decision before discarding a query draft"] = function()
    local first_db = vim.fn.tempname() .. ".db"
    local second_db = vim.fn.tempname() .. ".db"
    local session = require("sqlite-scratch.session")
    require("sqlite-scratch").setup()

    local query_buf = session.open(first_db)
    vim.api.nvim_buf_set_lines(query_buf, 0, -1, false, { "SELECT 1;" })

    local original_confirm = vim.fn.confirm
    local confirmation = 1
    local prompts = 0
    vim.fn.confirm = function()
        prompts = prompts + 1
        return confirmation
    end

    local ok, err = pcall(function()
        vim.cmd("SQLiteOpen " .. vim.fn.fnameescape(second_db))
        MiniTest.expect.equality(session.current().db_path, first_db)
        MiniTest.expect.equality(vim.api.nvim_buf_is_valid(query_buf), true)

        confirmation = 2
        vim.cmd("SQLiteOpen " .. vim.fn.fnameescape(second_db))
        MiniTest.expect.equality(session.current().db_path, second_db)
        MiniTest.expect.equality(vim.api.nvim_buf_is_valid(query_buf), false)
        MiniTest.expect.equality(prompts, 2)
    end)
    vim.fn.confirm = original_confirm
    if not ok then error(err) end
end

return T
