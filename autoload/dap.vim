if !exists('g:dap_initialized')
  let s:job_id = -1
  let s:seq = 1
  let s:last_buffer = -1
  let s:capabilities = {}
  let s:response_handlers = {}  " unused really, but left here because it may end up being useful
  let s:configuration_done_guard = {}
  let s:stopped_thread = -1
  let s:stopped_stack_frame_id = -1
  let s:show_var = ''
  let s:launch_args = v:null
  let s:running = v:false
  let s:scopes = []
  let g:dap_use_vimux = exists('g:loaded_vimux') && g:loaded_vimux
  let g:dap_initialized = v:true

  call sign_define('dap-breakpoint', {'text': '🛑'})
  call sign_define('dap-stopped', {'text': '⏸'})
endif

function! dap#run(buffer) abort
  echomsg 'Running '.a:buffer
  let s:last_buffer = bufnr(a:buffer)
  if s:running
    if s:capabilities['supportsRestartRequest']
      echoerr 'Fancy restart requested, but not implemented yet.'
    endif
    call dap#terminate(v:true)  " TODO: ensure that this restarts the debuggee
  else
    if exists('g:LanguageClient_loaded') && g:LanguageClient_loaded
      call dap#language_client#run(a:buffer)
    else
      echoerr 'No supported language client extension installed.'
    endif
  endif
endfunction

function! dap#run_last() abort
  if s:last_buffer == -1
    throw 'No previous buffer to run.'
  endif
  call dap#run(s:last_buffer)
endfunction

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
  if s:job_id == -1
    call dap#log_error('No connection to disconnect from.')
    return
  endif
  call s:send_message(s:build_request('disconnect', {}))
endfunction

function! dap#get_capabilities() abort
  if s:job_id == -1
    call dap#log_error('No debugger session running.')
    return v:null
  endif
  return s:capabilities
endfunction

" NOTE: In order to run JUnit, you need to specify a mainClass of
" org.junit.runner.JUnitCore along with an array of classpaths.
function! dap#launch(arguments) abort
  if s:job_id == -1
    echoerr 'No debug session running.'
    return
  endif
  call s:send_message(s:build_request('launch', a:arguments))
endfunction

function! dap#threads() abort
  call s:send_message(s:build_request('threads', v:null))
endfunction

function! dap#continue(thread_id) abort
  call s:set_all_breakpoints()
  call sign_unplace('dap-stopped-group')
  call s:send_message(s:build_request('continue', {'threadId': a:thread_id}))
endfunction

function! dap#continue_stopped() abort
  if s:stopped_thread == -1
    echoerr 'No stopped thread.'
    return
  endif
  call dap#continue(s:stopped_thread)
  let s:stopped_thread = -1
  let s:stopped_stack_frame_id = -1
endfunction

function! dap#next(thread_id) abort
  call sign_unplace('dap-stopped-group')
  call s:send_message(s:build_request('next', {'threadId': a:thread_id}))
endfunction

function! dap#next_stopped() abort
  if s:stopped_thread == -1
    echoerr 'No stopped thread.'
    return
  endif
  call dap#next(s:stopped_thread)
endfunction

function! dap#step_in(thread_id) abort
  " TODO: support step-in targets
  call sign_unplace('dap-stopped-group')
  call s:send_message(s:build_request('stepIn', {'threadId': a:thread_id}))
endfunction

function! dap#step_in_stopped() abort
  if s:stopped_thread == -1
    echoerr 'No stopped thread.'
    return
  endif
  call dap#step_in(s:stopped_thread)
endfunction

function! dap#step_out(thread_id) abort
  call sign_unplace('dap-stopped-group')
  call s:send_message(s:build_request('stepOut', {'threadId': a:thread_id}))
endfunction

function! dap#step_out_stopped() abort
  if s:stopped_thread == -1
    echoerr 'No stopped thread.'
    return
  endif
  call dap#step_out(s:stopped_thread)
endfunction

function! dap#terminate(restart) abort
  if s:running
    call VimuxSendKeys('C-c')
  endif
  call s:send_message(s:build_request('terminate', {'restart': a:restart}))
endfunction

function! s:buffer_path(buffer) abort
  " prepend file:// if we need uris
  return expand('#'.a:buffer.':p')
endfunction

function! dap#toggle_breakpoint(bufexpr, line) abort
  let l:buffer = bufnr(a:bufexpr)
  let l:line = line(a:line)
  let l:found = v:false

  let l:existing = sign_getplaced(l:buffer, {'group': 'dap-breakpoint-group', 'lnum': l:line})[0]['signs']
  if empty(l:existing)
    call sign_place(0, 'dap-breakpoint-group', 'dap-breakpoint', l:buffer, {'lnum': l:line})
  else
    call sign_unplace('dap-breakpoint-group', {'buffer': l:buffer, 'lnum': l:line})
  endif
endfunction

function! dap#clear_breakpoints() abort
  call sign_unplace('dap-breakpoint-group')
endfunction

function! dap#evaluate(expression) abort
  let l:body = {'expression': a:expression}
  if s:stopped_stack_frame_id != -1
    let l:body['frameId'] = s:stopped_stack_frame_id
  endif
  call s:send_message(s:build_request('evaluate', l:body))
endfunction

function! dap#scopes(frame_id) abort
  let l:body = {'frameId': a:frame_id}
  call s:send_message(s:build_request('scopes', l:body))
endfunction

function! dap#echo_scopes() abort
  let l:scope_names = []
  for l:scope in s:scopes
    call add(l:scope_names, l:scope['name'])
  endfor
  echomsg 'Available scopes: '.join(l:scope_names, ', ') | echo ''
endfunction

function! dap#show_scope(name) abort
  let s:show_var = ''
  call s:show_scope(a:name)
endfunction

function! dap#show_scope_var(name, var) abort
  let s:show_var = a:var
  call s:show_scope(a:name)
endfunction

function! s:show_scope(name) abort
  for l:scope in s:scopes
    if l:scope['name'] == a:name
      call dap#variables(l:scope['variablesReference'])
      return
    endif
  endfor
  echoerr 'No scope found for name: '.a:name
endfunction

function! dap#variables(ref) abort
  let l:body = {'variablesReference': a:ref}
  call s:send_message(s:build_request('variables', l:body))
endfunction

" TODO: don't echo log messages
function! dap#log(msg) abort
  echo a:msg
endfunction

function! dap#log_error(msg) abort
  echomsg a:msg
endfunction

function! s:reset()
  let s:job_id = -1
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

    let s:message_buffer = l:message['rest']
    
    let l:body = json_decode(l:message['content'])
    if type(l:body) != v:t_dict
      call dap#log_error('Bad response, not a dict')
      return
    endif

    let g:dap_last_message = l:body

    let l:message_type = l:body['type']
    if l:message_type == 'response'
      call s:handle_response(l:body)
    elseif l:message_type == 'event'
      call s:handle_event(l:body)
    elseif l:message_type == 'request'
      call s:handle_reverse_request(l:body)
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
    call s:handle_initialized()
  elseif l:command == 'launch'
    call s:set_all_breakpoints()
  elseif l:command == 'disconnect'
    call dap#async#job#stop(s:job_id)
    call s:reset()
    return
  endif

  let l:request_seq = a:data['request_seq']
  if has_key(s:response_handlers, l:request_seq)
    call s:response_handlers[l:request_seq](a:data)
    call remove(s:response_handlers, l:request_seq)
    return
  endif

  if l:command == 'threads'
    let l:message = ''
    " TODO: sort these threads, and/or display them differently
    for l:thread in a:data['body']['threads']
      let message .= l:thread['id'].': '.l:thread['name']."\n"
    endfor
    echo l:message
  elseif l:command == 'setBreakpoints'
    unlet s:configuration_done_guard[l:request_seq]
    if empty(s:configuration_done_guard)
      call s:send_message(s:build_request('configurationDone', {}))
    endif
    " TODO: it would be nice to remove unverified breakpoints, but they don't
    " seem to include source information, so we can't really do anything about
    " it.
  elseif l:command == 'evaluate'
    echomsg 'Evaluation result: '.a:data['body']['result']
  elseif l:command == 'scopes'
    let s:scopes = a:data['body']['scopes']
  elseif l:command == 'variables'
    call s:handle_variables_response(a:data['body']['variables'])
  else
    echomsg 'Command succeeded: '.l:command
  endif
endfunction

function! s:handle_initialized() abort
  " This method is written under the assumption that what needs to happen
  " after initialization varies by language. For example, java needs to launch
  " a VM before setting breakpoints, but other languages may need things done
  " in a different order.
  if &filetype == 'java'
    if exists('g:LanguageClient_loaded') && g:LanguageClient_loaded
      call dap#language_client#launch(s:last_buffer)
    else
      echoerr 'No supported language client extension installed.'
    endif
  endif
endfunction

function! s:handle_variables_response(variables) abort
  if empty(s:show_var)
    let l:variable_names = []
    for l:variable in a:variables
      call add(l:variable_names, l:variable['name'])
    endfor
    echomsg 'Variables in scope: '.join(l:variable_names, ', ')
  else
    for l:variable in a:variables
      if l:variable['name'] == s:show_var
        echomsg l:variable['value']
        break
      endif
    endfor
  endif
endfunction

function! s:handle_event(data) abort
  if a:data['event'] == 'initialized'
    call sign_unplace('dap-stopped-group')
  elseif a:data['event'] == 'process'
    let s:running = v:true
  elseif a:data['event'] == 'output'
    echoerr 'The debuggee should be running in a terminal, no output event is expected.'
  elseif a:data['event'] == 'stopped'
    call s:handle_event_stopped(a:data['body'])
  elseif a:data['event'] == 'breakpoint'
    call s:handle_event_breakpoint(a:data['body'])
  elseif a:data['event'] == 'terminated'
    call dap#async#job#stop(s:job_id)
    call s:reset()
  elseif a:data['event'] == 'exited'
    call s:handle_event_exited(a:data['body']['exitCode'])
  endif
endfunction

function! s:handle_event_stopped(body) abort
  if has_key(a:body, 'threadId')
    let s:stopped_thread = a:body['threadId']
    let l:request = s:build_request('stackTrace', {
          \ 'threadId': s:stopped_thread,
          \ 'levels': 1,
          \ 'format': {'line': v:true},
          \ })
    call s:add_response_handler(l:request, function('s:handle_event_stopped_stacktrace'))
    call s:send_message(l:request)
  endif
  let l:reason = a:body['reason']
  if l:reason == 'breakpoint'
    echomsg 'Stopped at a breakpoint'
    if has_key(a:body, 'threadId')
    endif
  else
    if has_key(a:body, 'description')
      echomsg a:body['description']
    elseif has_key(a:body, 'text')
      echomsg a:body['text']
    else
      echomsg 'Stopped by '.l:reason
    endif
  endif
endfunction

function! s:handle_event_stopped_stacktrace(data) abort
  let l:stackframes = a:data['body']['stackFrames']
  if empty(l:stackframes)
    echoerr 'Cannot jump to stopped location, stack trace is empty.'
    return
  endif

  let l:frame = l:stackframes[0]
  let s:stopped_stack_frame_id = l:frame['id']
  let l:path = l:frame['source']['path']
  let l:line = l:frame['line']

  exec ':keepalt edit +'.l:line.' '.l:path
  call sign_place(1, 'dap-stopped-group', 'dap-stopped', '%', {'lnum': l:line, 'priority': 11})

  call dap#scopes(s:stopped_stack_frame_id)
endfunction

function! s:handle_event_breakpoint(body) abort
  let l:reason = a:body['reason']
  echo 'breakpoint event, reason: '.l:reason
  if l:reason == 'new'
  elseif l:reason == 'removed'
  elseif l:reason == 'changed'
  else
    echoerr 'unknown breakpoint reason: '.l:reason
  endif
endfunction

function! s:handle_event_exited(exit_code) abort
  let s:running = v:false
  echomsg 'Process exited with exit code '.a:exit_code
endfunction

function! s:handle_reverse_request(data) abort
  if a:data['command'] == 'runInTerminal'
    let l:request_args = a:data['arguments']
    " if has_key(l:request_args, 'kind')
    "   echomsg 'Requested terminal kind: '.l:args['kind']
    " endif
    " if has_key(l:request_args, 'title')
    "   echomsg 'Requested terminal title: '.l:args['title']
    " endif

    let l:command_args = l:request_args['args']
    call map(l:command_args, 'shellescape(v:val)')
    let l:command = join(l:command_args, ' ')

    if has_key(l:request_args, 'cwd') || has_key(l:request_args, 'env')
      let l:env = 'env'
      if has_key(l:request_args, 'cwd')
        let l:env .= ' --chdir='.shellescape(l:request_args['cwd'])
      endif
      if has_key(l:request_args, 'env')
        for [l:key, l:value] in items(l:request_args['env'])
          let l:env .= ' '.l:key.'='.shellescape(l:value)
        endfor
      endif
      let l:command = l:env.' '.l:command
    endif

    let l:script = '/tmp/vim-dap-debug.sh'
    call writefile(['exec '.l:command], l:script)
    " execute 'terminal '.l:command
    if g:dap_use_vimux
      call VimuxRunCommand('clear; sh '.l:script)
    else
      " TODO: terminals need to be closed after they exit
      execute 'split | terminal clear; sh '.l:script
    endif
    let l:pid = trim(system('pgrep -f "sh '.l:script.'"'))
    call s:send_message(s:build_response(a:data, v:true, {'processId': l:pid}))
  endif
endfunction

function! s:handle_stderr(job_id, data, event_type) abort
  " echomsg 'stderr: '.join(a:data, "\n")
endfunction

function! s:handle_exit(job_id, data, event_type) abort
  " no op
endfunction

function! s:send_message(body) abort
  let l:encoded_body = json_encode(a:body)
  let l:content_length = strlen(l:encoded_body)
  call dap#async#job#send(s:job_id, "Content-Length: ".l:content_length."\r\n\r\n".l:encoded_body)
endfunction

function! s:build_request(command, arguments) abort
  let l:request = {
        \ 'seq': s:seq,
        \ 'type': 'request',
        \ 'command': a:command,
        \ }
  
  if !empty(a:arguments)
    let l:request['arguments'] = a:arguments
  endif

  let s:seq = s:seq+1
  return l:request
endfunction

function! s:build_response(request, success, body) abort
  let l:response = {
        \ 'seq': s:seq,
        \ 'type': 'response',
        \ 'request_seq': a:request['seq'],
        \ 'command': a:request['command'],
        \ 'success': a:success,
        \ 'body': a:body,
        \ }
  
  let s:seq = s:seq+1
  return l:response
endfunction

function! s:add_response_handler(request, handler) abort
  let s:response_handlers[a:request['seq']] = a:handler
endfunction

function! s:initialize() abort
  " TODO: support other arguments?
  call s:send_message(s:build_request('initialize', {
        \ 'adapterID': 'vim-dap',
        \ 'pathFormat': 'path',
        \ 'linesStartAt1': v:true,
        \ 'columnsStartAt1': v:true,
        \ 'supportsRunInTerminalRequest': v:true,
        \ }))
endfunction

function! s:set_breakpoints(buffer, signs) abort
  if s:job_id == -1
    call dap#log_error('No debugger session running.')
    return
  endif
  let l:breakpoints = []
  for l:sign in a:signs
    call add(l:breakpoints, {'line': l:sign['lnum']})
  endfor
  let l:request = {
        \ 'seq': s:seq,
        \ 'type': 'request',
        \ 'command': 'setBreakpoints',
        \ 'arguments': {
        \   'source': { 'path': s:buffer_path(a:buffer) },
        \   'breakpoints': l:breakpoints},
        \ }
  let s:seq = s:seq+1

  call s:send_message(l:request)
endfunction

function! s:set_all_breakpoints() abort
  if s:job_id == -1
    call dap#log_error('No debugger session running.')
    return
  endif

  " In order to ensure that all setBreakpoints requests have returned before
  " configurationDone is sent, we build the requests first, add all of their
  " seq values to the guard, and then send them all at once. The response
  " listeners will remove each one from the guard, and when it's empty,
  " configurationDone will be sent.

  let l:requests = []
  for l:item in sign_getplaced('', {'group': 'dap-breakpoint-group'})
    let l:breakpoints = []
    for l:sign in l:item['signs']
      call add(l:breakpoints, {'line': l:sign['lnum']})
    endfor
    let l:request = s:build_request('setBreakpoints', {
        \   'source': { 'path': s:buffer_path(l:item['bufnr']) },
        \   'breakpoints': l:breakpoints,
        \ })
    " TODO: use closure functions instead?
    let s:configuration_done_guard[l:request['seq']] = v:true
    call add(l:requests, l:request)
  endfor

  for l:request in l:requests
    call s:send_message(l:request)
  endfor
endfunction

function! dap#get_job_id() abort
  return s:job_id
endfunction
