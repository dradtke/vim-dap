if !exists('s:job_id') | let s:job_id = 0 | endif
if !exists('s:seq') | let s:seq = 1 | endif
if !exists('s:capabilities') | let s:capabilities = {} | endif

function! dap#connect(host, port) abort
  "if s:job_id != 0
  "  call dap#log_error('Already connected.')
  "  return
  "endif
  call dap#log('Connecting to debugger at '.a:host.':'.a:port.'...')
  let s:job_id = dap#async#job#start(['nc', a:host, a:port], {
        \ 'on_stdout': function('s:handle_stdout'),
        \ 'on_stderr': function('s:handle_stderr'),
        \ 'on_exit': function('s:handle_exit'),
        \ })
  call s:initialize()
endfunction

function! dap#disconnect() abort
  if s:job_id == 0
    call dap#log_error('No connection to disconnect from.')
    return
  endif
  call dap#async#job#stop(s:job_id)
  call s:reset()
endfunction

function! dap#get_capabilities() abort
  if s:job_id == 0
    call dap#log_error('No debugger session running.')
    return v:null
  endif
  return s:capabilities
endfunction

" NOTE: In order to run JUnit, you need to specify a mainClass of
" org.junit.runner.JUnitCore along with an array of classpaths.
" Unfortunately, it doesn't look like there is (yet) a way to retrieve the
" list of available classpaths from the language server: https://github.com/eclipse/eclipse.jdt.ls/pull/1312
function! dap#launch(args) abort
  let l:request = {
        \ 'seq': s:seq,
        \ 'type': 'request',
        \ 'command': 'launch',
        \ 'arguments': a:args,
        \ }
  let s:seq = s:seq+1

  call s:send_message(l:request)
endfunction

" TODO: don't echo log messages
function! dap#log(msg) abort
  echo a:msg
endfunction

function! dap#log_error(msg) abort
  echomsg a:msg
endfunction

function! s:reset()
  let s:job_id = 0
  let s:seq = 1
endfunction

function! s:handle_stdout(job_id, data, event_type) abort
  let l:headers = {}
  let l:i = 0
  while i < len(a:data)
    let l:line = trim(a:data[i])
    let l:i += 1
    if l:line == ''
      break
    endif
    let l:parts = split(l:line, ':')
    let l:headers[trim(l:parts[0])] = trim(l:parts[1])
  endwhile

  if !has_key(l:headers, 'Content-Length')
    call dap#log_error('Bad response, missing Content-Length header')
    return
  endif
  
  let l:content_length = str2nr(l:headers['Content-Length'])
  if len(a:data[l:i]) < l:content_length
    call dap#log_error('Bad response, body is missing data')
    return
  endif

  let l:response = json_decode(a:data[l:i])
  if type(l:response) != v:t_dict
    call dap#log_error('Bad response, not a dict')
    return
  endif
  let g:dap_last_response = l:response

  let l:command = l:response['command']
  if !l:response['success']
    if l:command == 'initialize'
      call dap#log_error('Initialization failed')
      call s:reset()
    else
      call dap#log_error('Command failed: '.l:command.': '.l:response['message'])
    endif
    return
  endif

  if l:command == 'initialize'
    call dap#log('Initialization successful')
    let s:capabilities = l:response['body']
  else
    echomsg 'Command succeeded: '.l:command
  endif
endfunction

function! s:handle_stderr(job_id, data, event_type) abort
  echomsg 'stderr: '.join(a:data, "\n")
endfunction

function! s:handle_exit(job_id, data, event_type) abort
  echomsg 'exiting'
endfunction

function! s:send_message(message)
  let l:data = json_encode(a:message)
  let l:content_length = strlen(l:data)
  call dap#async#job#send(s:job_id, "Content-Length: ".l:content_length."\r\n")
  call dap#async#job#send(s:job_id, "\r\n")
  call dap#async#job#send(s:job_id, l:data)
endfunction

function! s:initialize()
  " TODO: support other arguments
  let l:request = {
        \ 'seq': s:seq,
        \ 'type': 'request',
        \ 'command': 'initialize',
        \ 'arguments': {'adapterID': 'vim-dap'},
        \ }
  let s:seq = s:seq+1

  call s:send_message(l:request)
endfunction
