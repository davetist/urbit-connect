/+  *test, ce=connect-entry
|%
++  test-anonymous-eyre-response-watch-is-allowed
  =/  incoming=bitt:gall  (~(put by *bitt:gall) ~[/eyre/watch-response/request /http-server] [~nec /http-response/request])
  (expect-eq !>(%.y) !>((http-watch:ce incoming ~nec /http-response/request)))
++  test-direct-gall-watch-cannot-observe-http-response
  =/  incoming=bitt:gall  (~(put by *bitt:gall) ~[/gall/sys/req/~nec/connect /ames] [~nec /http-response/request])
  (expect-eq !>(%.n) !>((http-watch:ce incoming ~nec /http-response/request)))
++  test-eyre-channel-subscription-is-not-direct-http
  =/  incoming=bitt:gall  (~(put by *bitt:gall) ~[/eyre/channel/request /http-server] [~zod /http-response/request])
  (expect-eq !>(%.n) !>((http-watch:ce incoming ~zod /http-response/request)))
++  test-forged-source-and-response-id-are-rejected
  =/  incoming=bitt:gall  (~(put by *bitt:gall) ~[/eyre/watch-response/request /http-server] [~nec /http-response/request])
  ;:  weld
    (expect-eq !>(%.n) !>((http-watch:ce incoming ~zod /http-response/request)))
    (expect-eq !>(%.n) !>((http-watch:ce incoming ~nec /http-response/other)))
    (expect-eq !>(%.n) !>((http-watch:ce *bitt:gall ~nec /http-response/request)))
  ==
++  test-second-untrusted-subscriber-is-rejected
  =/  incoming=bitt:gall  (~(put by *bitt:gall) ~[/eyre/watch-response/request /http-server] [~nec /http-response/request])
  =.  incoming  (~(put by incoming) ~[/gall/sys/req/~nec/connect /ames] [~nec /http-response/request])
  (expect-eq !>(%.n) !>((http-watch:ce incoming ~nec /http-response/request)))
--
