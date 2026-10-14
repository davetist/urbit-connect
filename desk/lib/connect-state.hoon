/-  c=connect
|%
++  load
  |=  old=vase
  ^-  world:c
  =/  state=state-2:c
    ?:  ?=([%0 *] q.old)
      =/  prior  !<(state-0:c old)
      [%2 instance.prior '' 1 0 *auth-state:c ~ ~ ~]
    ?:  ?=([%1 *] q.old)
      =/  prior  !<(state-1:c old)
      [%2 instance.prior issuer.prior epoch.prior nonce.prior auth.prior spaces.prior csrf.prior ~]
    !<(state-2:c old)
  [state ~ ~]
++  fresh-epoch
  |=  [state=state-2:c entropy=@uv]
  ^-  @ud
  :: Restored counters are not freshness. Use the runtime's entropy with a
  :: domain-separated durable identity/nonce, keeping decimal-string v1 bounds.
  =/  candidate=@ud
    (add 1 (mod (shax (jam ['connect-restore' entropy instance.state nonce.state])) (bex 128)))
  ?:(=(candidate epoch.state) +(candidate) candidate)
--
