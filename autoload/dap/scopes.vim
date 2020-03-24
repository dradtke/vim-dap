let s:scopes_guard = {}
let s:scopes_result = {}

function! dap#scopes#request(frame_id) abort
  let l:body = {'frameId': a:frame_id}
  call dap#send_message(dap#build_request('scopes', l:body))
endfunction

function! dap#scopes#response(data) abort
  let s:scopes_guard = {}
  let s:scopes_result = {}
  let l:var_requests = []
  for l:scope in a:data['body']['scopes']
    let l:request = dap#build_request('variables', {'variablesReference': l:scope['variablesReference']})
    let s:scopes_guard[l:request['seq']] = l:scope['name']
    call add(l:var_requests, l:request)
  endfor
  for l:request in l:var_requests
    call dap#send_message(l:request)
  endfor
endfunction

function! dap#scopes#waiting_for(request_seq) abort
  return has_key(s:scopes_guard, a:request_seq)
endfunction

function! dap#scopes#variables_response(data) abort
  let l:scope_name = s:scopes_guard[a:data['request_seq']]
  let s:scopes_result[l:scope_name] = a:data['body']['variables']
  if len(s:scopes_guard) == len(s:scopes_result)
    call dap#write_result(json_encode(s:scopes_result))
  endif
endfunction
