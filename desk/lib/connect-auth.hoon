/-  c=connect
/+  cc=connect-codec
|%
++  challenge
  |=  verifier=@t
  ^-  @t
  =/  raw  (trip (en:base64:mimes:html [32 (shax verifier)]))
  %-  crip
  %+  turn  (skim raw |=(ch=@tD !=(ch '=')))
  |=  ch=@tD
  ?:(=(ch '+') '-' ?:(=(ch '/') '_' ch))
++  valid-verifier
  |=  value=@t
  ^-  ?
  =/  chars  (trip value)
  ?.  &((gte (lent chars) 43) (lte (lent chars) 128))  |
  %+  levy  chars
  |=  ch=@tD
  |(&((gte ch 'a') (lte ch 'z')) &((gte ch 'A') (lte ch 'Z')) &((gte ch '0') (lte ch '9')) =(ch '-') =(ch '_') =(ch '.') =(ch '~'))
++  scopes
  |=  raw=@t
  ^-  (unit (set @t))
  =/  parsed  (rush raw (more ace (plus ;~(pose low col))))
  ?~  parsed  ~
  =/  values  (turn u.parsed crip)
  ?.  (levy values |=(s=@t |(=(s 'documents:read') =(s 'documents:write') =(s 'documents:delete'))))  ~
  `(silt values)
++  authority
  |=  value=session:c
  ^-  authority:c
  :*  namespace.value  epoch.value
      (~(has in scopes.value) 'documents:read')
      (~(has in scopes.value) 'documents:write')
      (~(has in scopes.value) 'documents:delete')
  ==
++  grant
  |=  value=session:c
  ^-  json
  %-  object:cc
  :~  ['id' [%s id.value]]  ['sessionId' [%s id.value]]
      ['clientId' [%s client.value]]  ['namespace' [%s namespace.value]]
      ['namespaceEpoch' (decimal:cc epoch.value)]
      ['scopes' [%a (turn ~(tap in scopes.value) string:cc)]]
  ==
++  access
  |=  [db=auth-state:c token=@t now=@da]
  ^-  (unit session:c)
  =/  digest  (shax token)
  =/  matches
    %+  skim  ~(val by sessions.db)
    |=  s=session:c
    &(=(access.s digest) (lth now access-expires.s) (lth now expires.s))
  ?~(matches ~ `i.matches)
++  clean
  |=  [db=auth-state:c now=@da]
  ^-  auth-state:c
  =.  pending.db
    (malt (skim ~(tap by pending.db) |=([p=@t q=authorization:c] (gth expires.q now))))
  =.  codes.db
    (malt (skim ~(tap by codes.db) |=([p=@ux q=code:c] (gth expires.q now))))
  =.  sessions.db
    (malt (skim ~(tap by sessions.db) |=([p=@t q=session:c] (gth expires.q now))))
  db
++  invalid  ^-  outcome:c
  [400 (object:cc ~[['error' [%s 'invalid_grant']] ['error_description' [%s 'Authorization is invalid or expired']]])]
++  response
  |=  [value=session:c access=@t refresh=@t]
  ^-  outcome:c
  :-  200
  %-  object:cc
  :~  ['access_token' [%s access]]
      ['refresh_token' [%s refresh]]
      ['token_type' [%s 'Bearer']]
      ['expires_in' [%n '600']]
      ['scope' [%s (crip (zing (join " " (turn ~(tap in scopes.value) trip))))]]
      ['grant' (grant value)]
  ==
++  exchange
  |=  [db=auth-state:c secret=@t client=@t redirect=@t verifier=@t now=@da id=@t access=@t refresh=@t]
  ^-  auth-result:c
  =/  work  (clean db now)
  =/  found  (~(get by codes.work) (shax secret))
  ?~  found  [work invalid]
  =/  code  u.found
  =/  req  authorization.code
  ?.  &(=(client client.req) =(redirect redirect.req) (valid-verifier verifier) =((challenge verifier) challenge.req))
    [work invalid]
  =/  registered  (~(get by clients.work) client)
  ?~  registered  [work invalid]
  ?.  enabled.u.registered  [work invalid]
  ?:  (gte (lent ~(tap by sessions.work)) 32)
    [work [429 (object:cc ~[['error' [%s 'temporarily_unavailable']]])]]
  =/  value=session:c
    :*  id  client  namespace.req  epoch.req  scopes.req  label.req
        (shax access)  (add now ~m10)  (shax refresh)  ~
        now  (add now ~d30)  (div now ~m1)  0
    ==
  :-  work(codes (~(del by codes.work) (shax secret)), sessions (~(put by sessions.work) id value))
  (response value access refresh)
++  rotate
  |=  [db=auth-state:c secret=@t client=@t now=@da access=@t refresh=@t]
  ^-  auth-result:c
  =/  work  (clean db now)
  =/  digest  (shax secret)
  =/  matches
    %+  skim  ~(val by sessions.work)
    |=  s=session:c
    &(=(client client.s) |(=(digest refresh.s) (~(has in consumed.s) digest)))
  ?~  matches  [work invalid]
  =/  value  i.matches
  ?:  |((~(has in consumed.value) digest) (gte (lent ~(tap in consumed.value)) 4.096))
    [work(sessions (~(del by sessions.work) id.value)) invalid]
  =/  registered  (~(get by clients.work) client)
  ?~  registered  [work invalid]
  ?.  enabled.u.registered  [work invalid]
  =.  value
    value(access (shax access), access-expires (add now ~m10), refresh (shax refresh), consumed (~(put in consumed.value) digest))
  [work(sessions (~(put by sessions.work) id.value value)) (response value access refresh)]
++  revoke-client
  |=  [db=auth-state:c id=@t]
  ^-  auth-state:c
  =.  sessions.db
    (malt (skim ~(tap by sessions.db) |=([p=@t q=session:c] !=(id client.q))))
  =.  pending.db
    (malt (skim ~(tap by pending.db) |=([p=@t q=authorization:c] !=(id client.q))))
  =.  codes.db
    (malt (skim ~(tap by codes.db) |=([p=@ux q=code:c] !=(id client.authorization.q))))
  db
++  valid-redirect
  |=  value=@t
  ^-  ?
  ?.  &((gte (met 3 value) 8) (lte (met 3 value) 256))  |
  =/  chars  (trip value)
  ?.  (levy chars |=(ch=@tD &((gte ch 33) (lte ch 126) !=(ch '#') !=(ch '?') !=(ch '@') !=(ch 92))))  |
  ?:  =('https://' (crip (scag 8 chars)))  (gth (lent chars) 10)
  =/  scheme  (rush value ;~(sfix (plus ;~(pose low dot hep nud)) ;~(plug col fas (star (shim 33 126)))))
  ?~  scheme  |
  &((lien ^-(tape u.scheme) |=(ch=@tD =(ch '.'))) (gte (mod value 256) 'a') (lte (mod value 256) 'z'))
--
