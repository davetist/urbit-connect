::  Local resource grants and explicitly registered native callbacks.
/-  c=connect
/+  cc=connect-codec, ca=connect-auth
|%
++  loopback
  |=  value=@t
  ^-  ?
  =/  chars=tape  (trip value)
  ?.  (levy chars |=(ch=@tD &((gte ch 33) (lte ch 126) !=(ch '#') !=(ch '?') !=(ch '@') !=(ch 92))))  |
  =/  rest=(unit tape)
    ?:  =('http://localhost:' (crip (scag 17 chars)))  `(slag 17 chars)
    ?:  =('http://127.0.0.1:' (crip (scag 17 chars)))  `(slag 17 chars)
    ~
  ?~  rest  |
  :: Parse the port followed by an optional absolute path; never a wildcard.
  =/  split  (find "/" u.rest)
  =/  digits  ?~(split u.rest (scag u.split u.rest))
  =/  parsed  (rush (crip digits) dem)
  ?~  parsed  |
  &((gte u.parsed 1.024) (lte u.parsed 65.535) =((ud:cc u.parsed) (crip digits)))
++  private-callback
  |=  value=@t
  ^-  ?
  =/  chars=tape  (trip value)
  ?.  (levy chars |=(ch=@tD &((gte ch 33) (lte ch 126) !=(ch '#') !=(ch '?') !=(ch '@') !=(ch 92))))  |
  =/  split  (find "://" chars)
  ?~  split  |
  =/  scheme=tape  (scag u.split chars)
  ?.  (levy scheme |=(ch=@tD |(&((gte ch 'a') (lte ch 'z')) &((gte ch '0') (lte ch '9')) =(ch '+') =(ch '-') =(ch '.'))))  |
  ?~  scheme  |
  ?.  &((gth (lent scheme) 0) (lte (lent scheme) 64) (gth (lent chars) (add u.split 3)))  |
  ?.  &((gte i.scheme 'a') (lte i.scheme 'z'))  |
  !(~(has in (silt ~['http' 'https' 'file' 'data' 'javascript' 'ws' 'wss' 'ftp'])) (crip scheme))
++  scope-name
  |=  value=@t
  ^-  ?
  ?&  (gth (met 3 value) 0)
      (lte (met 3 value) 64)
      !=('documents:' (crip (scag 10 (trip value))))
      (levy (trip value) |=(ch=@tD |(&((gte ch 'a') (lte ch 'z')) &((gte ch '0') (lte ch '9')) =(ch ':') =(ch '_') =(ch '-') =(ch '.'))))
  ==
++  decode
  |=  value=json
  ^-  integration:c
  ?>  (keys:cc value (silt ~['agent' 'scopes' 'redirectURIs']))
  =/  agent  (text:cc (field:cc 'agent' value))
  ?>  &((name:cc agent) !=(agent 'connect'))
  =/  scope-json  (field:cc 'scopes' value)
  =/  redirects-json  (field:cc 'redirectURIs' value)
  ?>  &(?=([%a *] scope-json) ?=([%a *] redirects-json))
  =/  allowed  (turn p.scope-json text:cc)
  =/  redirects  (turn p.redirects-json text:cc)
  ?>  &((gth (lent allowed) 0) (lte (lent allowed) 8) (gth (lent redirects) 0) (lte (lent redirects) 8))
  ?>  (levy allowed scope-name)
  ?>  (levy redirects |=(r=@t &((lte (met 3 r) 256) |((valid-redirect:ca r) (loopback r) (private-callback r)))))
  [`@tas`agent (silt allowed) (silt redirects)]
++  scopes
  |=  [raw=@t allowed=(set @t)]
  ^-  (unit (set @t))
  =/  parsed  (rush raw (more ace (plus (shim 33 126))))
  ?~  parsed  ~
  =/  values  (turn u.parsed crip)
  ?.  (levy values |=(s=@t (~(has in allowed) s)))  ~
  `(silt values)
++  live
  |=  [state=state-2:c resource=@tas id=@t now=@da]
  ^-  json
  =/  found  (~(get by sessions.auth.state) id)
  ?~  found  ~
  =/  s  u.found
  =/  policy  (~(get by integrations.state) client.s)
  =/  app  (~(get by clients.auth.state) client.s)
  =/  space  (~(get by spaces.state) namespace.s)
  ?.  &(?=(^ policy) ?=(^ app) ?=(^ space))  ~
  ?.  &(=(resource agent.u.policy) enabled.u.app (lth now expires.s) =(epoch.s epoch.u.space))  ~
  (grant:ca s)
--
