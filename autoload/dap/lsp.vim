function! dap#lsp#execute_command(command, args, callback) abort
  if s:has_languageclient_neovim()
    call LanguageClient#workspace_executeCommand(a:command, a:args, a:callback)
  else
    echoerr 'No supported language client installed!'
  endif
endfunction

function! s:has_languageclient_neovim()
  return exists('g:LanguageClient_loaded') && g:LanguageClient_loaded
endfunction
