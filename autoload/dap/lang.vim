function! dap#lang#run(buffer) abort
  let l:filetype = getbufvar(a:buffer, '&filetype')
  if l:filetype == 'java'
    call dap#lang#java#run(a:buffer)
  elseif l:filetype == 'go'
    call dap#lang#go#run(a:buffer)
  else
    throw 'vim-dap: unsupported filetype: '.l:filetype
  endif
endfunction

function! dap#lang#initialized(buffer, run_args) abort
  let l:filetype = getbufvar(a:buffer, '&filetype')
  " This method is written under the assumption that what needs to happen
  " after initialization varies by language. For example, java needs to launch
  " a VM before setting breakpoints, but other languages may need things done
  " in a different order.
  if l:filetype == 'java'
    let g:run_args = a:run_args[0]
    call dap#lang#java#launch(a:run_args[0])
  elseif l:filetype == 'go'
    call dap#lang#go#launch(a:buffer, a:run_args)
  else
    throw 'vim-dap: unsupported filetype: '.l:filetype
  endif
endfunction

function! dap#lang#supports_dynamic_breakpoints(buffer) abort
  let l:filetype = getbufvar(a:buffer, '&filetype')
  if l:filetype == 'java'
    return v:true
  endif
  return v:false
endfunction

" vim: set expandtab shiftwidth=2 tabstop=2:
