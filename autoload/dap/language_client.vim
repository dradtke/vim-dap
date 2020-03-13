function! dap#language_client#run(buffer)
  let l:filetype = getbufvar(a:buffer, '&filetype')
  if l:filetype == 'java'
    function! s:start_callback(data) closure
      if has_key(a:data, 'result')
        let l:port = a:data['result']
        call dap#connect(l:port)
      elseif has_key(a:data, 'error')
        echoerr a:data['error']['message']
      else
        echoerr 'Call to vscode.java.startDebugSession returned unexpected response.'
      endif
    endfunction

    call LanguageClient#workspace_executeCommand('vscode.java.startDebugSession', [], function('s:start_callback'))
  else
    echoerr 'unsupported filetype for language client: '.a:filetype
  endif
endfunction

function! dap#language_client#launch(buffer, ...)
  let l:filetype = getbufvar(a:buffer, '&filetype')
  if l:filetype == 'java'
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

        let l:package = dap#java#package_name(a:buffer)
        let l:class_name = dap#java#public_class_name(a:buffer)
        let l:full_class = l:package.'.'.l:class_name
        " If this is a test file, execute JUnit and pass the class in as an
        " argument.
        " TODO: shellescape args?
        if l:is_test
          " TODO: support configuring the test runner
          call dap#launch({
                \ 'mainClass': 'org.junit.runner.JUnitCore',
                \ 'args': l:full_class.' '.join(a:000, ' '),
                \ 'classPaths': l:classpaths,
                \ })
        else
          call dap#launch({
                \ 'mainClass': l:full_class,
                \ 'args': join(a:000, ' '),
                \ 'classPaths': l:classpaths,
                \ })
        endif
      endfunction

      let l:scope = (l:is_test ? 'test' : 'runtime')
      call LanguageClient#workspace_executeCommand('java.project.getClasspaths', [l:path, json_encode({'scope': l:scope})], function('s:get_classpaths_callback'))
    endfunction

    call LanguageClient#workspace_executeCommand('java.project.isTestFile', [l:path], function('s:is_test_callback'))
  else
    echoerr 'unsupported filetype for language client: '.a:filetype
  endif
endfunction
