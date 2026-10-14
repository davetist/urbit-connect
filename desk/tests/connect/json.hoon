/+  *test, cj=connect-json
|%
++  test-reject-duplicate-keys
  (expect-eq !>(~) !>((parse:cj '{"x":1,"x":2}')))
++  test-reject-escaped-duplicate-keys
  (expect-eq !>(~) !>((parse:cj '{"a":1,"\\u0061":2}')))
++  test-reject-unsafe-integer
  (expect-eq !>(~) !>((parse:cj '{"n":9007199254740993}')))
++  test-reject-unsafe-exponent-integer
  (expect-eq !>(~) !>((parse:cj '{"n":9.007199254740993e15}')))
++  test-reject-nonfinite
  (expect-eq !>(~) !>((parse:cj '{"n":1e9999}')))
++  test-reject-deep-json
  =/  text=@t  (rap 3 (weld (reap 17 '[') (weld ~['0'] (reap 17 ']'))))
  (expect-eq !>(~) !>((parse:cj text)))
++  test-reject-trailing-input
  (expect-eq !>(~) !>((parse:cj '{} []')))
++  test-accept-nested-objects-and-unicode
  =/  text=@t  '{"one":{"x":1},"two":{"x":2},"s":"a\\u00f1o","n":1.25}'
  (expect-eq !>((de:json:html text)) !>((parse:cj text)))
++  test-accept-safe-integer
  =/  text=@t  '{"n":9007199254740991}'
  (expect-eq !>((de:json:html text)) !>((parse:cj text)))
++  test-quoted-braces-do-not-affect-depth
  =/  text=@t  '{"s":"[[[[[[[[[[[[[[[[[[[["}'
  (expect-eq !>((de:json:html text)) !>((parse:cj text)))
--
