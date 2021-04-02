let s:plugin_home = fnamemodify(expand('<sfile>:p'), ':h:h:h:h')
let s:current_buffer = v:null

let s:test_runner_main_class = v:null
let s:test_runner_args_builder = {mainclass -> mainclass}

function! dap#lang#java#run_test_class() abort
  call dap#run('%')
endfunction

function! dap#lang#java#run_test_method() abort
  let l:class_name = dap#lang#java#full_class_name('%')
  let l:test_name = dap#lang#java#test_name()
  call dap#run('%', l:class_name.'#'.l:test_name)
endfunction

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

function! s:load_debug_settings(buffer, next) abort
  for l:path in ['.vim/launch.json', '.vscode/launch.json']
    if filereadable(l:path)
      function! s:settings_updated_callback(data) closure
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
      call dap#lsp#execute_command(a:buffer, 'vscode.java.updateDebugSettings', [json_encode(l:settings)], function('s:settings_updated_callback'))
      return
    endif
  endfor
  call a:next()
endfunction

function! s:start_debug_adapter(buffer) abort
  function! s:cb(data) closure
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

  call dap#lsp#execute_command(a:buffer, 'vscode.java.startDebugSession', [], function('s:cb'))
endfunction

function! dap#lang#java#run(buffer) abort
  if dap#is_connected()
    " Java at least requires us to start a new debug adapter for each session.
    call dap#restart(a:buffer)
  else
    function! s:run_cb1() closure
      call s:start_debug_adapter(a:buffer)
    endfunction
    call s:load_debug_settings(a:buffer, function('s:run_cb1'))
  endif
endfunction

function! dap#lang#java#launch(buffer, run_args) abort
  let l:path = 'file://'.getbufinfo(a:buffer)[0]['name']

  function! s:is_test_callback(data) closure
    if has_key(a:data, 'error')
      call dap#log_error('Error calling java.project.isTestFile: '.a:data['error']['message'])
      return
    endif
    let l:is_test = a:data['result']

    function! s:get_classpaths_callback(data) closure
      if has_key(a:data, 'error')
        call dap#log_error('Error calling java.project.getClasspaths: '.a:data['error']['message'])
        return
      endif
      let l:project_root = dap#util#uri_to_path(a:data['result']['projectRoot'])
      let l:project_name = fnamemodify(l:project_root, ':t')
      let l:classpaths = a:data['result']['classpaths']
      let l:modulepaths = a:data['result']['modulepaths']

      let l:args = join(a:run_args, ' ')

      " If this is a test file, execute JUnit and pass the class in as an
      " argument.
      " TODO: shellescape args?
      if l:is_test
        let l:misc = s:plugin_home.'/misc'
        call add(l:classpaths, l:misc)
        let l:test_runner = s:test_runner_main_class
        if l:test_runner == v:null
          let l:test_runner = s:get_test_runner()
          if !filereadable(l:misc.'/'.l:test_runner.'.class')
            call dap#log('Classpaths: '.join(l:classpaths, ':'))
            let l:output = system('javac -cp "'.join(l:classpaths, ':').'" -d "'.l:misc.'" "'.l:misc.'/'.l:test_runner.'.java"')
            if v:shell_error
              throw 'Failed to compile single test runner: '.l:output
            endif
          endif
        endif

        " TODO: use s:test_runner_args_builder again
        if len(a:run_args) == 0
          let l:args = dap#lang#java#full_class_name(a:buffer)
        endif
        call dap#launch({
              \ 'mainClass': l:test_runner,
              \ 'args': l:args,
              \ 'classPaths': l:classpaths,
              \ 'modulePaths': l:modulepaths,
              \ 'cwd': l:project_root,
              \ 'projectName': l:project_name,
              \ 'shortenCommandLine': 'jarmanifest',
              \ })
      else
        call dap#launch({
              \ 'mainClass': dap#lang#java#full_class_name(a:buffer),
              \ 'args': l:args,
              \ 'classPaths': l:classpaths,
              \ 'modulePaths': l:modulepaths,
              \ 'cwd': l:project_root,
              \ 'projectName': l:project_name,
              \ 'shortenCommandLine': 'jarmanifest',
              \ })
      endif
    endfunction

    let l:scope = (l:is_test ? 'test' : 'runtime')
    call dap#lsp#execute_command(a:buffer, 'java.project.getClasspaths', [l:path, json_encode({'scope': l:scope})], function('s:get_classpaths_callback'))
  endfunction

  call dap#lsp#execute_command(a:buffer, 'java.project.isTestFile', [l:path], function('s:is_test_callback'))
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

function! s:get_test_runner() abort
  if search('import org.junit.jupiter.api.Test', 'nw') > 0
    echoerr 'JUnit 5 is not supported (yet)'
  elseif search('import org.junit.Test', 'nw') > 0
    return 'JUnit4TestRunner'
  else
    echoerr 'No recognized Test imports found'
  endif
endfunction

" vim: set expandtab shiftwidth=2 tabstop=2:
