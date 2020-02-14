if !exists('g:dap_initialized')
  let s:job_id = -1
  let s:seq = 1
  let s:output_buffer = -1
  let s:capabilities = {}
  let s:breakpoints = {} " from path to list
  let g:dap_initialized = v:true
endif

function! dap#connect(host, port) abort
  if !executable('nc')
    echoerr 'command "nc" not found! please install netcat and try again'
    return
  endif
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
function! dap#launch(arguments) abort
  if s:job_id == 0
    echoerr 'No debug session running.'
    return
  endif
  call s:send_request('launch', a:arguments)
endfunction

function! dap#threads() abort
  call s:send_request('threads', v:null)
endfunction

function! dap#continue(thread_id) abort
  call s:send_request('continue', {'threadId': a:thread_id})
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

function! s:open_output_window() abort
  10new Output
  setlocal buftype=nofile bufhidden=hide noswapfile
  let s:output_buffer = bufnr('%')
  let g:output_buffer = s:output_buffer
endfunction

function! s:reset()
  let s:job_id = 0
  let s:seq = 1
endfunction

" TODO: better handle input coming in in weird batches

function! s:parse_message(data) abort
  let l:split_index = stridx(a:data, "\r\n\r\n")
  if l:split_index == -1
    return {'valid': v:false, 'reason': 'No content split found'}
  endif

  let l:headers = {}
  for l:line in split(a:data[:l:split_index-1], "\r\n")
    let l:parts = split(l:line, ':')
    let l:headers[trim(l:parts[0])] = trim(l:parts[1])
  endfor

  if !has_key(l:headers, 'Content-Length')
    return {'valid': v:false, 'reason': 'No Content-Length header'}
  endif

  let l:content_length = str2nr(l:headers['Content-Length'])

  let l:content_start = l:split_index + 4
  let l:content_end = l:content_start + (l:content_length - 1)
  let l:content = a:data[l:content_start:l:content_end]

  if len(l:content) != l:content_length
    " not enough content to meet Content-Length
    return {'valid': v:false, 'reason': 'Content too short'}
  endif

  return {
        \ 'valid': v:true,
        \ 'headers': l:headers,
        \ 'content': l:content,
        \ 'rest': a:data[l:content_end+1:],
        \ }
endfunction

let s:message_buffer = ''

function! s:handle_stdout(job_id, data, event_type) abort
  let s:message_buffer .= join(a:data, "\n")

  while v:true
    let l:message = s:parse_message(s:message_buffer)
    if !l:message['valid']
      " echo 'Message not valid: '.l:message['reason']
      return
    endif

    echo 'Found a valid message'

    let s:message_buffer = l:message['rest']
    
    let l:body = json_decode(l:message['content'])
    if type(l:body) != v:t_dict
      call dap#log_error('Bad response, not a dict')
      return
    endif

    let g:dap_last_message = l:body

    let l:message_type = l:body['type']
    if l:message_type == 'response'
      echo 'handling response'
      call s:handle_response(l:body)
    elseif l:message_type == 'event'
      echo 'handling event'
      call s:handle_event(l:body)
    endif
  endwhile
endfunction

function! s:handle_response(data) abort
  let l:command = a:data['command']
  if !a:data['success']
    if l:command == 'initialize'
      call dap#log_error('Initialization failed')
      call s:reset()
    else
      call dap#log_error('Command failed: '.l:command.': '.a:data['message'])
    endif
    return
  endif

  if l:command == 'initialize'
    call dap#log('Initialization successful')
    let s:capabilities = a:data['body']
  elseif l:command == 'threads'
    let l:message = ''
    " TODO: sort these threads, and/or display them differently
    for l:thread in a:data['body']['threads']
      let message .= l:thread['id'].': '.l:thread['name']."\n"
    endfor
    echo l:message
  else
    echomsg 'Command succeeded: '.l:command
  endif
endfunction

function! s:handle_event(data) abort
  " echomsg 'Received event: '.a:data['event']
  if a:data['event'] == 'initialized'
    if bufexists(s:output_buffer)
      " Clear out the existing output window if there is one.
      call deletebufline(s:output_buffer, 1, '$')
    else
      call s:open_output_window()
    endif
  elseif a:data['event'] == 'output'
    " Since we're appending a new line, trim off any existing final newline
    " character, otherwise each line ends with ^@
    let l:output = substitute(a:data['body']['output'], '\n$', '', '')
    call appendbufline(s:output_buffer, '$', l:output)
  endif
endfunction

function! s:handle_reverse_request(data) abort
  if a:data['command'] == 'runInTerminal'
    echomsg 'Received request to run this in a terminal: '.join(a:data['args'], ' ')
    " run this in a terminal
  endif
endfunction

function! s:handle_stderr(job_id, data, event_type) abort
  echomsg 'stderr: '.join(a:data, "\n")
endfunction

function! s:handle_exit(job_id, data, event_type) abort
  echomsg 'exiting'
endfunction

function! s:send_message(body) abort
  let l:encoded_body = json_encode(a:body)
  let l:content_length = strlen(l:encoded_body)
  call dap#async#job#send(s:job_id, "Content-Length: ".l:content_length."\r\n\r\n".l:encoded_body)
endfunction

function! s:send_request(command, arguments)
  let l:request = {
        \ 'seq': s:seq,
        \ 'type': 'request',
        \ 'command': a:command,
        \ }
  
  if !empty(a:arguments)
    let l:request['arguments'] = a:arguments
  endif

  let s:seq = s:seq+1
  call s:send_message(l:request)
endfunction

function! s:initialize() abort
  " TODO: support other arguments
  call s:send_request('initialize', {'adapterID': 'vim-dap'})
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

function! dap#get_job_id() abort
  return s:job_id
endfunction
