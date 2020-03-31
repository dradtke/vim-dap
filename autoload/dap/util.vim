function! dap#util#download(src, dest) abort
  call system('wget --output-document='.shellescape(a:dest).' '.shellescape(a:src))
  if v:shell_error
    throw 'Failed to download: '.a:src
  endif
endfunction

function! dap#util#unzip(src, dest) abort
  call system('unzip '.shellescape(a:src).' -d '.shellescape(a:dest))
  if v:shell_error
    throw 'Failed to unzip: '.a:src
  endif
endfunction

function! dap#util#format_string(format, variables) abort
  let l:message = a:format
  for l:item in items(a:variables)
    let l:name = l:item[0]
    let l:value = l:item[1]
    let l:message = substitute(l:message, '{'.l:name.'}', l:value, 'g')
  endfor
  return l:message
endfunction

function! dap#util#uri_to_path(uri) abort
  " This function assumes that uri represents a file, but doesn't verify that.
  let l:protocol_sep = stridx(a:uri, '://')
  if l:protocol_sep != -1
    return a:uri[l:protocol_sep+3:]
  endif
  let l:protocol_sep = stridx(a:uri, ':')
  if l:protocol_sep != -1
    return a:uri[l:protocol_sep+1:]
  endif
  throw 'dap#util#uri_to_path: not a uri: '.a:uri
endfunction

" vim: set expandtab shiftwidth=2 tabstop=2:
