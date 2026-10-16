/-  c=connect
/+  *test, cs=connect-store, cc=connect-codec, ca=connect-auth
=/  now  ~2026.10.12
=/  base=space:c  empty:cs
=/  auth=authority:c  ['test' 1 & & &]
=/  one=operation:c  [%put ['lists' 'new'] (object:cc ~[['text' [%s 'a']]]) ~]
=/  req=mutation:c  ['request' 0x1 ~[one]]
|%
++  rows
  |=  count=@ud
  ^-  (map key:c record:c)
  %-  malt
  %+  turn  (gulf 1 count)
  |=  index=@ud
  =/  key=key:c  ['lists' (ud:cc index)]
  [key [key (object:cc ~[['x' [%s 'small']]]) 1 now]]
++  test-document-count-limit-atomic
  =/  db  base(records (rows 1.000))
  =/  result  (mutate:cs db auth now req 16.777.216)
  ;:  weld
    (expect-eq !>(429) !>(status.outcome.result))
    (expect-eq !>(db) !>(next.result))
  ==
++  test-global-available-limit
  =/  result  (mutate:cs empty:cs auth now req 1)
  (expect-eq !>(429) !>(status.outcome.result))
++  test-document-byte-limit
  =/  value  (object:cc ~[['x' [%s (crip (reap 16.384 'x'))]]])
  =/  result  (mutate:cs empty:cs auth now req(operations ~[[%put key.one value ~]]) 16.777.216)
  (expect-eq !>(413) !>(status.outcome.result))
++  test-receipt-capacity-and-expiry
  =/  entries
    %-  malt
    %+  turn  (gulf 1 10.000)
    |=  index=@ud
    [(ud:cc index) [0x1 (add now ~d30) ~]]
  =/  db  base(receipts entries)
  =/  denied  (mutate:cs db auth now req 16.777.216)
  =/  allowed  (mutate:cs db auth (add now ~d30) req 16.777.216)
  ;:  weld
    (expect-eq !>(429) !>(status.outcome.denied))
    (expect-eq !>(200) !>(status.outcome.allowed))
    (expect-eq !>(1) !>((lent ~(tap by receipts.next.allowed))))
  ==
++  test-tombstone-expiry
  =/  db  base(tombstones (~(put by *(map key:c tombstone:c)) key.one [1 (add now ~d30)]))
  =/  denied  (mutate:cs db auth now req 16.777.216)
  =/  allowed  (mutate:cs db auth (add now ~d30) req 16.777.216)
  ;:  weld
    (expect-eq !>(409) !>(status.outcome.denied))
    (expect-eq !>(200) !>(status.outcome.allowed))
  ==
++  test-tombstone-capacity-preserves-the-live-record
  =/  entries
    %-  malt
    %+  turn  (gulf 1 10.000)
    |=  index=@ud
    [['old' (ud:cc index)] [1 (add now ~d30)]]
  =/  made  (mutate:cs empty:cs auth now req 16.777.216)
  =/  db  next.made(tombstones entries)
  =/  remove=mutation:c  ['delete-request' 0x2 ~[[%delete key.one 1]]]
  =/  denied  (mutate:cs db auth now remove 16.777.216)
  =/  allowed  (mutate:cs db auth (add now ~d30) remove 16.777.216)
  ;:  weld
    (expect-eq !>(429) !>(status.outcome.denied))
    (expect-eq !>(db) !>(next.denied))
    (expect-eq !>(200) !>(status.outcome.allowed))
    (expect-eq !>(~) !>(records.next.allowed))
    (expect-eq !>(1) !>((lent ~(tap by tombstones.next.allowed))))
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
  =/  made  (mutate:cs empty:cs auth now req 16.777.216)
  =/  denied  (mutate:cs next.made auth(read |) now req(id 'different') 16.777.216)
  ;:  weld
    (expect-eq !>(409) !>(status.outcome.denied))
    (expect-eq !>(~) !>((field:cc 'current' (field:cc 'error' body.outcome.denied))))
  ==
++  test-empty-and-too-many-operations
  =/  empty  (mutate:cs empty:cs auth now req(operations ~) 16.777.216)
  =/  many  (mutate:cs empty:cs auth now req(operations (reap 33 one)) 16.777.216)
  ;:  weld
    (expect-eq !>(400) !>(status.outcome.empty))
    (expect-eq !>(400) !>(status.outcome.many))
  ==
--
