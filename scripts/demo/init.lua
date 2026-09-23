local source = assert(debug.getinfo(1, "S").source):gsub("^@", "")
local init_path = vim.fn.fnamemodify(source, ":p")
local root = vim.fn.fnamemodify(init_path, ":h:h:h")
local fixture = vim.fs.joinpath(root, "scripts", "demo", "fixtures", "shop.sql")
local db_path = vim.fn.tempname() .. ".db"

vim.opt.runtimepath:prepend(root)
vim.cmd.cd(vim.fn.fnameescape(root))
vim.g.mapleader = " "
vim.opt.background = "dark"
vim.opt.number = true
vim.opt.termguicolors = true
vim.opt.cursorline = true
vim.opt.signcolumn = "no"
vim.opt.showmode = false
vim.opt.wrap = false
pcall(vim.cmd.colorscheme, "habamax")

local result = vim.system(
    { "sqlite3", db_path },
    { stdin = table.concat(vim.fn.readfile(fixture), "\n") }
)
    :wait()
if result.code ~= 0 then error("Could not prepare SQLite demo database: " .. result.stderr) end

require("sqlite-scratch").setup()
vim.cmd("SQLiteOpen " .. vim.fn.fnameescape(db_path))
vim.api.nvim_create_autocmd("VimLeavePre", {
    once = true,
    callback = function()
        os.remove(db_path)
        os.remove(db_path .. "-journal")
        os.remove(db_path .. "-wal")
        os.remove(db_path .. "-shm")
    end,
})
