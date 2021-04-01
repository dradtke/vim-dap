local M = {}

function M.execute_command(buffer, command, args)
  function handler(err, method, result, client_id, bufnr, config)
    if err then
      error(tostring(err))
    else
      vim.fn["dap#lsp#execute_command_callback"]({result = result})
    end
  end

  local params = { command = command, arguments = args }
  vim.lsp.buf_request(buffer, "workspace/executeCommand", params, handler)
end

return M
