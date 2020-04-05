let s:plugin_home = fnamemodify(expand('<sfile>:p'), ':h:h:h:h')
let s:adapter_url = 'https://github.com/microsoft/vscode-go/releases/download/0.13.1/Go-0.13.1.vsix'

function! dap#lang#go#run(buffer) abort
  let l:adapter_path = s:plugin_home.'/adapters/go'
  if !isdirectory(l:adapter_path)
    call mkdir(l:adapter_path, 'p')
    echomsg 'Installing Go debug adapter...'
    call dap#util#download(s:adapter_url, l:adapter_path.'/vscode-go.vsix')
    call dap#util#unzip(l:adapter_path.'/vscode-go.vsix', l:adapter_path)
    echomsg 'Go debug adapter installed.'
  endif

  if !executable('node')
    throw 'command "node" not found! please install Node and try again'
  endif

  call dap#spawn(['node', l:adapter_path.'/extension/out/src/debugAdapter/goDebug.js'])
  " call dap#spawn(['node', '/home/damien/Workspace/language-servers/vscode-go/out/src/debugAdapter/goDebug.js'])
endfunction

function! dap#lang#go#launch(buffer, run_args)
  if !executable('dlv')
    throw '"dlv" executable not found'
  endif
  echomsg 'Launching Go'
  let l:buffer_path = getbufinfo(a:buffer)[0]['name']
  " For debugging, set 'trace' to 'verbose'
  let l:args = {
        \ 'request': 'launch',
        \ 'program': l:buffer_path,
        \ 'dlvToolPath': exepath('dlv'),
        \ 'args': a:run_args,
        \ }
  if l:buffer_path =~ '_test\.go$'
    let l:args['mode'] = 'test'
  endif
  call dap#launch(l:args)
endfunction

" vim: set expandtab shiftwidth=2 tabstop=2:
