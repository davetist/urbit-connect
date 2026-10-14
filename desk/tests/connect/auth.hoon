/-  c=connect
/+  *test, ca=connect-auth, cc=connect-codec
=/  now  ~2026.10.12
=/  verifier  'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'
=/  request=authorization:c
  ['pending' 'client' 'test:/callback' 'namespace' 1 (silt ~['documents:read' 'documents:write']) (challenge:ca verifier) 'state' 'Phone' (add now ~m5)]
=/  db=auth-state:c
  [(~(put by *(map @t client:c)) 'client' ['client' 'Test' 'test:/callback' 'namespace' & now]) ~ (~(put by *(map @ux code:c)) (shax 'secret') [request (add now ~s60)]) ~ ~]
|%
++  first  (exchange:ca db 'secret' 'client' 'test:/callback' verifier now 'session' 'access' 'refresh')
++  test-rfc7636-pkce-vector
  (expect-eq !>('E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM') !>((challenge:ca verifier)))
++  test-code-exchange
  =/  done  first
  ;:  weld
    (expect-eq !>(200) !>(status.outcome.done))
    (expect-eq !>(%.y) !>(?=(^ (access:ca next.done 'access' now))))
    (expect-eq !>(~) !>((access:ca next.done 'wrong' now)))
  ==
++  test-code-cannot-be-consumed-twice
  =/  done  first
  =/  again  (exchange:ca next.done 'secret' 'client' 'test:/callback' verifier now 'session2' 'a2' 'r2')
  (expect-eq !>(400) !>(status.outcome.again))
++  test-wrong-pkce-redirect-client-and-expiry
  =/  a  (exchange:ca db 'secret' 'client' 'test:/callback' 'wrong' now 's' 'a' 'r')
  =/  b  (exchange:ca db 'secret' 'client' 'evil:/callback' verifier now 's' 'a' 'r')
  =/  d  (exchange:ca db 'secret' 'other' 'test:/callback' verifier now 's' 'a' 'r')
  =/  e  (exchange:ca db 'secret' 'client' 'test:/callback' verifier (add now ~s60) 's' 'a' 'r')
  ;:  weld
    (expect-eq !>(400) !>(status.outcome.a))
    (expect-eq !>(400) !>(status.outcome.b))
    (expect-eq !>(400) !>(status.outcome.d))
    (expect-eq !>(400) !>(status.outcome.e))
  ==
++  test-refresh-rotation-and-replay-revokes-family
  =/  done  first
  =/  next  (rotate:ca next.done 'refresh' 'client' now 'a2' 'r2')
  =/  replay  (rotate:ca next.next 'refresh' 'client' now 'a3' 'r3')
  ;:  weld
    (expect-eq !>(200) !>(status.outcome.next))
    (expect-eq !>(400) !>(status.outcome.replay))
    (expect-eq !>(~) !>((access:ca next.replay 'a2' now)))
  ==
++  test-access-and-absolute-session-expiry
  =/  made  first
  =/  expired  (rotate:ca next.made 'refresh' 'client' (add now ~d30) 'a2' 'r2')
  ;:  weld
    (expect-eq !>(~) !>((access:ca next.made 'access' (add now ~m10))))
    (expect-eq !>(400) !>(status.outcome.expired))
  ==
++  test-refresh-retention-bound-requires-new-authorization
  =/  made  first
  =/  session  (~(got by sessions.next.made) 'session')
  =.  session  session(consumed (silt (gulf 1 4.096)))
  =/  full  next.made(sessions (~(put by sessions.next.made) 'session' session))
  =/  result  (rotate:ca full 'refresh' 'client' now 'a2' 'r2')
  ;:  weld
    (expect-eq !>(400) !>(status.outcome.result))
    (expect-eq !>(~) !>(sessions.next.result))
  ==
++  test-session-capacity
  =/  made  first
  =/  session  (~(got by sessions.next.made) 'session')
  =/  entries
    %-  malt
    %+  turn  (gulf 1 32)
    |=  index=@ud
    =/  id  (ud:cc index)
    [id session(id id)]
  =/  result  (exchange:ca db(sessions entries) 'secret' 'client' 'test:/callback' verifier now 'new' 'a' 'r')
  (expect-eq !>(429) !>(status.outcome.result))
--
