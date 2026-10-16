/-  c=connect
/+  *test, cs=connect-store, cc=connect-codec, ca=connect-auth
=/  now  ~2026.10.12
=/  base=space:c  empty:cs
=/  auth=authority:c  ['test' 1 & & &]
=/  one=operation:c  [%put ['lists' 'new'] (object:cc ~[['text' [%s 'a']]]) ~]
=/  req=mutation:c  ['request' 0x1 ~[one]]
|%
++  test-tombstone-expiry
  =/  db  base(tombstones (~(put by *(map key:c tombstone:c)) key.one [1 (add now ~d30)]))
  =/  denied  (mutate:cs db auth now req)
  =/  allowed  (mutate:cs db auth (add now ~d30) req)
  ;:  weld
    (expect-eq !>(409) !>(status.outcome.denied))
    (expect-eq !>(200) !>(status.outcome.allowed))
  ==
++  test-journal-count-byte-truncation-and-gap
  =/  log  (turn (gulf 1 1.025) |=(n=@ud ^-([@ud (list json) @ud] [n ~ 1])))
  =/  trimmed  (trim-log:cs log)
  =/  db  base(revision 1.025, journal trimmed)
  =/  gap  (changes:cs db 1 '1:1:0')
  =/  retained  (changes:cs db 1 '1:1:1')
  ;:  weld
    (expect-eq !>(1.024) !>((lent trimmed)))
    (expect-eq !>(410) !>(status.gap))
    (expect-eq !>(200) !>(status.retained))
    (expect-eq !>(1) !>((lent (trim-log:cs ~[[1 ~ 600.000] [2 ~ 600.000]]))))
  ==
++  test-write-only-conflict-body-is-null
  =/  made  (mutate:cs empty:cs auth now req)
  =/  denied  (mutate:cs next.made auth(read |) now req(id 'different'))
  ;:  weld
    (expect-eq !>(409) !>(status.outcome.denied))
    (expect-eq !>(~) !>((field:cc 'current' (field:cc 'error' body.outcome.denied))))
  ==
++  test-empty-operations
  =/  empty  (mutate:cs empty:cs auth now req(operations ~))
  (expect-eq !>(400) !>(status.outcome.empty))
--
