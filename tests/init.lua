vim.cmd([[let &runtimepath.=','.getcwd()]])
pcall(vim.cmd, "packadd mini.nvim")

if #vim.api.nvim_list_uis() == 0 then require("mini.test").setup() end
