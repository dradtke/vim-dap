let s:test_runner_main_class = 'org.junit.runner.JUnitCore'
let s:test_runner_args_builder = {mainclass -> mainclass}

function! dap#lang#java#set_test_runner_main_class(class)
  let s:test_runner_main_class = a:class
endfunction

" This function can be used to customize how arguments are passed to the test
" runner. It expects a function which itself takes one argument, the
" fully-qualified name of the class to run tests for, and should return a
" string which will be passed to the test runner as its arguments.
function! dap#lang#java#set_test_runner_args_builder(f)
  let s:test_runner_args_builder = a:f
endfunction

function! dap#lang#java#run(buffer) abort
  if dap#is_connected()
    " Java at least requires us to start a new debug adapter for each session.
    call dap#restart(a:buffer)
  else
    function! s:start_callback(data) closure
      if has_key(a:data, 'result')
        let l:port = a:data['result']
        call dap#connect(l:port)
      elseif has_key(a:data, 'error')
        echoerr 'Failed to start debug session, is the language server running? Error message to follow:'
        echoerr a:data['error']['message']
      else
        echoerr 'Call to vscode.java.startDebugSession returned unexpected response.'
      endif
    endfunction

    call dap#lsp#execute_command('vscode.java.startDebugSession', [], function('s:start_callback'))
  endif
endfunction

function! dap#lang#java#launch(buffer, run_args) abort
  let l:path = 'file://'.getbufinfo(a:buffer)[0]['name']

  function! s:is_test_callback(data) closure
    if has_key(a:data, 'error')
      echoerr 'Error calling java.project.isTestFile: '.a:data['error']['message']
      return
    endif
    let l:is_test = a:data['result']

    function! s:get_classpaths_callback(data) closure
      if has_key(a:data, 'error')
        echoerr 'Error calling java.project.getClasspaths: '.a:data['error']['message']
        return
      endif
      " TODO: check for modulepaths
      let l:classpaths = a:data['result']['classpaths']

      let l:package = dap#lang#java#package_name(a:buffer)
      let l:class_name = dap#lang#java#public_class_name(a:buffer)
      let l:full_class = l:package.'.'.l:class_name
      " If this is a test file, execute JUnit and pass the class in as an
      " argument.
      " TODO: shellescape args?
      if l:is_test
        " TODO: support configuring the test runner
        call dap#launch({
              \ 'mainClass': s:test_runner_main_class,
              \ 'args': s:test_runner_args_builder(l:full_class).' '.join(a:run_args, ' '),
              \ 'classPaths': l:classpaths,
              \ })
      else
        call dap#launch({
              \ 'mainClass': l:full_class,
              \ 'args': join(a:run_args, ' '),
              \ 'classPaths': l:classpaths,
              \ })
      endif
    endfunction

    let l:scope = (l:is_test ? 'test' : 'runtime')
    call dap#lsp#execute_command('java.project.getClasspaths', [l:path, json_encode({'scope': l:scope})], function('s:get_classpaths_callback'))
  endfunction

  call dap#lsp#execute_command('java.project.isTestFile', [l:path], function('s:is_test_callback'))
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
    throw 'No package line found, is the buffer loaded?'
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
