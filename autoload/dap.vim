" TODO: ensure that a tmux session is running, and/or support internal
" terminals
"
" TODO: clean up temp files before and/or after?

if !has('nvim') && !has('channel')
  echoerr 'vim-dap: Neovim or Vim with channel support is required'
  finish
endif

if !exists('g:dap_initialized')
  let s:debug_adapter_job = 0
  let s:debug_console_socket = -1
  let s:seq = 1
  let s:last_buffer = -1
  let s:run_args = []
  let s:restarting = v:null
  let s:capabilities = {}
  let s:response_handlers = {}  " unused really, but left here because it may end up being useful
  let s:configuration_done_guard = {}
  let s:stopped_thread = -1
  let s:stopped_stack_frame_id = -1
  let s:adapter_running = v:false
  let s:debuggee_running = v:false
  let g:dap_use_tmux = 1
  let g:dap_initialized = v:true
  let s:plugin_home = fnamemodify(expand('<sfile>:p'), ':h:h')
  let s:tailing_output = v:false
  let s:temp = '/tmp/vim-dap'
  call delete(s:temp, 'rf')
  call mkdir(s:temp, 'p')
  let s:quickfix_file = tempname()
  let s:output_file = s:temp.'/output'
  let s:console_buffer = ''

  call sign_define('dap-breakpoint', {'text': 'B'})
  call sign_define('dap-stopped', {'text': '>'})
endif

function! dap#run(buffer, ...) abort
  let s:last_buffer = bufnr(a:buffer)
  let s:run_args = a:000
  call dap#run_last()
endfunction

function! dap#run_last() abort
  if s:last_buffer == -1
    throw 'No previous buffer to run.'
  endif
  if str2nr(system('tmux display-message -p "#{window_panes}"')) == 1
    call s:split_panes()
  endif
  if s:tailing_output
    call s:tmux_reset(s:output_pane)
    let s:tailing_output = v:false
  endif
  " It's possible that some debuggers will not need to restart their adapter
  " if it's already running, but Java seems to require restarting the whole
  " thing, so at least for now we'll stick with the nuclear option.
  if s:debuggee_running || s:adapter_running
    call dap#restart(s:last_buffer)
  else
    echomsg 'Starting debugger'
    call dap#lang#run(s:last_buffer, s:run_args)
  endif
endfunction

function! dap#restart(buffer) abort
  echomsg 'Restarting debugger'
  if get(s:capabilities, 'supportsRestartRequest', v:false)
    call dap#log_error('Fancy restart requested, but not implemented yet.')
  else
    let s:restarting = a:buffer
    call dap#disconnect(v:true)  " TODO: ensure that this restarts the debuggee
  endif
endfunction

function! dap#capabilities() abort
  return s:capabilities
endfunction

function! dap#spawn(args) abort
  if s:is_open_socket_or_job(s:debug_adapter_job)
    call dap#log_error('Already connected.')
    return
  endif
  let s:debug_adapter_job = dap#io#jobstart(a:args, function('s:handle_stdout'), function('s:handle_stderr'), function('s:handle_exit'))
  call s:initialize()
endfunction

function! dap#connect(port) abort
  if !executable('nc')
    throw 'command "nc" not found! please install netcat and try again'
  endif
  if s:is_open_socket_or_job(s:debug_adapter_job)
    call dap#log_error('Already connected.')
    return
  endif
  call dap#log('Connecting to debugger on port '.a:port)
  call dap#spawn(['nc', 'localhost', a:port])
endfunction

function! dap#disconnect(restart) abort
  if !s:is_open_socket_or_job(s:debug_adapter_job)
    call dap#log_error('No connection to disconnect from.')
    return
  endif
  call dap#send_message(dap#build_request('disconnect', {'restart': a:restart}))
endfunction

function! dap#is_connected() 
  return s:is_open_socket_or_job(s:debug_adapter_job)
endfunction

function! dap#adapter_running()
  return s:adapter_running
endfunction

function! dap#debuggee_running()
  return s:debuggee_running
endfunction

function! dap#get_capabilities() abort
  if !s:is_open_socket_or_job(s:debug_adapter_job)
    call dap#log_error('No debugger session running.')
    return v:null
  endif
  return s:capabilities
endfunction

" NOTE: In order to run JUnit, you need to specify a mainClass of
" org.junit.runner.JUnitCore along with an array of classpaths.
function! dap#launch(arguments) abort
  if !s:is_open_socket_or_job(s:debug_adapter_job)
    call dap#log_error('No debug session running.')
    return
  endif
  call dap#send_message(dap#build_request('launch', a:arguments))
endfunction

function! dap#threads() abort
  call dap#send_message(dap#build_request('threads', v:null))
endfunction

function! dap#continue(thread_id) abort
  " call s:set_all_breakpoints()
  call sign_unplace('dap-stopped-group')
  call dap#send_message(dap#build_request('continue', {'threadId': a:thread_id}))
endfunction

function! dap#continue_stopped() abort
  if s:stopped_thread == -1
    call dap#log_error('No stopped thread.')
    return
  endif
  call dap#continue(s:stopped_thread)
  let s:stopped_thread = -1
  let s:stopped_stack_frame_id = -1
endfunction

function! dap#next(thread_id) abort
  call sign_unplace('dap-stopped-group')
  call dap#send_message(dap#build_request('next', {'threadId': a:thread_id}))
endfunction

function! dap#next_stopped() abort
  if s:stopped_thread == -1
    call dap#log_error('No stopped thread.')
    return
  endif
  call dap#next(s:stopped_thread)
endfunction

function! dap#step_in(thread_id) abort
  " TODO: support step-in targets
  call sign_unplace('dap-stopped-group')
  call dap#send_message(dap#build_request('stepIn', {'threadId': a:thread_id}))
endfunction

function! dap#step_in_stopped() abort
  if s:stopped_thread == -1
    call dap#log_error('No stopped thread.')
    return
  endif
  call dap#step_in(s:stopped_thread)
endfunction

function! dap#step_out(thread_id) abort
  call sign_unplace('dap-stopped-group')
  call dap#send_message(dap#build_request('stepOut', {'threadId': a:thread_id}))
endfunction

function! dap#step_out_stopped() abort
  if s:stopped_thread == -1
    call dap#log_error('No stopped thread.')
    return
  endif
  call dap#step_out(s:stopped_thread)
endfunction

function! dap#terminate(restart) abort
  if s:adapter_running
    call s:quit_console()
  endif
  call dap#send_message(dap#build_request('terminate', {'restart': a:restart}))
endfunction

function! dap#send_message(body) abort
  let l:encoded_body = json_encode(a:body)
  let l:content_length = strlen(l:encoded_body)
  let l:message = "Content-Length: ".l:content_length."\r\n\r\n".l:encoded_body
  call dap#io#send(s:debug_adapter_job, l:message)
endfunction

function! dap#build_request(command, arguments) abort
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

function! dap#list_breakpoints() abort
  let l:list = []
  for [l:bufnr, l:lines] in items(s:get_breakpoints())
    for l:lnum in l:lines
      call add(l:list, {'bufnr': l:bufnr, 'lnum': l:lnum})
    endfor
  endfor

  call setloclist(0, l:list)
  lopen
endfunction

function! dap#tail_output() abort
  call writefile([], '/tmp/vim-dap.output')
  call s:tmux_send_keys(s:output_pane, ['"tail -f '.s:output_file.'"', 'Enter'])
endfunction

function! dap#get_job() abort
  return s:debug_adapter_job
endfunction

function! dap#get_console_buffer() abort
  return s:console_buffer
endfunction

function! dap#write_result(data) abort
  call dap#log('Evaluation result: '.a:data)
  call s:send_to_console('!', a:data)
endfunction

function! dap#write_completion(data) abort
  call s:send_to_console('?', a:data)
endfunction

function! dap#toggle_breakpoint(bufexpr, line) abort
  if s:debuggee_running && !dap#lang#supports_dynamic_breakpoints(s:last_buffer)
    throw 'Cannot set breakpoint while program is running.'
  endif
  let l:buffer = bufnr(a:bufexpr)
  let l:line = line(a:line)
  let l:found = v:false

  let l:existing = sign_getplaced(l:buffer, {'group': 'dap-breakpoint-group', 'lnum': l:line})[0]['signs']
  if empty(l:existing)
    call sign_place(0, 'dap-breakpoint-group', 'dap-breakpoint', l:buffer, {'lnum': l:line, 'priority': 98})
  else
    call sign_unplace('dap-breakpoint-group', {'buffer': l:buffer, 'id': l:existing[0]['id']})
  endif
endfunction

function! dap#clear_breakpoints() abort
  call sign_unplace('dap-breakpoint-group')
endfunction

function! dap#evaluate(...) abort
  if a:0 == 0
    call dap#evaluate(input('expression: '))
    return
  endif
  let l:body = {'expression': a:1}
  if s:stopped_stack_frame_id != -1
    let l:body['frameId'] = s:stopped_stack_frame_id
  endif
  call dap#send_message(dap#build_request('evaluate', l:body))
endfunction

function! dap#completions(text, column) abort
  let l:body = {'text': a:text, 'column': a:column}
  if s:stopped_stack_frame_id != -1
    let l:body['frameId'] = s:stopped_stack_frame_id
  endif
  call dap#send_message(dap#build_request('completions', l:body))
endfunction

function! dap#variables(ref) abort
  let l:body = {'variablesReference': a:ref}
  call dap#send_message(dap#build_request('variables', l:body))
endfunction

function! dap#log(msg) abort
  " TODO: make this configurable?
  let l:logfile = s:temp.'/log'
  if type(a:msg) == v:t_list
    call writefile(a:msg, l:logfile, 'a')
  elseif type(a:msg) == v:t_string
    call writefile([a:msg], l:logfile, 'a')
  else
    call dap#log_error('dap#log: unexpected message type: '.type(a:msg))
  endif
endfunction

function! dap#log_warning(msg) abort
  call dap#log('[WARN] '.a:msg)
  echohl WarningMsg | echomsg a:msg | echohl None
endfunction

function! dap#log_error(msg) abort
  call dap#log('[ERROR] '.a:msg)
  echohl ErrorMsg | echomsg a:msg | echohl None
endfunction

function! dap#clear_quickfix() abort
  call delete(s:quickfix_file)
  call setqflist([])
endfunction

function! dap#get_quickfix_file() abort
  return s:quickfix_file
endfunction

function! dap#open_quickfix() abort
  if filereadable(s:quickfix_file)
    execute 'cfile! '.s:quickfix_file
  endif
endfunction

function! s:reset()
  let s:debug_adapter_job = 0
  let s:seq = 1
endfunction

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

function! s:handle_stdout(data) abort
  let s:message_buffer .= s:string(a:data, "\n")

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

  " Handle failure cases first.
  if !a:data['success']
    if l:command == 'initialize'
      call dap#log_error('Initialization failed')
      call s:reset()
    elseif l:command == 'evaluate'
      if has_key(a:data, 'body') && has_key(a:data['body'], 'error')
        let l:error = a:data['body']['error']
        call dap#log('Evaluation failed: '.json_encode(l:error))
        " TODO: respect showUser?
        let l:format = l:error['format']
        let l:variables = get(l:error, 'variables', {})
        call dap#write_result(dap#util#format_string(l:format, l:variables))
      else
        call dap#log_error('Evaluation failed: '.a:data['message'])
        call dap#write_result(a:data['message'])
    endif
    elseif l:command == 'completions'
      call dap#write_completion(a:data['message'])
    else
      if has_key(a:data, 'body') && has_key(a:data['body'], 'error')
        let l:error = a:data['body']['error']
        let l:format = l:error['format']
        let l:variables = get(l:error, 'variables', {})
        call dap#log_error('Command failed: '.l:command.': '.dap#util#format_string(l:format, l:variables))
      else
        call dap#log_error('Command failed: '.l:command.': '.a:data['message'])
      endif
    endif
    return
  endif

  " At this point, we know the request succeeded.
  if l:command == 'initialize'
    call dap#log('Initialization successful')
    let s:capabilities = a:data['body']
    call s:handle_initialize_response()
  elseif l:command == 'configurationDone'
    let s:debuggee_running = v:true
  elseif l:command == 'launch'
    call s:set_all_breakpoints()
  elseif l:command == 'disconnect'
    let s:adapter_running = v:false
    call dap#io#jobstop(s:debug_adapter_job)
    call s:reset()
    if s:restarting != v:null
      call dap#run(s:restarting)
      let s:restarting = v:null
    endif
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
      call dap#send_message(dap#build_request('configurationDone', {}))
    endif
    " TODO: it would be nice to remove unverified breakpoints, but they don't
    " seem to include source information, so we can't really do anything about
    " it.
  elseif l:command == 'evaluate'
    call dap#write_result(a:data['body']['result'])
  elseif l:command == 'scopes'
    call dap#scopes#response(a:data)
  elseif l:command == 'completions'
    let l:completion_items = []
    if has_key(a:data, 'body') && has_key(a:data['body'], 'targets')
      let l:completion_items = a:data['body']['targets']
    endif
    call dap#write_completion(json_encode(l:completion_items))
  elseif l:command == 'variables'
    " A scopes request automatically retrieves its variables, so if this
    " request was part of a scope request, handle it accordingly.
    if dap#scopes#waiting_for(l:request_seq)
      call dap#scopes#variables_response(a:data)
    endif
  else
    echomsg 'Command succeeded: '.l:command
  endif
endfunction

function! s:handle_initialize_response() abort
  call dap#lang#initialized(s:last_buffer, s:run_args)

  call s:run_debug_console()
endfunction

function! s:handle_initialized_event() abort
  call sign_unplace('dap-stopped-group')
  let s:adapter_running = v:true
endfunction

function! s:handle_event(data) abort
  call dap#log('Received event: '.a:data['event'])
  if a:data['event'] == 'initialized'
    call s:handle_initialized_event()
  elseif a:data['event'] == 'output'
    call s:handle_event_output(a:data['body'])
  elseif a:data['event'] == 'stopped'
    call s:handle_event_stopped(a:data['body'])
  elseif a:data['event'] == 'breakpoint'
    call s:handle_event_breakpoint(a:data['body'])
  elseif a:data['event'] == 'terminated'
    echomsg 'Adapter terminated.'
    let s:adapter_running = v:false
    let s:debuggee_running = v:false
    call dap#io#jobstop(s:debug_adapter_job)
    doautocmd User dap_adapter_terminated
    call s:reset()
    call s:quit_console()
  elseif a:data['event'] == 'exited'
    let s:debuggee_running = v:false
    call s:quit_console()
    let l:exit_code = a:data['body']['exitCode']
    if l:exit_code == v:null
      echomsg 'Process exited'
    else
      echomsg 'Process exited with exit code '.a:data['body']['exitCode']
    endif
  endif
endfunction

function! s:handle_event_output(body) abort
  if !s:tailing_output
    call dap#tail_output()
    let s:tailing_output = v:true
  endif
  let l:category = get(a:body, 'category', 'console')
  if l:category == 'console' || l:category == 'stdout' || l:category == 'stderr'
    "for l:line in split(a:body['output'], '\n')
    "  let l:command = 'tmux run-shell -t '.s:output_pane.' "echo '.shellescape(l:line).'"'
    "  call system(l:command)
    "endfor
    let l:lines = split(a:body['output'], '\n')
    call writefile(l:lines, s:output_file, 'a')
  endif
endfunction

function! s:handle_event_stopped(body) abort
  if has_key(a:body, 'threadId')
    let s:stopped_thread = a:body['threadId']
    let l:request = dap#build_request('stackTrace', {
          \ 'threadId': s:stopped_thread,
          \ 'levels': 1,
          \ 'format': {'line': v:true},
          \ })
    call s:add_response_handler(l:request, function('s:handle_event_stopped_stacktrace'))
    call dap#send_message(l:request)
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
    call dap#log_warning('Cannot jump to stopped location, stack trace is empty.')
    return
  endif

  let l:frame = l:stackframes[0]
  let s:stopped_stack_frame_id = l:frame['id']
  let l:path = l:frame['source']['path']
  let l:line = l:frame['line']

  exec ':keepalt edit +'.l:line.' '.l:path
  call s:send_to_console('@', fnamemodify(l:path, ':t').':'.l:line)
  call sign_place(1, 'dap-stopped-group', 'dap-stopped', '%', {'lnum': l:line, 'priority': 99})
endfunction

function! s:handle_event_breakpoint(body) abort
  let l:reason = a:body['reason']
  echo 'breakpoint event, reason: '.l:reason
  if l:reason == 'new'
  elseif l:reason == 'removed'
  elseif l:reason == 'changed'
  else
    call dap#log_error('Unknown breakpoint reason: '.l:reason)
  endif
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
      let l:command = 'clear && '.l:env.' '.l:command
    endif

    " let l:script = '/tmp/vim-dap-debug.sh'
    " call writefile(['exec '.l:command], l:script)
    if g:dap_use_tmux
      call s:tmux_reset(s:output_pane)
      " call s:run_debuggee('sh '.l:script)
      call s:run_debuggee(l:command)
    else
      " TODO: terminals need to be closed after they exit
      " execute 'terminal '.l:command
      execute 'split | terminal clear; sh '.l:script
    endif
    " let l:pid = trim(system('pgrep -f "sh '.l:script.'"'))
    let l:pid = trim(system('pgrep -f "'.l:command.'"'))
    call dap#send_message(s:build_response(a:data, v:true, {'processId': l:pid}))
  endif
endfunction

function! s:handle_stderr(data) abort
  " for l:line in a:data
  "   call dap#log('stderr: '.l:line)
  " endfor
endfunction

function! s:handle_exit(exit_code) abort
  call dap#log('job exited with exit code '.a:exit_code)
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
  call dap#log('Initializing...')
  call dap#send_message(dap#build_request('initialize', {
        \ 'adapterID': 'vim-dap',
        \ 'pathFormat': 'path',
        \ 'linesStartAt1': v:true,
        \ 'columnsStartAt1': v:true,
        \ 'supportsRunInTerminalRequest': v:true,
        \ }))
endfunction

let s:output_pane = 1
let s:console_pane = 2

function! s:split_panes() abort
  " TODO: make pane sizes configurable
  call system('tmux split-pane -p 40 -h')
  call system('tmux split-pane -v')
  call system('tmux select-pane -t 0')
endfunction

function! s:buffer_path(buffer) abort
  " prepend file:// if we need uris
  return expand('#'.a:buffer.':p')
endfunction

function! s:get_breakpoints() abort
  let l:breakpoints = {}
  for l:buffer in getbufinfo()
    let l:bufnr = l:buffer['bufnr']
    let l:signs = sign_getplaced(l:bufnr, {'group': 'dap-breakpoint-group'})
    if empty(l:signs)
      continue
    endif
    let l:breakpoints[l:bufnr] = []
    for l:item in l:signs
      for l:sign in l:item['signs']
        call add(l:breakpoints[l:bufnr], l:sign['lnum'])
      endfor
    endfor
  endfor
  return l:breakpoints
endfunction

function! s:set_all_breakpoints() abort
  if !s:is_open_socket_or_job(s:debug_adapter_job)
    call dap#log_error('No debugger session running.')
    return
  endif

  " In order to ensure that all setBreakpoints requests have returned before
  " configurationDone is sent, we build the requests first, add all of their
  " seq values to the guard, and then send them all at once. The response
  " listeners will remove each one from the guard, and when it's empty,
  " configurationDone will be sent.

  let l:requests = []
  echomsg 'Setting all breakpoints'
  for [l:bufnr, l:lines] in items(s:get_breakpoints())
    echomsg 'Setting breakpoints for buffer '.l:bufnr
    let l:breakpoints = []
    for l:lnum in l:lines
      call add(l:breakpoints, {'line': l:lnum})
    endfor
    let l:path = s:buffer_path(l:bufnr)
    if !empty(l:path)
      let l:request = dap#build_request('setBreakpoints', {
          \   'source': { 'path': l:path },
          \   'breakpoints': l:breakpoints,
          \ })
      " TODO: use closure functions instead?
      let s:configuration_done_guard[l:request['seq']] = v:true
      call add(l:requests, l:request)
    endif
  endfor

  for l:request in l:requests
    call dap#send_message(l:request)
  endfor
endfunction

function! s:run_debug_console() abort
  if s:is_open_socket_or_job(s:debug_console_socket)
    call s:quit_console()
    sleep 1
  endif
  if !executable(s:plugin_home.'/bin/console') || getfsize(s:plugin_home.'/bin/console') == 0
    if has('unix')
      call system(s:plugin_home.'/install-console.sh')
    else
      throw 'Console is either not executable or empty, did you install it correctly?'
    endif
  endif
  let l:addrfile = s:temp.'/console-addr'
  let l:logfile = s:temp.'/console-log'
  let l:historyfile = s:temp.'/console-history'
  call delete(l:addrfile)
  let l:command = './bin/console -addrfile '.l:addrfile.' -log '.l:logfile.' -history '.l:historyfile
  call s:tmux_send_keys(s:console_pane, ['"clear; (cd '.s:plugin_home.' && '.l:command.')"', 'Enter'])
  let s:debug_console_socket = -1
  call s:wait_for_file(l:addrfile)
  let s:debug_console_socket = dap#io#sockconnect(readfile(l:addrfile)[0], function('s:handle_debug_console_stdout'))
endfunction

function! s:wait_for_file(path) abort
  let l:try = 0
  while !filereadable(a:path)
    let l:try = l:try+1
    if l:try > 10
      throw 'File never appeared: '.a:path
    endif
    sleep 100m
  endwhile
endfunction

function! s:run_debuggee(command) abort
  let s:output_mode = 'terminal'
  call s:tmux_send_keys(s:output_pane, ['"'.a:command.'"', 'Enter'])
endfunction

function! s:handle_debug_console_stdout(data) abort
  let s:console_buffer .= s:string(a:data, '')
  let l:len_delim = stridx(s:console_buffer, '#')
  if l:len_delim == -1
    return
  endif
  let l:len = str2nr(s:console_buffer[:l:len_delim-1])
  let l:rest = s:console_buffer[l:len_delim+1:]
  if len(l:rest) < l:len
    return
  endif

  let l:expr = l:rest[:l:len]
  let s:console_buffer = l:rest[l:len+1:]

  let l:action = l:expr[0]
  let l:text = l:expr[1:]

  if empty(l:text)
    return
  endif

  if l:action == ':'
    call s:console_command(l:text)
  elseif l:action == '!'
    call dap#log('evaluating: '.l:text)
    call dap#evaluate(l:text)
  elseif l:action == '?'
    let l:cursor_delim = stridx(l:text, '|')
    let l:cursor_pos = str2nr(l:text[:l:cursor_delim-1])
    let l:line = l:text[l:cursor_delim+1:]
    call dap#completions(l:line, l:cursor_pos)
  endif
endfunction

function! s:console_command(command) abort
  if a:command == 'continue'
    call dap#continue_stopped()
  elseif a:command == 'scopes'
    call dap#scopes#request(s:stopped_stack_frame_id)
  elseif a:command == 'next'
    call dap#next_stopped()
  endif
endfunction

function! s:send_to_console(action, data) abort
  call dap#io#send(s:debug_console_socket, a:action.len(a:data).':'.a:data)
endfunction

function! s:quit_console() abort
  if s:is_open_socket_or_job(s:debug_console_socket)
    call dap#io#sockclose(s:debug_console_socket)
    let s:debug_console_socket = -1
  endif
endfunction

function! s:tmux_send_keys(pane, keys) abort
  call system('tmux send-keys -t '.a:pane.' '.join(a:keys, ' '))
endfunction

function! s:tmux_reset(pane) abort
  call system('tmux send-keys -t '.a:pane.' C-c')
  call system('tmux send-keys -t '.a:pane.' clear Enter')
endfunction

function! s:is_open_socket_or_job(value)
  if type(a:value) == v:t_number
    return a:value > 0
  endif
  if has('channel') && type(a:value) == v:t_channel
    return v:true
  endif
  if has('job') && type(a:value) == v:t_job
    return v:true
  endif
  return v:false
endfunction

" Neovim invokes callbacks with lists of strings, and Vim invokes them
" with just strings. This method normalizes the two results into a string,
" joined by sep if needed.
function! s:string(value, sep) abort
  if type(a:value) == v:t_list
    return trim(join(a:value, a:sep))
  elseif type(a:value) == v:t_string
    return trim(a:value)
  else
    throw 'unsupported type passed to s:string(): '.type(a:value)
  endif
endfunction

" vim: set expandtab shiftwidth=2 tabstop=2:
