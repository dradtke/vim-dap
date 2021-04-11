let s:plugin_home = fnamemodify(expand('<sfile>:p'), ':h:h:h:h')
let s:current_buffer = v:null

let s:test_runner_main_class = v:null
let s:test_runner_args_builder = {mainclass -> mainclass}

function! dap#lang#java#launch(params) abort
  call dap#log('Port: '.dap#get_program_listener_port())
  call dap#log('(Before) Args: '.a:params['args'])
  let a:params['args'] = substitute(a:params['args'], '-port \d* ', '-port '.dap#get_program_listener_port().' ', '')
  call dap#log('(After) Args: '.a:params['args'])
  call dap#launch(a:params)
endfunction

function! dap#lang#java#run_test_class() abort
  call dap#run('%')
endfunction

function! s:run_test_item(buffer, test_item) abort
  " vscode.java.test.junit.argument
  function! s:junit_args_callback(data) closure
    if has_key(a:data, 'result')
      let g:junit_args_result = a:data['result']
        let l:junit_args = a:data['result']
        call dap#run(a:buffer, #{
              \ type: 'java',
              \ mainClass: l:junit_args['mainClass'],
              \ args: join(l:junit_args['programArguments']),
              \ vmArgs: join(l:junit_args['vmArguments']),
              \ classPaths: l:junit_args['classpath'],
              \ modulePaths: l:junit_args['modulepath'],
              \ cwd: l:junit_args['workingDirectory'],
              \ projectName: l:junit_args['projectName'],
              \ shortenCommandLine: 'jarmanifest',
              \ })
    elseif has_key(a:data, 'error')
      call dap#log_error('Call to vscode.java.test.junit.argument unexpected response.')
    endif
  endfunction

  let l:nameParts = split(a:test_item['fullName'], '#')
  let l:className = l:nameParts[0]
  let l:methodName = ''
  if len(l:nameParts) > 1
    let l:methodName = l:nameParts[1]
  endif

  let l:params = #{
        \ uri: 'file://'.getbufinfo(a:buffer)[0]['name'],
        \ fullName: l:className,
        \ testName: l:methodName,
        \ project: a:test_item['project'],
        \ scope: a:test_item['level'],
        \ testKind: a:test_item['kind'],
        \ start: a:test_item['location']['range']['start'],
        \ end: a:test_item['location']['range']['end'],
        \ }

  call dap#log('Params: '.json_encode(l:params))

  call dap#log('Calling vscode.java.test.junit.argument')
  call dap#lsp#execute_command(a:buffer, 'vscode.java.test.junit.argument', [json_encode(l:params)], function('s:junit_args_callback'))
endfunction

function! dap#lang#java#run_test_method() abort
  let l:buffer = bufnr('%')
  function! s:code_lens_callback(data) closure
    if has_key(a:data, 'result')
      let l:test_items = a:data['result']
      call filter(l:test_items, 'v:val["level"] == 4')
      call filter(l:test_items, 'v:val["location"]["range"]["start"]["line"] < '.line('.'))

      " sort by line number, descending
      function! s:test_items_sort(x, y)
        return a:y['location']['range']['start']['line'] - a:x['location']['range']['start']['line'] 
      endfunction

      call sort(l:test_items, function('s:test_items_sort'))

      if !empty(l:test_items)
        call s:run_test_item(l:buffer, l:test_items[0])
      endif
    elseif has_key(a:data, 'error')
      call dap#log_error('Call to vscode.java.test.search.codelens returned unexpected response.')
    endif
  endfunction

  let l:params = ['file://'.getbufinfo('%')[0]['name']]
  call dap#lsp#execute_command(l:buffer, 'vscode.java.test.search.codelens', l:params, function('s:code_lens_callback'))

  "let l:class_name = dap#lang#java#full_class_name('%')
  "let l:test_name = dap#lang#java#test_name()
  "call dap#run('%', l:class_name.'#'.l:test_name)
endfunction

function! dap#lang#java#set_test_runner_main_class(class)
  let s:test_runner_main_class = a:class
endfunction

function! dap#lang#java#lens(buffer)
  function! s:test_codelens_callback(data) closure
    " TODO: if run-focus was requested, look for item with type == 4 (method)
    " for run-buffer, look for item with type == 3 (class)
    let g:lens_result = a:data['result']
    for l:item in a:data['result']
      echomsg l:item['displayName']
    endfor
  endfunction
  let l:params = ['file://'.getbufinfo(a:buffer)[0]['name']]
  let l:method = 'vscode.java.test.search.codelens'
  call dap#log('Calling '.l:method)
  call dap#lsp#execute_command(a:buffer, l:method, l:params, function('s:test_codelens_callback'))
endfunction

" This function can be used to customize how arguments are passed to the test
" runner. It expects a function which itself takes one argument, the
" fully-qualified name of the class to run tests for, and should return a
" string which will be passed to the test runner as its arguments.
function! dap#lang#java#set_test_runner_args_builder(f)
  let s:test_runner_args_builder = a:f
endfunction

function! s:load_debug_settings(buffer, next) abort
  for l:path in ['.vim/launch.json', '.vscode/launch.json']
    if filereadable(l:path)
      function! s:update_debug_settings_callback(data) closure
        if has_key(a:data, 'result')
          call dap#log('Debug settings updated')
          call dap#log(a:data['result'])
        elseif has_key(a:data, 'error')
          call dap#log_warning('Failed to update settings, error message to follow:')
          call dap#log_warning(a:data['error']['message'])
        else
          call dap#log_error('Call to vscode.java.updateDebugSettings returned unexpected response.')
        endif
        call a:next()
      endfunction

      call dap#log('Loading debug settings from '.l:path)
      let l:settings = json_decode(join(readfile(l:path), ''))
      " For some reason, a NullPointerException often gets thrown if logLevel
      " is not defined explicitly, so default it to warn if not defined
      if !has_key(l:settings, 'logLevel')
        let l:settings['logLevel'] = 'warn'
      endif
      call dap#lsp#execute_command(a:buffer, 'vscode.java.updateDebugSettings', [json_encode(l:settings)], function('s:update_debug_settings_callback'))
      return
    endif
  endfor
  call a:next()
endfunction

function! s:start_debug_adapter(buffer) abort
  function! s:start_debug_session_callback(data) closure
    if has_key(a:data, 'result')
      let l:port = a:data['result']
      echomsg 'Connecting to debug adapter on port '.l:port
      call dap#connect(l:port)
    elseif has_key(a:data, 'error')
      call dap#log_error('Failed to start debug session, is the language server running? Error message to follow:')
      call dap#log_error(a:data['error']['message'])
    else
      call dap#log_error('Call to vscode.java.startDebugSession returned unexpected response.')
    endif
  endfunction

  call dap#lsp#execute_command(a:buffer, 'vscode.java.startDebugSession', [], function('s:start_debug_session_callback'))
endfunction

function! dap#lang#java#run(buffer) abort
  if dap#is_connected()
    " Java at least requires us to start a new debug adapter for each session.
    call dap#restart(a:buffer)
  else
    function! s:settings_loaded() closure
      call s:start_debug_adapter(a:buffer)
    endfunction
    call s:load_debug_settings(a:buffer, function('s:settings_loaded'))
  endif
endfunction

function! s:find_line(buffer, pat) abort
  let l:line_number = 1
  while 1
    let l:line = getbufline(a:buffer, l:line_number)
    if empty(l:line)
      return ''
    endif
    if l:line[0] =~ a:pat
      return l:line[0]
    endif
    let l:line_number += 1
  endwhile
endfunction

function! dap#lang#java#package_name(buffer) abort
  let l:package_line = s:find_line(a:buffer, '^package ')
  if l:package_line == ''
    return ''
  endif

  let l:parts = split(l:package_line)
  let l:package = parts[1]
  return substitute(l:package, ';', '', '')
endfunction

function! dap#lang#java#public_class_name(buffer) abort
  let l:public_class_line = s:find_line(a:buffer, '^public class ')
  if l:public_class_line == ''
    throw 'No public class line found, is the buffer loaded?'
  endif
  let l:parts = split(l:public_class_line)
  return l:parts[2]
endfunction

function! dap#lang#java#full_class_name(buffer) abort
  let l:package_name = dap#lang#java#package_name(a:buffer)
  let l:class_name = dap#lang#java#public_class_name(a:buffer)
  if l:package_name == ''
    return l:class_name
  else
    return l:package_name.'.'.l:class_name
  endif
endfunction

function! dap#lang#java#test_name() abort
  let l:line_number = search('^\s*@Test\>', 'bnW')
  if l:line_number == 0
    throw 'No @Test annotation found.'
  endif
  let l:line_number += 1
  while 1
    let l:line = getbufline('%', l:line_number)
    if empty(l:line)
      throw 'No public void method found after @Test annotation'
    endif
    if l:line[0] =~ '\s*public void '
      let l:parts = split(l:line[0])
      let l:test_name = l:parts[2]
      let l:open_paren = stridx(l:test_name, '(')
      if l:open_paren != -1
        let l:test_name = l:test_name[:l:open_paren-1]
      endif
      return l:test_name
    endif
  endwhile
endfunction

function! s:get_test_runner(buffer) abort
  for l:line in getbufline(a:buffer, 1, '$')
    if stridx(l:line, 'import org.junit.jupiter.api.Test') > -1
      echoerr 'JUnit 5 is not supported (yet)'
    elseif stridx(l:line, 'import org.junit.Test') > -1
      return 'JUnit4TestRunner'
    endif
  endfor
  echoerr 'No recognized Test imports found'
endfunction

" vim: set expandtab shiftwidth=2 tabstop=2:
