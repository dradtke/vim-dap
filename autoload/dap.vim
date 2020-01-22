let s:job_id = 0
let s:seq = 1
let s:capabilities = {}
let s:breakpoints = {} " from path to list

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

function! dap#add_breakpoint() abort
  let l:path = expand('%:p')
  let l:line = line('.')
  if !has_key(s:breakpoints, l:path)
    let s:breakpoints[l:path] = []
  endif
  call s:set_breakpoints(l:path, add(s:breakpoints[l:path], {
        \ 'line': l:line
        \ }))
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

  let l:message = json_decode(a:data[l:i])
  if type(l:message) != v:t_dict
    call dap#log_error('Bad response, not a dict')
    return
  endif
  let g:dap_last_message = l:message

  let l:message_type = l:message['type']
  if l:message_type == 'response'
    call s:handle_response(l:message)
  elseif l:message_type == 'event'
    call s:handle_event(l:message)
  endif
endfunction

function! s:handle_response(message) abort
  let l:command = a:message['command']
  if !a:message['success']
    if l:command == 'initialize'
      call dap#log_error('Initialization failed')
      call s:reset()
    else
      call dap#log_error('Command failed: '.l:command.': '.a:message['message'])
    endif
    return
  endif

  if l:command == 'initialize'
    call dap#log('Initialization successful')
    let s:capabilities = a:message['body']
  else
    echomsg 'Command succeeded: '.l:command
  endif
endfunction

function! s:handle_event(message) abort
  echomsg 'Received event: '.a:message['event']
endfunction

function! s:handle_stderr(job_id, data, event_type) abort
  echomsg 'stderr: '.join(a:data, "\n")
endfunction

function! s:handle_exit(job_id, data, event_type) abort
  echomsg 'exiting'
endfunction

function! s:send_message(message) abort
  let l:data = json_encode(a:message)
  let l:content_length = strlen(l:data)
  call dap#async#job#send(s:job_id, "Content-Length: ".l:content_length."\r\n")
  call dap#async#job#send(s:job_id, "\r\n")
  call dap#async#job#send(s:job_id, l:data)
endfunction

function! s:initialize() abort
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

" TODO: this returns an error of 'Empty debug session.'
" Do we need to do something besides send an initialize request?
" Looks like we need to first do an 'attach' or 'launch' command.
" https://microsoft.github.io/debug-adapter-protocol/overview
function! s:set_breakpoints(path, points) abort
  if s:job_id == 0
    call dap#log_error('No debugger session running.')
    return
  endif
  let l:request = {
        \ 'seq': s:seq,
        \ 'type': 'request',
        \ 'command': 'setBreakpoints',
        \ 'arguments': {
        \   'source': { 'path': a:path },
        \   'breakpoints': a:points},
        \ }
  let s:seq = s:seq+1

  call s:send_message(l:request)
endfunction
