function! dap#io#sockconnect(address, on_data) abort
  if has('nvim')
    return sockconnect('tcp', a:address, {'on_data': {chan_id, data, name -> a:on_data(data)}})
  elseif has('channel')
    return ch_open(a:address, {'mode': 'raw', 'callback': {chan_id, data -> a:on_data(data)}})
  else
    throw 'Must be running Neovim or Vim with channel support'
  endif
endfunction

function! dap#io#sockclose(socket) abort
  if has('nvim')
    call chanclose(a:socket)
  elseif has('channel')
    call ch_close(a:socket)
  else
    throw 'Must be running Neovim or Vim with channel support'
  endif
endfunction

function! dap#io#send(id, data) abort
  if has('nvim')
    call chansend(a:id, a:data)
  elseif has('channel')
    call ch_sendraw(a:id, a:data)
  else
    throw 'Must be running Neovim or Vim with channel support'
  endif
endfunction

function! dap#io#jobstart(args, on_stdout, on_stderr, on_exit) abort
  if has('nvim')
    return jobstart(a:args, {
          \ 'on_stdout': {job_id, data, name -> a:on_stdout(data)},
          \ 'on_stderr': {job_id, data, name -> a:on_stderr(data)},
          \ 'on_exit': {job_id, data, name -> a:on_exit(data)},
          \ })
  elseif has('job')
    return job_start(a:args, {'mode': 'raw', 
          \ 'out_cb': {job_id, data -> a:on_stdout(data)},
          \ 'err_cb': {job_id, data -> a:on_stderr(data)},
          \ 'exit_cb': {job_id, data -> a:on_exit(data)},
          \ })
  else
    throw 'Must be running Neovim or Vim with job support'
  endif
endfunction

function! dap#io#jobstop(id) abort
  if has('nvim')
    call jobstop(a:id)
  elseif has('job')
    call job_stop(a:id)
  else
    throw 'Must be running Neovim or Vim with job support'
  endif
endfunction
