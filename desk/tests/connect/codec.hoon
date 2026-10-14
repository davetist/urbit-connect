/+  *test, cc=connect-codec
|%
++  test-large-revision-is-exact-decimal-string
  (expect-eq !>([%s '9007199254740993']) !>((decimal:cc 9.007.199.254.740.993)))
++  test-revision-roundtrip
  (expect-eq !>(9.007.199.254.740.993) !>((revision:cc [%s '9007199254740993'])))
++  test-names-reject-traversal
  %-  expect-eq
  :-  !>(~[| | | | | &])
  !>((turn ~['' 'a/b' '..' 'a%2fb' 'é' 'todo-lists-2'] name:cc))
++  test-uuid-rejects-uppercase
  ;:  weld
    (expect-eq !>(|) !>((uuid:cc 'AAAAAAAA-aaaa-4aaa-8aaa-aaaaaaaaaaaa')))
    (expect-eq !>(&) !>((uuid:cc 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')))
  ==
++  test-namespace-cannot-be-selected-by-payload
  =/  value  (object:cc ~[['requestId' [%s 'a']] ['operations' [%a ~]] ['namespace' [%s 'victim']]])
  (expect-eq !>(|) !>((keys:cc value (silt ~['requestId' 'operations']))))
--
