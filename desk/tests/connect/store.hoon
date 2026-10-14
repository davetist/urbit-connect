/-  c=connect
/+  *test, cs=connect-store, cc=connect-codec
=/  auth  ^-  authority:c  ['test' 1 & & &]
=/  now  ~2026.10.12
=/  one  ^-  operation:c
  [%put ['lists' '11111111-1111-4111-8111-111111111111'] (object:cc ~[['title' [%s 'Personal']]]) ~]
=/  req  ^-  mutation:c
  ['aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa' 0x1 ~[one]]
|%
++  first  (mutate:cs empty:cs auth now req 16.777.216)
++  test-create-read-update-delete
  =/  made  first
  =/  row  (~(get by records.next.made) key.one)
  ;:  weld
    (expect-eq !>(200) !>(status.outcome.made))
    (expect-eq !>(1) !>(revision.next.made))
    (expect-eq !>(%.y) !>(?=(^ row)))
  ==
++  test-atomic-batch-conflict
  =/  made  first
  =/  bad=operation:c  one(key ['lists' '22222222-2222-4222-8222-222222222222'])
  =/  result  (mutate:cs next.made auth now req(id 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', operations ~[bad one]) 16.777.216)
  ;:  weld
    (expect-eq !>(409) !>(status.outcome.result))
    (expect-eq !>(next.made) !>(next.result))
  ==
++  test-same-request-same-result
  =/  made  first
  =/  again  (mutate:cs next.made auth now req 16.777.216)
  ;:  weld
    (expect-eq !>(200) !>(status.outcome.again))
    (expect-eq !>(made) !>(again))
  ==
++  test-changed-body-same-request-rejected
  =/  made  first
  =/  again  (mutate:cs next.made auth now req(digest 0x2) 16.777.216)
  (expect-eq !>(409) !>(status.outcome.again))
++  test-duplicate-target-rejected
  =/  result  (mutate:cs empty:cs auth now req(operations ~[one one]) 16.777.216)
  (expect-eq !>(400) !>(status.outcome.result))
++  test-reauthenticated-retry-recovers-receipt
  =/  made  first
  =/  again  (mutate:cs next.made auth now req 16.777.216)
  ;:  weld
    (expect-eq !>(200) !>(status.outcome.again))
    (expect-eq !>(outcome.made) !>(outcome.again))
  ==
++  test-permissions-before-receipt
  =/  made  first
  =/  denied  (mutate:cs next.made auth(write |) now req 16.777.216)
  (expect-eq !>(403) !>(status.outcome.denied))
++  test-epoch-mismatch
  =/  denied  (mutate:cs empty:cs auth(epoch 2) now req 16.777.216)
  (expect-eq !>(401) !>(status.outcome.denied))
--
