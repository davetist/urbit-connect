/-  c=connect
/+  *test, ca=connect-auth, ci=connect-integrations, ch=connect-http, cs=connect-store
|%
++  test-public-session-id-does-not-disclose-token-seed
  =/  seed=@  33
  =/  public  (slav %uv (session-id:ci seed))
  ;:  weld
    (expect-eq !>(%.n) !>(=(seed public)))
    (expect-eq !>(%.n) !>(=((shas %access seed) (shas %access public))))
    (expect-eq !>(%.n) !>(=((shas %refresh seed) (shas %refresh public))))
  ==
++  test-explicit-loopback-policy
  ;:  weld
    (expect-eq !>(%.y) !>((loopback:ci 'http://localhost:8065')))
    (expect-eq !>(%.y) !>((loopback:ci 'http://127.0.0.1:18065/callback')))
    (expect-eq !>(%.n) !>((loopback:ci 'http://example.com:8065')))
    (expect-eq !>(%.n) !>((loopback:ci 'http://localhost:80')))
    (expect-eq !>(%.n) !>((loopback:ci 'http://localhost:8065@evil.example')))
    (expect-eq !>(%.n) !>((valid-redirect:ca 'http://localhost:8065')))
  ==
++  test-resource-scopes-cannot-read-documents
  ;:  weld
    (expect-eq !>(%.n) !>((scope-name:ci 'documents:read')))
    (expect-eq !>(~) !>((scopes:ci 'documents:read' (silt ~['notes:read']))))
    (expect-eq !>(`(silt ~['notes:read'])) !>((scopes:ci 'notes:read' (silt ~['notes:read']))))
  ==
++  legacy-request
  |=  [resource=? method=?(%'GET' %'POST') url=@t]
  ^-  http-result:c
  =/  now  ~2026.10.14
  =/  seed=@  33
  =/  sid  (scot %uv seed)
  =/  access  (scot %uv (shas %access seed))
  =/  app=client:c  ['notes' 'Notes' 'notes:/callback' 'space' & now]
  =/  session=session:c
    [sid 'notes' 'space' 1 (silt ~['documents:read']) 'Notes' (shax access) (add now ~m10) 0x1 ~ now (add now ~d30) 0 0]
  =/  auth=auth-state:c
    [(~(put by *(map @t client:c)) 'notes' app) ~ ~ (~(put by *(map @t session:c)) sid session) ~]
  =/  policy=integration:c  [%grant-probe (silt ~['notes:read']) (silt ~['notes:/callback'])]
  =/  policies=(map @t integration:c)  ?:(resource (~(put by *(map @t integration:c)) 'notes' policy) ~)
  =/  world=world:c
    [[%2 'instance' 'https://ship.example/connect' 1 0 auth (~(put by *(map @t space:c)) 'space' empty:cs) ~ policies] ~ ~]
  =/  ctx=context:c
    [~zod ~nec now 0v1 'test' | & [| & [%ipv4 .127.0.0.1] [method url ~[['authorization' (cat 3 'Bearer ' access)]] ~]]]
  (handle:ch world ctx)
++  test-resource-bearer-rejected-by-all-http-routes
  =/  requests=(list [?(%'GET' %'POST') @t])
    :~  [%'GET' '/connect/v1/identity']
        [%'POST' '/connect/oauth/revoke']
        [%'GET' '/connect/v1/collections/notes/documents']
        [%'POST' '/connect/v1/mutations']
        [%'POST' '/connect/v1/snapshots']
        [%'GET' '/connect/v1/changes?after=1:1:0']
    ==
  %-  zing
  %+  turn  requests
  |=  [method=?(%'GET' %'POST') url=@t]
  =/  result  (legacy-request & method url)
  ?>  ?=(^ payload.result)
  ;:  weld
    (expect-eq !>(401) !>(status-code.response-header.u.payload.result))
    (expect-eq !>(1) !>((lent ~(tap by sessions.auth.state.next.result))))
  ==
++  test-ordinary-http-identity-and-revoke-preserved
  =/  identity  (legacy-request | %'GET' '/connect/v1/identity')
  =/  revoke  (legacy-request | %'POST' '/connect/oauth/revoke')
  ?>  &(?=(^ payload.identity) ?=(^ payload.revoke))
  ;:  weld
    (expect-eq !>(200) !>(status-code.response-header.u.payload.identity))
    (expect-eq !>(200) !>(status-code.response-header.u.payload.revoke))
    (expect-eq !>(0) !>((lent ~(tap by sessions.auth.state.next.revoke))))
  ==
--
