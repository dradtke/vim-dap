local M = {}

function M.execute_command(buffer, command, args)
  function handler(err, method, result, client_id, bufnr, config)
    require("vim.lsp.log").warn("Returned for command "..command)
    if err then
      require("vim.lsp.log").warn(tostring(err))
      error(tostring(err))
    else
      require("vim.lsp.log").warn("Got result "..vim.inspect(result))
      vim.fn["dap#lsp#execute_command_callback"]({result = result})
    end
  end

  local params = { command = command, arguments = args }
  require("vim.lsp.log").warn("Executing command "..command)
  vim.lsp.buf_request(buffer, "workspace/executeCommand", params, handler)
end

return M
