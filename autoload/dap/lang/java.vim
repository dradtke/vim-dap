let s:plugin_home = fnamemodify(expand('<sfile>:p'), ':h:h:h:h')
let s:current_buffer = v:null

" let s:test_runner_main_class = 'org.junit.runner.JUnitCore'
let s:custom_junit_runner = 'JUnitTestRunner'
let s:test_runner_main_class = s:custom_junit_runner
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

    if &filetype != 'java'
      let s:current_buffer = bufnr('%')
      execute 'hide buffer '.a:buffer
    endif
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
      let g:is_test = l:is_test
      let g:result = a:data
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
        if s:test_runner_main_class == s:custom_junit_runner && !filereadable(l:misc.'/'.s:custom_junit_runner.'.class')
          let l:output = system('javac -cp "'.join(l:classpaths, ':').'" -d "'.l:misc.'" "'.l:misc.'/'.s:custom_junit_runner.'.java"')
          if v:shell_error
            throw 'Failed to compile single test runner: '.l:output
          endif
        endif

        " TODO: use s:test_runner_args_builder again
        if len(a:run_args) == 0
          let l:args = dap#lang#java#full_class_name(a:buffer)
        endif
        call dap#launch({
              \ 'mainClass': s:test_runner_main_class,
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

      if s:current_buffer != v:null
        execute 'hide buffer '.s:current_buffer
        let s:current_buffer = v:null
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

" vim: set expandtab shiftwidth=2 tabstop=2:
