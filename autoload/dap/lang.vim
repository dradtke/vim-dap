function! dap#lang#run(buffer, run_args) abort
  let l:filetype = getbufvar(a:buffer, '&filetype')
  if l:filetype == 'java'
    call dap#lang#java#run(a:buffer)
  endif
endfunction

function! dap#lang#initialized(buffer, run_args) abort
  let l:filetype = getbufvar(a:buffer, '&filetype')
  " This method is written under the assumption that what needs to happen
  " after initialization varies by language. For example, java needs to launch
  " a VM before setting breakpoints, but other languages may need things done
  " in a different order.
  if l:filetype == 'java'
    call dap#lang#java#launch(a:buffer, a:run_args)
  endif
endfunction
