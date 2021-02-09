function! dap#lsp#execute_command(command, args, callback) abort
  if s:has_neovim_lsp()
    let s:last_callback = a:callback
    call luaeval('require"dap".execute_command(_A[1], _A[2])', [a:command, a:args])
  elseif s:has_languageclient_neovim()
    call LanguageClient#workspace_executeCommand(a:command, a:args, a:callback)
  elseif s:has_vim_lsp()
    call s:vim_lsp_execute_command(a:command, a:args, a:callback)
  else
    echoerr 'No supported language client installed!'
  endif
endfunction

function! dap#lsp#execute_command_callback(result) abort
  if !exists('s:last_callback')
    echoerr 'Expected s:last_callback to be defined, but it was not'
  else
    call s:last_callback(a:result)
    unlet s:last_callback
  endif
endfunction

function! s:vim_lsp_execute_command(command, args, callback) abort
    let l:allowed_servers = lsp#get_allowed_servers()
    if empty(l:allowed_servers)
      echoerr 'No allowed servers found, is the server running?'
    else
      call lsp#send_request(l:allowed_servers[0], {
            \ 'method': 'workspace/executeCommand',
            \ 'params': {
            \     'command': a:command,
            \     'arguments': a:args,
            \ },
            \ 'on_notification': {data->s:vim_lsp_handle_execute_command_response(data, a:callback)},
            \ })
    endif
endfunction

function! s:vim_lsp_handle_execute_command_response(data, callback) abort
  let l:response = a:data['response']
  if lsp#client#is_error(l:response)
    let l:error = l:response['error']
    call lsp#utils#error(l:error['code'].': '.l:error['message'])
  else
    call call(a:callback, [l:response])
  endif
endfunction

function! s:has_neovim_lsp()
  return has('nvim-0.5')
endfunction

function! s:has_languageclient_neovim()
  return exists('g:LanguageClient_loaded') && g:LanguageClient_loaded
endfunction

function! s:has_vim_lsp()
  return exists('g:lsp_loaded') && g:lsp_loaded
endfunction
