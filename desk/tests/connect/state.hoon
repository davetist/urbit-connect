/-  c=connect
/+  *test, ct=connect-state, cs=connect-store
|%
++  test-state-zero-migrates-stable-instance
  =/  old=state-0:c  [%0 'prior-instance']
  =/  loaded  (load:ct !>(old))
  ;:  weld
    (expect-eq !>('prior-instance') !>(instance.state.loaded))
    (expect-eq !>(1) !>(epoch.state.loaded))
    (expect-eq !>(~) !>(snapshots.loaded))
    (expect-eq !>(~) !>(polls.loaded))
  ==
++  test-current-state-preserves-durable-nouns
  =/  receipt=receipt:c  [0x123 ~2026.11.12 [%s 'receipt']]
  =/  key=key:c  ['lists' '11111111-1111-4111-8111-111111111111']
  =/  row=record:c  [key [%o ~] 9 ~2026.10.12]
  =/  space=space:c  [2 9 (~(put by *(map key:c record:c)) key row) ~ (~(put by *(map @t receipt:c)) 'request' receipt) ~ 2]
  =/  old=state-1:c  [%1 'instance' 'https://ship.example/connect' 3 71 *auth-state:c (~(put by *(map @t space:c)) 'app-1' space) ~]
  =/  loaded  (load:ct !>(old))
  (expect-eq !>(spaces.old) !>(spaces.state.loaded))
++  test-unknown-version-is-rejected
  =/  attempt  (mule |.((load:ct !>([%3 'unknown']))))
  (expect-eq !>(%.y) !>(?=(%| -.attempt)))
--
