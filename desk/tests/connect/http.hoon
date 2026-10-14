/-  c=connect
/+  *test, ch=connect-http, cc=connect-codec, server
=/  world=world:c  [[%2 'instance' '' 1 0 *auth-state:c ~ ~ ~] ~ ~]
=/  ctx=context:c  [~zod ~nec ~2026.10.12 0v1 'test' | & [| & [%ipv4 .127.0.0.1] [%'GET' '/apps/connect/' ~ ~]]]
|%
++  test-assets-trailing-slash
  =/  result  (handle:ch world ctx)
  ?>  ?=(^ payload.result)
  (expect-eq !>(200) !>(status-code.response-header.u.payload.result))
++  test-foreign-authenticated-cannot-be-owner
  =/  request  request.ctx(authenticated &, request [%'GET' '/connect/owner/v1/bootstrap' ~[['cookie' 'fake-test-cookie']] ~])
  =/  result  (handle:ch world ctx(request request))
  ?>  ?=(^ payload.result)
  (expect-eq !>(401) !>(status-code.response-header.u.payload.result))
++  test-local-delivery-without-cookie-is-not-owner
  =/  request  request.ctx(request [%'GET' '/connect/owner/v1/bootstrap' ~ ~])
  =/  result  (handle:ch world ctx(local &, request request))
  ?>  ?=(^ payload.result)
  (expect-eq !>(401) !>(status-code.response-header.u.payload.result))
++  test-owner-cookie-does-not-become-app-token
  =/  request  request.ctx(authenticated &, request [%'GET' '/connect/v1/identity' ~[['cookie' 'fake-test-cookie']] ~])
  =/  result  (handle:ch world ctx(local &, request request))
  ?>  ?=(^ payload.result)
  (expect-eq !>(401) !>(status-code.response-header.u.payload.result))
++  test-new-owner-context-evicts-oldest-without-lockout
  =/  contexts
    %-  malt
    %+  turn  (gulf 1 8)
    |=  index=@ud
    ^-  [@ux csrf:c]
    [`@ux`index [0x1 (add now.ctx (mul index ~m1))]]
  =/  current  world(csrf.state contexts)
  =/  request  request.ctx(authenticated &, request [%'GET' '/connect/owner/v1/bootstrap' ~[['cookie' 'new-owner-context']] ~])
  =/  result  (handle:ch current ctx(local &, request request))
  ?>  ?=(^ payload.result)
  ;:  weld
    (expect-eq !>(200) !>(status-code.response-header.u.payload.result))
    (expect-eq !>(8) !>((lent ~(tap by csrf.state.next.result))))
    (expect-eq !>(%.n) !>((~(has by csrf.state.next.result) 0x1)))
  ==
++  test-poll-capacity-retry-does-not-delay-normal-sync-a-minute
  =/  response  (payload:ch [429 (error:cc 'poll_capacity' 'Existing poll' ~)])
  (expect-eq !>('1') !>((header:ch 'retry-after' headers.response-header.response)))
++  test-repeated-backup-restores-use-fresh-runtime-entropy
  =/  cookie=@t  'restore-test-cookie'
  =/  csrf=@t  'restore-test-csrf'
  =/  contexts=(map @ux csrf:c)
    (~(put by *(map @ux csrf:c)) (shax cookie) [(shax csrf) (add now.ctx ~m30)])
  =/  backup  world(issuer.state 'https://ship.example/connect', csrf.state contexts)
  =/  fields
    :~  ['cookie' cookie]  ['origin' 'https://ship.example']
        ['x-connect-csrf' csrf]  ['content-type' 'application/json']
    ==
  =/  data  (as-octs:mimes:html '{"confirmInstanceId":"instance"}')
  =/  req  request.ctx(authenticated &, request [%'POST' '/connect/owner/v1/restore-epoch' fields `data])
  =/  first  (handle:ch backup ctx(local &, entropy 0v1, request req))
  =/  second  (handle:ch backup ctx(local &, entropy 0v2, request req))
  ?>  ?=(^ payload.first)
  ?>  ?=(^ payload.second)
  ;:  weld
    (expect-eq !>(200) !>(status-code.response-header.u.payload.first))
    (expect-eq !>(200) !>(status-code.response-header.u.payload.second))
    (expect-eq !>(%.n) !>(=(epoch.state.next.first epoch.state.next.second)))
    (expect-eq !>(%.n) !>(=(epoch.state.backup epoch.state.next.first)))
  ==
--
