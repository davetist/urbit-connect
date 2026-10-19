/-  c=connect
/+  *test, ch=connect-http, cc=connect-codec, cs=connect-store, server
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
++  test-anonymous-authorization-requires-login-before-reserving-capacity
  =/  now  ~2026.10.12
  =/  client=client:c  ['client' 'Test' 'test:/callback' 'namespace' & now]
  =/  clients=(map @t client:c)  (~(put by *(map @t client:c)) 'client' client)
  =/  auth=auth-state:c  [clients ~ ~ ~ ~]
  =/  spaces=(map @t space:c)  (~(put by *(map @t space:c)) 'namespace' empty:cs)
  =/  state=state-2:c  [%2 'instance' 'https://ship.example/connect' 1 0 auth spaces ~ ~]
  =/  current=world:c  [state ~ ~]
  =/  url=@t
    '/connect/oauth/authorize?response_type=code&client_id=client&redirect_uri=test%3A%2Fcallback&scope=documents%3Aread&state=state&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=S256'
  =/  request  request.ctx(request [%'GET' url ~ ~])
  =/  result  (handle:ch current ctx(local &, request request))
  ?>  ?=(^ payload.result)
  =/  location  (header:ch 'location' headers.response-header.u.payload.result)
  ;:  weld
    (expect-eq !>(302) !>(status-code.response-header.u.payload.result))
    (expect-eq !>('/~/login?redirect=') !>((crip (scag 18 (trip location)))))
    (expect-eq !>(0) !>((lent ~(tap by pending.auth.state.next.result))))
    (expect-eq !>(0) !>((lent ~(tap by starts.auth.state.next.result))))
  ==
++  test-malformed-authenticated-mutation-keeps-rate-charge
  =/  now  ~2026.10.12
  =/  client=client:c  ['client' 'Test' 'test:/callback' 'namespace' & now]
  =/  session=session:c
    ['session' 'client' 'namespace' 1 (silt ~['documents:write']) 'Phone' (shax 'access') (add now ~m10) 0x1 ~ now (add now ~d30) (div now ~m1) 119]
  =/  clients=(map @t client:c)  (~(put by *(map @t client:c)) 'client' client)
  =/  sessions=(map @t session:c)  (~(put by *(map @t session:c)) 'session' session)
  =/  auth=auth-state:c  [clients ~ ~ sessions ~]
  =/  spaces=(map @t space:c)  (~(put by *(map @t space:c)) 'namespace' empty:cs)
  =/  state=state-2:c  [%2 'instance' 'https://ship.example/connect' 1 0 auth spaces ~ ~]
  =/  current=world:c  [state ~ ~]
  =/  fields  ~[['authorization' 'Bearer access']]
  =/  invalid  (as-octs:mimes:html '{')
  =/  request  request.ctx(request [%'POST' '/connect/v1/mutations' fields `invalid])
  =/  attempt  (mule |.(!>((handle:ch current ctx(request request)))))
  ?:  ?=(%| -.attempt)  (expect-eq !>(%&) !>(%|))
  =/  result  !<(http-result:c p.attempt)
  ?>  ?=(^ payload.result)
  =/  charged  (~(got by sessions.auth.state.next.result) 'session')
  =/  limited  (handle:ch next.result ctx(request request))
  ?>  ?=(^ payload.limited)
  =/  stopped  (~(got by sessions.auth.state.next.limited) 'session')
  ;:  weld
    (expect-eq !>(400) !>(status-code.response-header.u.payload.result))
    (expect-eq !>(120) !>(requests.charged))
    (expect-eq !>(429) !>(status-code.response-header.u.payload.limited))
    (expect-eq !>(120) !>(requests.stopped))
  ==
++  test-owner-cannot-erase-resource-owned-data-through-connect
  =/  now  ~2026.10.12
  =/  client=client:c  ['client' 'Resource' 'resource:/callback' 'namespace' & now]
  =/  clients=(map @t client:c)  (~(put by *(map @t client:c)) 'client' client)
  =/  policy=integration:c  [%grant-probe (silt ~['vault:read']) (silt ~['resource:/callback'])]
  =/  policies=(map @t integration:c)  (~(put by *(map @t integration:c)) 'client' policy)
  =/  spaces=(map @t space:c)  (~(put by *(map @t space:c)) 'namespace' empty:cs)
  =/  contexts=(map @ux csrf:c)
    (~(put by *(map @ux csrf:c)) (shax 'owner-cookie') [(shax 'csrf') (add now ~m30)])
  =/  auth=auth-state:c  [clients ~ ~ ~ ~]
  =/  state=state-2:c  [%2 'instance' 'https://ship.example/connect' 1 0 auth spaces contexts policies]
  =/  current=world:c  [state ~ ~]
  =/  fields
    :~  ['cookie' 'owner-cookie']  ['origin' 'https://ship.example']
        ['x-connect-csrf' 'csrf']  ['content-type' 'application/json']
    ==
  =/  data  (as-octs:mimes:html '{"confirmNamespace":"namespace"}')
  =/  req  request.ctx(authenticated &, request [%'POST' '/connect/owner/v1/namespaces/namespace/erase' fields `data])
  =/  result  (handle:ch current ctx(local &, request req))
  ?>  ?=(^ payload.result)
  ;:  weld
    (expect-eq !>(409) !>(status-code.response-header.u.payload.result))
    (expect-eq !>(spaces.state.current) !>(spaces.state.next.result))
  ==
--
