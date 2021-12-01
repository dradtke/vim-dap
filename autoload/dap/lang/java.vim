let s:plugin_home = fnamemodify(expand('<sfile>:p'), ':h:h:h:h')
let s:current_buffer = v:null

set errorformat+=%f:%l\ -\ %m

augroup java_adapter_terminated
  autocmd!
  autocmd User dap_adapter_terminated call dap#open_quickfix()
augroup END

function! dap#lang#java#run(buffer) abort
  if dap#is_connected()
    " Java at least requires us to start a new debug adapter for each session.
    call dap#restart(a:buffer)
  else
    function! s:run_load_debug_settings_callback() closure
      call s:start_debug_adapter(a:buffer)
    endfunction
    call s:load_debug_settings(a:buffer, function('s:run_load_debug_settings_callback'))
  endif
endfunction

function! dap#lang#java#launch(buffer, run_args) abort
  call dap#clear_quickfix()
  call dap#launch(a:run_args[0])
endfunction

function! dap#lang#java#run_test_class() abort
  let l:buffer = bufnr('%')

  function! s:run_test_class_items_callback(test_items) closure
    call filter(a:test_items, 'v:val["testLevel"] == 5')
    if empty(a:test_items)
      echoerr 'No class test items found'
    endif
    call s:run_test_item(l:buffer, a:test_items[0])
  endfunction

  call s:get_test_items(l:buffer, function('s:run_test_class_items_callback'))
endfunction

function! dap#lang#java#run_test_method() abort
  let l:buffer = bufnr('%')

  function! s:run_test_method_items_callback(test_items) closure
    call filter(a:test_items, 'v:val["testLevel"] == 5')
    if empty(a:test_items)
      echoerr 'No class test items found'
    endif

    let l:method_test_items = get(a:test_items[0], 'children', [])
    if empty(l:method_test_items)
      echoerr 'No method test items found'
    endif

    call filter(l:method_test_items, 'v:val["testLevel"] == 6')
    call filter(l:method_test_items, 'v:val["range"]["start"]["line"] < '.line('.'))

    " sort by line number, descending
    function! s:test_items_sort(x, y)
      return a:y['range']['start']['line'] - a:x['range']['start']['line'] 
    endfunction

    call sort(l:method_test_items, function('s:test_items_sort'))

    if !empty(l:method_test_items)
      call s:run_test_item(l:buffer, l:method_test_items[0])
    endif
  endfunction

  call s:get_test_items(l:buffer, function('s:run_test_method_items_callback'))
endfunction

function! s:get_test_items(buffer, callback) abort
  function! s:code_lens_callback(data) closure
    if has_key(a:data, 'result')
      let l:test_items = a:data['result']
      call a:callback(l:test_items)
    elseif has_key(a:data, 'error')
      call dap#log_error('Call to vscode.java.test.findTestTypesAndMethods returned unexpected response.')
    endif
  endfunction

  let l:params = ['file://'.getbufinfo(a:buffer)[0]['name']]
  call dap#lsp#execute_command(a:buffer, 'vscode.java.test.findTestTypesAndMethods', l:params, function('s:code_lens_callback'))
endfunction

function! s:run_test_item(buffer, test_item) abort
  let l:test_runner = s:get_test_runner(a:test_item)

  function! s:get_classpaths_callback(data) closure
    if has_key(a:data, 'error')
      call dap#log_error('Error calling java.project.getClasspaths: '.a:data['error']['message'])
      return
    endif
    let l:project_root = dap#util#uri_to_path(a:data['result']['projectRoot'])
    let l:project_name = fnamemodify(l:project_root, ':t')
    let l:classpaths = a:data['result']['classpaths']
    let l:modulepaths = a:data['result']['modulepaths']

    " TODO: shellescape args?
    let l:misc = s:plugin_home.'/misc'
    call add(l:classpaths, l:misc)
    if !filereadable(l:misc.'/'.l:test_runner.'.class')
      call dap#log('Classpaths: '.join(l:classpaths, ':'))
      let l:output = system('javac -cp "'.join(l:classpaths, ':').'" -d "'.l:misc.'" "'.l:misc.'/'.l:test_runner.'.java"')
      if v:shell_error
        throw 'Failed to compile single test runner: '.l:output
      endif
    endif

    call dap#clear_quickfix()

    let l:args = join([a:test_item['fullName'], expand('#'.a:buffer), dap#get_quickfix_file()])
    call dap#run(a:buffer, {
          \ 'mainClass': l:test_runner,
          \ 'args': l:args,
          \ 'classPaths': l:classpaths,
          \ 'modulePaths': l:modulepaths,
          \ 'cwd': l:project_root,
          \ 'projectName': l:project_name,
          \ 'shortenCommandLine': 'jarmanifest',
          \ })
  endfunction

  call dap#lsp#execute_command(a:buffer, 'java.project.getClasspaths', [a:test_item['uri'], json_encode({'scope': 'test'})], function('s:get_classpaths_callback'))
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

function! s:get_test_runner(test_item) abort
  " See https://github.com/microsoft/vscode-java-test/blob/main/java-extension/com.microsoft.java.test.plugin/src/main/java/com/microsoft/java/test/plugin/model/TestKind.java
  if a:test_item['testKind'] == '0'
    echoerr 'JUnit 5 not yet supported'
  elseif a:test_item['testKind'] == '1'
    return 'JUnit4TestRunner'
  elseif a:test_item['testKind'] == '2'
    echoerr 'TestNG not yet supported'
  else
    echoerr 'Unknown test item kind: '.a:test_item['testKind']
  endif
endfunction

" vim: set expandtab shiftwidth=2 tabstop=2:
