/-  c=connect
/+  cc=connect-codec, ca=connect-auth, cs=connect-store, ct=connect-state, cj=connect-json, cp=connect-policy, ci=connect-integrations, assets=connect-assets, server
|%
++  headers
  ^-  header-list:http
  :~  ['content-type' 'application/json; charset=utf-8']
      ['cache-control' 'no-store']
      ['x-content-type-options' 'nosniff']
      ['x-frame-options' 'DENY']
      ['referrer-policy' 'no-referrer']
      ['content-security-policy' (crip "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")]
  ==
++  payload
  |=  out=outcome:c
  ^-  simple-payload:http
  =/  head
    ?:  =(status.out 503)  [['retry-after' '1'] headers]
    ?.  =(status.out 429)  headers
    =/  detail  (field:cc 'error' body.out)
    =/  quick  ?:(?=([%o *] detail) =([%s 'poll_capacity'] (field:cc 'code' detail)) |)
    [['retry-after' ?:(quick '1' '60')] headers]
  [[status.out head] `(json-to-octs:server body.out)]
++  lower
  |=  value=@t
  ^-  @t
  %-  crip
  %+  turn  (trip value)
  |=  ch=@tD
  ?:(&((gte ch 'A') (lte ch 'Z')) (add ch 32) ch)
++  header
  |=  [name=@t fields=header-list:http]
  ^-  @t
  =/  found  (skim fields |=([key=@t value=@t] =((lower key) name)))
  ?.  =(1 (lent found))  ''
  ?>  ?=(^ found)
  +.i.found
++  query
  |=  pairs=(list [key=@t value=@t])
  ^-  (map @t @t)
  =/  out  *(map @t @t)
  |-  ^+  out
  ?~  pairs  out
  ?>  !(~(has by out) key.i.pairs)
  $(pairs t.pairs, out (~(put by out) key.i.pairs value.i.pairs))
++  escape  |=(value=@t (crip (en-urlt:html (trip value))))
++  body
  |=  request=inbound-request:eyre
  ^-  @t
  =/  data  body.request.request
  ?~  data  ''
  ?>  =(p.u.data (met 3 q.u.data))
  q.u.data
++  json-body
  |=  request=inbound-request:eyre
  ^-  json
  =/  parsed  (parse-wire:cj (body request))
  ?>  ?=(^ parsed)
  u.parsed
++  origin
  |=  issuer=@t
  ^-  @t
  (crip (scag (sub (lent (trip issuer)) 8) (trip issuer)))
++  account
  |=  [state=state-2:c our=@p]
  ^-  json
  %-  object:cc
  :~  ['issuer' [%s issuer.state]]
      ['instanceId' [%s instance.state]]
      ['ship' [%s (scot %p our)]]
      ['syncEpoch' (decimal:cc epoch.state)]
  ==
++  live-snapshots
  |=  [snapshots=(map @t snapshot:c) auth=auth-state:c now=@da]
  ^-  (map @t snapshot:c)
  %-  malt
  %+  skim  ~(tap by snapshots)
  |=  [p=@t q=snapshot:c]
  &((gth expires.q now) |(=('owner-' (crip (scag 6 (trip session.q)))) (~(has by sessions.auth) session.q)))
++  drain
  |=  [world=world:c now=@da]
  ^-  [next=world:c cards=(list card:agent:gall)]
  =/  remaining  ~(tap by polls.world)
  =/  cards  *(list card:agent:gall)
  |-  ^-  [next=world:c cards=(list card:agent:gall)]
  ?~  remaining  [world cards]
  =/  poll  q.i.remaining
  =/  session  (~(get by sessions.auth.state.world) session.poll)
  =/  space  (~(get by spaces.state.world) namespace.poll)
  =/  result=outcome:c
    ?~  session  [401 (error:cc 'invalid_token' 'Authorization was revoked' ~)]
    ?.  &((gth expires.u.session now) (gth access-expires.u.session now) =(access.u.session access.poll) (~(has in scopes.u.session) 'documents:read'))
      [401 (error:cc 'invalid_token' 'Authorization expired or changed' ~)]
    ?~  space  [401 (error:cc 'epoch_changed' 'Namespace was erased' ~)]
    ?.  =(epoch.u.space epoch.u.session)  [401 (error:cc 'epoch_changed' 'Namespace was erased' ~)]
    (changes-page:cs u.space epoch.state.world after.poll limit.poll)
  =/  ready
    ?:  !=(200 status.result)  &
    |((gte now deadline.poll) !=([%a ~] (field:cc 'batches' body.result)))
  ?.  ready  $(remaining t.remaining)
  =.  polls.world  (~(del by polls.world) rid.poll)
  =/  sent  (give-simple-payload:app:server rid.poll (payload result))
  =/  cancel=card:agent:gall  [%pass /poll/[rid.poll] %arvo %b %rest deadline.poll]
  $(remaining t.remaining, cards (weld cards [cancel sent]))
++  handle
  |=  [world=world:c ctx=context:c]
  ^-  http-result:c
  =/  line  (parse-request-line:server url.request.request.ctx)
  =/  path  site.line
  =/  args  (query args.line)
  =/  method  method.request.request.ctx
  =/  fields  header-list.request.request.ctx
  =/  owner  (owner:cp authenticated.request.ctx local.ctx)
  |^
  route
  ++  route
    ^-  http-result:c
    ?:  =(~['apps' 'connect'] (scag 2 path))
      ?.  =(method %'GET')  (fail 405 'method_not_allowed' 'Use GET')
      =/  file=@t
        ?:  |(=(2 (lent path)) =(path ~['apps' 'connect' '']))  '/apps/connect/index.html'
        =/  prefix  (spat (turn path |=(part=@t `@ta`part)))
        ?~  ext.line  prefix
        (cat 3 prefix (cat 3 '.' u.ext.line))
      =/  found  (~(get by assets:assets) file)
      ?~  found  (fail 404 'not_found' 'Asset does not exist')
      =/  head  (skim headers |=([key=@t value=@t] !=(key 'content-type')))
      [world `[[200 [['content-type' mime.u.found] head]] `(as-octs:mimes:html body.u.found)]]
    ?:  ?=(^ ext.line)  (fail 404 'not_found' 'API paths do not have file extensions')
    =/  allowed
      ?:  =(path ~['connect' 'oauth' 'authorize'])
        (silt ~['response_type' 'client_id' 'redirect_uri' 'scope' 'state' 'code_challenge' 'code_challenge_method' 'device_label'])
      ?:  =(path ~['connect' 'v1' 'changes'])  (silt ~['after' 'wait' 'limit'])
      ?:  |(=(~['connect' 'v1' 'collections'] (scag 3 path)) =(~['connect' 'v1' 'snapshots'] (scag 3 path)) =(~['connect' 'owner' 'v1'] (scag 3 path)))
        (silt ~['page' 'limit'])
      *(set @t)
    ?>  (levy ~(tap in ~(key by args)) |=(key=@t (~(has in allowed) key)))
    ?:  =(path ~['connect' 'v1' 'info'])
      ?.  =(method %'GET')  (fail 405 'method_not_allowed' 'Use GET')
      =/  info
        %-  object:cc
        :~  ['protocolVersion' [%n '1']]
            ['issuer' [%s issuer.state.world]]
            ['instanceId' [%s instance.state.world]]
            ['syncEpoch' (decimal:cc epoch.state.world)]
            ['ship' [%s (scot %p our.ctx)]]
            ['development' [%b development.ctx]]
            ['configured' [%b !=(issuer.state.world '')]]
        ==
      (reply 200 info)
    ?:  =(path ~['connect' 'oauth' 'token'])  token
    ?:  =(path ~['connect' 'oauth' 'authorize'])  authorize
    ?:  =(~['connect' 'owner' 'v1'] (scag 3 path))  owner-route
    ?:  =(~['connect' 'v1'] (scag 2 path))  app-route
    ?:  =(path ~['connect' 'oauth' 'revoke'])  app-route
    (fail 404 'not_found' 'Unknown Connect route')
  ++  reply
    |=  [status=@ud value=json]
    ^-  http-result:c
    [world `(payload status value)]
  ++  fail
    |=  [status=@ud code=@t message=@t]
    (reply status (error:cc code message ~))
  ++  secret
    |=  purpose=@t
    ^-  @t
    (ud:cc (shax (jam [purpose entropy.ctx now.ctx nonce.state.world rid.ctx])))
  ++  oauth-error
    |=  [status=@ud code=@t]
    (reply status (object:cc ~[['error' [%s code]]]))
  ++  token
    ^-  http-result:c
    ?.  =(method %'POST')  (oauth-error 405 'invalid_request')
    ?.  =((header 'content-type' fields) 'application/x-www-form-urlencoded')  (oauth-error 400 'invalid_request')
    =/  form-line  (parse-request-line:server (cat 3 '/?' (body request.ctx)))
    =/  form  (query args.form-line)
    =/  kind  (~(got by form) 'grant_type')
    =/  allowed
      ?:  =(kind 'authorization_code')  (silt ~['grant_type' 'client_id' 'redirect_uri' 'code' 'code_verifier'])
      (silt ~['grant_type' 'client_id' 'refresh_token'])
    ?>  (levy ~(tap in ~(key by form)) |=(key=@t (~(has in allowed) key)))
    =/  client  (~(got by form) 'client_id')
    ?:  (~(has by integrations.state.world) client)  (oauth-error 400 'unauthorized_client')
    =/  access  (secret 'access')
    =/  refresh  (secret 'refresh')
    =/  db  auth.state.world
    =/  result=auth-result:c
      ?:  =(kind 'authorization_code')
        (exchange:ca db (~(got by form) 'code') client (~(got by form) 'redirect_uri') (~(got by form) 'code_verifier') now.ctx (secret 'session') access refresh)
      ?>  =(kind 'refresh_token')
      (rotate:ca db (~(got by form) 'refresh_token') client now.ctx access refresh)
    =.  auth.state.world  next.result
    (reply status.outcome.result body.outcome.result)
  ++  authorize
    ^-  http-result:c
    ?.  =(method %'GET')  (oauth-error 405 'invalid_request')
    ?:  =(issuer.state.world '')  (oauth-error 503 'temporarily_unavailable')
    =/  client-id  (~(got by args) 'client_id')
    =/  registered  (~(get by clients.auth.state.world) client-id)
    ?~  registered  (oauth-error 400 'unauthorized_client')
    ?.  enabled.u.registered  (oauth-error 400 'unauthorized_client')
    =/  redirect  (~(got by args) 'redirect_uri')
    =/  policy  (~(get by integrations.state.world) client-id)
    ?.  ?~(policy =(redirect redirect.u.registered) (~(has in redirects.u.policy) redirect))
      (oauth-error 400 'invalid_request')
    ?.  &(=('code' (~(got by args) 'response_type')) =('S256' (~(got by args) 'code_challenge_method')))
      (oauth-error 400 'invalid_request')
    =/  challenge  (~(got by args) 'code_challenge')
    ?.  &(=(43 (met 3 challenge)) (valid-verifier:ca challenge))  (oauth-error 400 'invalid_request')
    =/  state  (~(got by args) 'state')
    ?.  &((gth (met 3 state) 0) (lte (met 3 state) 128))  (oauth-error 400 'invalid_request')
    =/  scopes
      ?~  policy  (scopes:ca (~(got by args) 'scope'))
      (scopes:ci (~(got by args) 'scope') scopes.u.policy)
    ?~  scopes  (oauth-error 400 'invalid_scope')
    ?.  ?=(^ u.scopes)  (oauth-error 400 'invalid_scope')
    =.  auth.state.world  (clean:ca auth.state.world now.ctx)
    =/  minute  (div now.ctx ~m1)
    =/  prior  (~(get by starts.auth.state.world) client-id)
    =/  count  ?~(prior 0 ?:(=(minute minute.u.prior) count.u.prior 0))
    =/  occupied
      %+  add
        (lent (skim ~(val by pending.auth.state.world) |=(req=authorization:c =(client.req client-id))))
      (lent (skim ~(val by codes.auth.state.world) |=(code=code:c =(client.authorization.code client-id))))
    ?:  |((gte count 30) (gte occupied 4) (gte (add (lent ~(tap by pending.auth.state.world)) (lent ~(tap by codes.auth.state.world))) 32))
      (oauth-error 429 'temporarily_unavailable')
    =/  id  (secret 'pending')
    =/  namespace  namespace.u.registered
    =/  space  (~(got by spaces.state.world) namespace)
    =/  label  (fall (~(get by args) 'device_label') 'Native app')
    ?>  (lte (met 3 label) 64)
    =/  entry=authorization:c  [id client-id redirect namespace epoch.space u.scopes challenge state label (add now.ctx ~m5)]
    =.  pending.auth.state.world  (~(put by pending.auth.state.world) id entry)
    =.  starts.auth.state.world  (~(put by starts.auth.state.world) client-id [minute +(count)])
    [world `[[302 [['location' (cat 3 '/apps/connect/?consent=' (escape id))] headers]] ~]]
  ++  owner-route
    ^-  http-result:c
    ?.  owner  (fail 401 'owner_required' 'Log in as the local ship owner')
    =/  cookie  (header 'cookie' fields)
    ?:  =(cookie '')  (fail 401 'owner_required' 'An owner browser session is required')
    =/  key  (shax cookie)
    =/  segments  (slag 3 path)
    ?:  &(=(method %'GET') =(segments ~['bootstrap']))
      =.  csrf.state.world
        (malt (skim ~(tap by csrf.state.world) |=([p=@ux q=csrf:c] (gth expires.q now.ctx))))
      =.  csrf.state.world
        ?:  |((~(has by csrf.state.world) key) (lth (lent ~(tap by csrf.state.world)) 8))
          csrf.state.world
        =/  oldest
          %-  head
          %+  sort  ~(tap by csrf.state.world)
          |=  [a=[p=@ux q=csrf:c] b=[p=@ux q=csrf:c]]
          (lth expires.q.a expires.q.b)
        (~(del by csrf.state.world) p.oldest)
      =/  csrf  (secret 'csrf')
      =.  csrf.state.world  (~(put by csrf.state.world) key [(shax csrf) (add now.ctx ~m30)])
      (reply 200 (object:cc ~[['csrf' [%s csrf]] ['account' (account state.world our.ctx)] ['configured' [%b !=(issuer.state.world '')]]]))
    ?.  =(method %'GET')
      =/  context  (~(get by csrf.state.world) key)
      ?~  context  (fail 403 'csrf_failed' 'Reload the owner page')
      ?.  &((gth expires.u.context now.ctx) =(token.u.context (shax (header 'x-connect-csrf' fields))))
        (fail 403 'csrf_failed' 'Reload the owner page')
      =/  expected  ?:(=(issuer.state.world '') (cat 3 'https://' (header 'host' fields)) (origin issuer.state.world))
      ?.  =((header 'origin' fields) expected)  (fail 403 'origin_mismatch' 'Owner origin does not match')
      owner-post
    ?:  =(segments ~['clients'])
      (reply 200 (object:cc ~[['clients' [%a (turn ~(val by clients.auth.state.world) client-json)]]]))
    ?:  =(segments ~['sessions'])
      =/  live  (clean:ca auth.state.world now.ctx)
      (reply 200 (object:cc ~[['sessions' [%a (turn ~(val by sessions.live) session-json)]]]))
    ?:  &(=(3 (lent segments)) =('namespaces' (snag 0 segments)) =('documents' (snag 2 segments)))
      =/  space  (~(get by spaces.state.world) (snag 1 segments))
      ?~  space  (fail 404 'not_found' 'Namespace does not exist')
      =/  rows
        %+  sort  ~(val by records.u.space)
        |=  [a=record:c b=record:c]
        ?:  =(collection.key.a collection.key.b)  (aor id.key.a id.key.b)
        (aor collection.key.a collection.key.b)
      =/  offset  (parameter 'page' 0 0 (lent rows))
      =/  limit  (parameter 'limit' 100 1 100)
      =/  selected  (scag limit (slag offset rows))
      =/  next  (add offset (lent selected))
      (reply 200 (object:cc ~[['documents' [%a (turn selected document:cc)]] ['nextPage' ?:((gte next (lent rows)) ~ (decimal:cc next))] ['revision' (decimal:cc revision.u.space)] ['bytes' (numb:enjs:format bytes.u.space)] ['count' (numb:enjs:format (lent rows))]]))
    ?:  &(=(2 (lent segments)) =('snapshots' (snag 0 segments)))
      =/  snapshot  (~(get by snapshots.world) (snag 1 segments))
      ?~  snapshot  (fail 410 'snapshot_expired' 'Start a new snapshot')
      ?.  =(session.u.snapshot (cat 3 'owner-' (ud:cc key)))  (fail 404 'not_found' 'Snapshot does not exist')
      (snapshot-page u.snapshot |)
    ?:  =(2 (lent segments))
      ?:  =('consents' (snag 0 segments))
        =/  pending  (~(get by pending.auth.state.world) (snag 1 segments))
        ?~  pending  (fail 410 'consent_expired' 'This connection request expired')
        ?.  (gth expires.u.pending now.ctx)  (fail 410 'consent_expired' 'This connection request expired')
        =/  app  (~(got by clients.auth.state.world) client.u.pending)
        =/  value
          %-  object:cc
          :~  ['requestId' [%s id.u.pending]]
              ['client' (client-json app)]
              ['scopes' [%a (turn ~(tap in scopes.u.pending) string:cc)]]
              ['label' [%s label.u.pending]]
              ['ship' [%s (scot %p our.ctx)]]
          ==
        (reply 200 value)
      (fail 404 'not_found' 'Unknown owner route')
    (fail 404 'not_found' 'Unknown owner route')
  ++  client-json
    |=  app=client:c
    ^-  json
    =/  policy  (~(get by integrations.state.world) id.app)
    =/  fields=(list [@t json])
      :~  ['id' [%s id.app]]
          ['name' [%s name.app]]
          ['redirectURI' [%s redirect.app]]
          ['namespace' [%s namespace.app]]
          ['enabled' [%b enabled.app]]
          ['development' [%b &]]
      ==
    (object:cc ?~(policy fields [['integration' (object:cc ~[['agent' [%s agent.u.policy]] ['scopes' [%a (turn ~(tap in scopes.u.policy) string:cc)]] ['redirectURIs' [%a (turn ~(tap in redirects.u.policy) string:cc)]]])] fields]))
  ++  session-json
    |=  session=session:c
    ^-  json
    %-  object:cc
    :~  ['grant' (grant:ca session)]
        ['label' [%s label.session]]
        ['createdAt' [%s (timestamp:cc created.session)]]
        ['expiresAt' [%s (timestamp:cc expires.session)]]
    ==
  ++  owner-post
    ^-  http-result:c
    ?.  =(method %'POST')  (fail 405 'method_not_allowed' 'Use POST')
    =/  value  (json-body request.ctx)
    ?>  ?=([%o *] value)
    =/  segments  (slag 3 path)
    ?:  =(segments ~['configure'])
      ?>  (keys:cc value (silt ~['issuer']))
      =/  issuer  (text:cc (field:cc 'issuer' value))
      =/  expected  (cat 3 (header 'origin' fields) '/connect')
      ?.  &(=(issuer expected) =('https://' (crip (scag 8 (trip issuer)))) (lte (met 3 issuer) 256))
        (fail 400 'invalid_issuer' 'Issuer must be this exact HTTPS origin followed by /connect')
      ?:  &(!=(issuer.state.world '') !=(issuer.state.world issuer))
        (fail 409 'issuer_already_set' 'Changing issuer requires a new explicit deployment')
      =.  issuer.state.world  issuer
      (reply 200 (account state.world our.ctx))
    ?:  =(segments ~['clients'])
      ?>  (keys:cc value (silt ~['id' 'name' 'redirectURI' 'integration']))
      =/  id  (text:cc (field:cc 'id' value))
      =/  name  (text:cc (field:cc 'name' value))
      =/  redirect  (text:cc (field:cc 'redirectURI' value))
      ?>  &((name:cc id) (gth (met 3 name) 0) (lte (met 3 name) 80))
      =/  policy-json  (~(get by p.value) 'integration')
      =/  policy=(unit integration:c)
        ?~  policy-json  ~
        `(decode:ci u.policy-json)
      ?>  ?~(policy (valid-redirect:ca redirect) (~(has in redirects.u.policy) redirect))
      ?:  (~(has by clients.auth.state.world) id)  (fail 409 'client_exists' 'This client is already registered')
      =/  namespace  (cat 3 'app-' (ud:cc nonce.state.world))
      =/  app=client:c  [id name redirect namespace & now.ctx]
      =?  integrations.state.world  ?=(^ policy)
        (~(put by integrations.state.world) id u.policy)
      =.  clients.auth.state.world  (~(put by clients.auth.state.world) id app)
      =.  spaces.state.world  (~(put by spaces.state.world) namespace empty:cs)
      (reply 200 (client-json app))
    ?:  &(=(2 (lent segments)) =('consents' (snag 0 segments)))
      ?>  (keys:cc value (silt ~['decision']))
      =/  pending  (~(get by pending.auth.state.world) (snag 1 segments))
      ?~  pending  (fail 410 'consent_expired' 'This connection request expired')
      =/  req  u.pending
      ?.  (gth expires.req now.ctx)  (fail 410 'consent_expired' 'This connection request expired')
      =/  app  (~(got by clients.auth.state.world) client.req)
      ?.  enabled.app  (fail 410 'consent_expired' 'This client was disabled')
      =/  space  (~(got by spaces.state.world) namespace.req)
      ?.  =(epoch.req epoch.space)  (fail 410 'consent_expired' 'The namespace changed')
      =/  decision  (text:cc (field:cc 'decision' value))
      ?>  |(=(decision 'approve') =(decision 'deny'))
      =.  pending.auth.state.world  (~(del by pending.auth.state.world) id.req)
      =/  suffix=@t
        ?:  =(decision 'deny')  'error=access_denied'
        =/  code  (secret 'code')
        (cat 3 'code=' (escape code))
      =.  codes.auth.state.world
        ?:  =(decision 'deny')  codes.auth.state.world
        (~(put by codes.auth.state.world) (shax (secret 'code')) [req (add now.ctx ~s60)])
      =/  redirect  (crip "{(trip redirect.req)}?{(trip suffix)}&state={(trip (escape state.req))}")
      (reply 200 (object:cc ~[['redirect' [%s redirect]]]))
    ?:  &(=(3 (lent segments)) =('clients' (snag 0 segments)) =('remove' (snag 2 segments)))
      ?>  (keys:cc value (silt ~['confirmClientId' 'confirmNamespace']))
      =/  id  (snag 1 segments)
      =/  app  (~(get by clients.auth.state.world) id)
      ?~  app  (fail 404 'not_found' 'Client does not exist')
      ?>  &(=(id (text:cc (field:cc 'confirmClientId' value))) =(namespace.u.app (text:cc (field:cc 'confirmNamespace' value))))
      =.  auth.state.world  (revoke-client:ca auth.state.world id)
      =.  integrations.state.world  (~(del by integrations.state.world) id)
      =.  clients.auth.state.world  (~(del by clients.auth.state.world) id)
      =.  spaces.state.world  (~(del by spaces.state.world) namespace.u.app)
      =.  snapshots.world
        (malt (skim ~(tap by snapshots.world) |=([p=@t q=snapshot:c] !=(namespace.u.app namespace.q))))
      (reply 200 (object:cc ~[['removed' [%b &]]]))
    ?:  &(=(2 (lent segments)) =('clients' (snag 0 segments)))
      ?>  (keys:cc value (silt ~['name' 'enabled']))
      =/  id  (snag 1 segments)
      =/  app  (~(get by clients.auth.state.world) id)
      ?~  app  (fail 404 'not_found' 'Client does not exist')
      =/  changed-name  (~(get by p.value) 'name')
      =/  changed-enabled  (~(get by p.value) 'enabled')
      ?>  |(?=(^ changed-name) ?=(^ changed-enabled))
      =/  name  ?~(changed-name name.u.app (text:cc u.changed-name))
      =/  enabled=json  ?~(changed-enabled [%b enabled.u.app] u.changed-enabled)
      ?>  ?=([%b *] enabled)
      ?>  &((gth (met 3 name) 0) (lte (met 3 name) 80))
      =.  clients.auth.state.world  (~(put by clients.auth.state.world) id u.app(name name, enabled p.enabled))
      =.  auth.state.world  ?:(p.enabled auth.state.world (revoke-client:ca auth.state.world id))
      =.  snapshots.world  (live-snapshots snapshots.world auth.state.world now.ctx)
      (reply 200 (client-json u.app(name name, enabled p.enabled)))
    ?:  =(segments ~['revoke'])
      ?>  (keys:cc value (silt ~['sessionId' 'clientId']))
      =/  fields  p.value
      =/  session  (~(get by fields) 'sessionId')
      =/  client  (~(get by fields) 'clientId')
      ?>  !=(?=(^ session) ?=(^ client))
      =.  auth.state.world
        ?~  session  (revoke-client:ca auth.state.world (text:cc (need client)))
        auth.state.world(sessions (~(del by sessions.auth.state.world) (text:cc u.session)))
      =.  snapshots.world  (live-snapshots snapshots.world auth.state.world now.ctx)
      (reply 200 (object:cc ~[['revoked' [%b &]]]))
    ?:  &(=(3 (lent segments)) =('namespaces' (snag 0 segments)))
      =/  namespace  (snag 1 segments)
      =/  space  (~(get by spaces.state.world) namespace)
      ?~  space  (fail 404 'not_found' 'Namespace does not exist')
      =/  db  u.space
      ?:  =('mutations' (snag 2 segments))
        =/  request  (decode-mutation:cc (body request.ctx))
        =/  result  (mutate:cs db [namespace epoch.db & & &] now.ctx request)
        =.  spaces.state.world  (~(put by spaces.state.world) namespace next.result)
        (reply status.outcome.result body.outcome.result)
      ?:  =('snapshots' (snag 2 segments))
        ?>  (keys:cc value *(set @t))
        (make-snapshot db namespace (cat 3 'owner-' (ud:cc (shax (header 'cookie' fields)))))
      ?:  =('erase' (snag 2 segments))
        ?>  (keys:cc value (silt ~['confirmNamespace']))
        ?>  =(namespace (text:cc (field:cc 'confirmNamespace' value)))
        =/  apps  (skim ~(val by clients.auth.state.world) |=(app=client:c =(namespace namespace.app)))
        =.  auth.state.world
          =/  auth  auth.state.world
          |-  ^+  auth
          ?~  apps  auth
          $(apps t.apps, auth (revoke-client:ca auth id.i.apps))
        =.  spaces.state.world  (~(put by spaces.state.world) namespace [+(epoch.db) 0 ~ ~ ~ ~ 0])
        =.  snapshots.world  (malt (skim ~(tap by snapshots.world) |=([p=@t q=snapshot:c] !=(namespace namespace.q))))
        (reply 200 (object:cc ~[['namespaceEpoch' (decimal:cc +(epoch.db))]]))
      (fail 404 'not_found' 'Unknown namespace operation')
    ?:  =(segments ~['restore-epoch'])
      ?>  (keys:cc value (silt ~['confirmInstanceId']))
      ?>  =(instance.state.world (text:cc (field:cc 'confirmInstanceId' value)))
      =.  epoch.state.world  (fresh-epoch:ct state.world entropy.ctx)
      =.  auth.state.world  auth.state.world(pending ~, codes ~, sessions ~)
      =.  snapshots.world  ~
      =.  spaces.state.world
        %-  malt
        %+  turn  ~(tap by spaces.state.world)
        |=  [p=@t q=space:c]
        [p q(receipts ~)]
      (reply 200 (account state.world our.ctx))
    ?:  =(segments ~['imports' 'validate'])
      ?>  (keys:cc value (silt ~['namespace' 'mode' 'export']))
      =/  namespace  (text:cc (field:cc 'namespace' value))
      =/  db  (~(get by spaces.state.world) namespace)
      ?~  db  (fail 404 'not_found' 'Namespace does not exist')
      =/  mode  (text:cc (field:cc 'mode' value))
      ?>  |(=(mode 'create') =(mode 'compare-and-swap'))
      =/  envelope  (field:cc 'export' value)
      ?>  (keys:cc envelope (silt ~['formatVersion' 'source' 'namespace' 'collections']))
      ?>  =([%n '1'] (field:cc 'formatVersion' envelope))
      =/  source  (field:cc 'source' envelope)
      ?>  (keys:cc source (silt ~['issuer' 'instanceId' 'ship' 'syncEpoch']))
      =/  source-issuer  (text:cc (field:cc 'issuer' source))
      ?>  =('https://' (crip (scag 8 (trip source-issuer))))
      ?>  (gth (met 3 (text:cc (field:cc 'instanceId' source))) 0)
      ?>  ?=(^ (slaw %p (text:cc (field:cc 'ship' source))))
      ?>  (gth (revision:cc (field:cc 'syncEpoch' source)) 0)
      ?>  (name:cc (text:cc (field:cc 'namespace' envelope)))
      =/  collections  (field:cc 'collections' envelope)
      ?>  ?=([%o *] collections)
      =/  groups  ~(tap by p.collections)
      =/  operations  *(list json)
      =/  conflicts  *(list json)
      |-  ^-  http-result:c
      ?~  groups
        (reply 200 (object:cc ~[['count' (numb:enjs:format (lent operations))] ['operations' [%a (flop operations)]] ['conflicts' [%a (flop conflicts)]]]))
      =/  collection  p.i.groups
      ?>  (name:cc collection)
      =/  rows  q.i.groups
      ?>  ?=([%a *] rows)
      =/  entries  p.rows
      =/  [ops=(list json) issues=(list json)]
        =/  ops  operations
        =/  issues  conflicts
        |-  ^-  [(list json) (list json)]
        ?~  entries  [ops issues]
        =/  doc  i.entries
        ?>  (keys:cc doc (silt ~['id' 'collection' 'data' 'revision' 'updatedAt']))
        =/  id  (text:cc (field:cc 'id' doc))
        ?>  &((uuid:cc id) =(collection (text:cc (field:cc 'collection' doc))))
        ?>  (gth (revision:cc (field:cc 'revision' doc)) 0)
        ?>  (gth (met 3 (text:cc (field:cc 'updatedAt' doc))) 0)
        ?>  !(lien ops |=(op=json &(=(id (text:cc (field:cc 'id' op))) =(collection (text:cc (field:cc 'collection' op))))))
        =/  data  (field:cc 'data' doc)
        ?>  ?=([%o *] data)
        ?>  (bounded:cj (en:json:html data))
        =/  current  (~(get by records.u.db) [collection id])
        =/  dead  (~(get by tombstones.u.db) [collection id])
        =/  expected=json
          ?:  =(mode 'create')  ~
          ?~  current  ~
          (decimal:cc revision.u.current)
        =/  op  (object:cc ~[['type' [%s 'put']] ['collection' [%s collection]] ['id' [%s id]] ['expectedRevision' expected] ['data' data]])
        =.  issues
          ?:  &(=(mode 'create') ?=(^ current))  [doc issues]
          ?~  dead  issues
          [doc issues]
        $(entries t.entries, ops [op ops])
      $(groups t.groups, operations ops, conflicts issues)
    ?:  =(segments ~['imports' 'apply'])
      ?>  (keys:cc value (silt ~['namespace' 'mutation']))
      =/  namespace  (text:cc (field:cc 'namespace' value))
      =/  db  (~(get by spaces.state.world) namespace)
      ?~  db  (fail 404 'not_found' 'Namespace does not exist')
      =/  request  (decode-mutation:cc (en:json:html (field:cc 'mutation' value)))
      =.  digest.request  (shax (body request.ctx))
      =/  result  (mutate:cs u.db [namespace epoch.u.db & & &] now.ctx request)
      =.  spaces.state.world  (~(put by spaces.state.world) namespace next.result)
      (reply status.outcome.result body.outcome.result)
    (fail 404 'not_found' 'Unknown owner operation')
  ++  app-route
    ^-  http-result:c
    =/  authorization  (header 'authorization' fields)
    ?.  =('Bearer ' (crip (scag 7 (trip authorization))))  (fail 401 'invalid_token' 'Authorization required')
    =/  token  (crip (slag 7 (trip authorization)))
    =/  found  (access:ca auth.state.world token now.ctx)
    ?~  found  (fail 401 'invalid_token' 'Authorization required')
    =/  session  u.found
    ?:  (~(has by integrations.state.world) client.session)
      (fail 401 'invalid_token' 'Authorization required')
    =/  app  (~(get by clients.auth.state.world) client.session)
    ?~  app  (fail 401 'invalid_token' 'Authorization required')
    ?.  enabled.u.app  (fail 401 'invalid_token' 'Authorization required')
    =/  space  (~(get by spaces.state.world) namespace.session)
    ?~  space  (fail 401 'invalid_token' 'Authorization required')
    =/  db  u.space
    ?.  =(epoch.db epoch.session)  (fail 401 'epoch_changed' 'Namespace was erased')
    =/  auth  (authority:ca session)
    ?:  =(path ~['connect' 'oauth' 'revoke'])
      ?.  =(method %'POST')  (fail 405 'method_not_allowed' 'Use POST')
      =.  sessions.auth.state.world  (~(del by sessions.auth.state.world) id.session)
      =.  snapshots.world  (live-snapshots snapshots.world auth.state.world now.ctx)
      (reply 200 (object:cc ~[['revoked' [%b &]]]))
    ?:  =(path ~['connect' 'v1' 'identity'])
      ?.  =(method %'GET')  (fail 405 'method_not_allowed' 'Use GET')
      (reply 200 (object:cc ~[['account' (account state.world our.ctx)] ['grant' (grant:ca session)]]))
    =/  minute  (div now.ctx ~m1)
    =/  count  ?:(=(minute minute.session) requests.session 0)
    ?:  &(=(4 (lent path)) =(~['connect' 'v1' 'snapshots'] (scag 3 path)))
      =/  throttled  (gte count 120)
      =.  sessions.auth.state.world
        ?:  throttled  sessions.auth.state.world
        (~(put by sessions.auth.state.world) id.session session(minute minute, requests +(count)))
      ?.  read.auth  (fail 403 'insufficient_scope' 'Read permission required')
      ?.  =(method %'GET')  (fail 405 'method_not_allowed' 'Use GET')
      =/  found  (~(get by snapshots.world) (snag 3 path))
      ?~  found  (fail 410 'snapshot_expired' 'Start a new snapshot')
      ?.  &(=(session.u.found id.session) =(namespace.u.found namespace.session))
        (fail 404 'not_found' 'Snapshot does not exist')
      (snapshot-page u.found throttled)
    ?:  (gte count 120)  (fail 429 'rate_limited' 'Wait before making more document requests')
    =.  sessions.auth.state.world  (~(put by sessions.auth.state.world) id.session session(minute minute, requests +(count)))
    ?:  =(path ~['connect' 'v1' 'mutations'])
      ?.  =(method %'POST')  (fail 405 'method_not_allowed' 'Use POST')
      =/  request  (decode-mutation:cc (body request.ctx))
      =/  result  (mutate:cs db auth now.ctx request)
      =.  spaces.state.world  (~(put by spaces.state.world) namespace.session next.result)
      (reply status.outcome.result body.outcome.result)
    ?.  read.auth  (fail 403 'insufficient_scope' 'Read permission required')
    ?:  &(=(5 (lent path)) =(~['connect' 'v1' 'collections'] (scag 3 path)) =('documents' (snag 4 path)))
      ?.  =(method %'GET')  (fail 405 'method_not_allowed' 'Use GET')
      =/  collection  (snag 3 path)
      ?>  (name:cc collection)
      =/  rows  (sort (skim ~(val by records.db) |=(row=record:c =(collection collection.key.row))) |=([a=record:c b=record:c] (aor id.key.a id.key.b)))
      =/  limit  (parameter 'limit' 100 1 100)
      =/  page  (~(get by args) 'page')
      =/  offset=@ud
        ?~  page  0
        =/  parsed  (rush u.page ;~(plug (bass 10 (plus dit)) ;~(pfix col (bass 10 (plus dit))) ;~(pfix col (bass 10 (plus dit))) ;~(pfix col (bass 10 (plus dit)))))
        ?>  ?=(^ parsed)
        =/  [global=@ud epoch=@ud revision=@ud offset=@ud]  u.parsed
        ?>  &(=(global epoch.state.world) =(epoch epoch.db) =(revision revision.db))
        offset
      =/  selected  (scag limit (slag offset rows))
      =/  next  (add offset (lent selected))
      =/  page-json=json
        ?:  (gte next (lent rows))  ~
        [%s (crip "{(trip (cursor:cs epoch.state.world epoch.db revision.db))}:{(trip (ud:cc next))}")]
      (reply 200 (object:cc ~[['documents' [%a (turn selected document:cc)]] ['nextPage' page-json]]))
    ?:  &(=(6 (lent path)) =(~['connect' 'v1' 'collections'] (scag 3 path)) =('documents' (snag 4 path)))
      ?.  =(method %'GET')  (fail 405 'method_not_allowed' 'Use GET')
      =/  key=key:c  [(snag 3 path) (snag 5 path)]
      ?>  &((name:cc collection.key) (uuid:cc id.key))
      =/  row  (~(get by records.db) key)
      ?~  row  (fail 404 'not_found' 'Document does not exist')
      (reply 200 (document:cc u.row))
    ?:  =(path ~['connect' 'v1' 'snapshots'])
      ?.  =(method %'POST')  (fail 405 'method_not_allowed' 'Use POST')
      ?>  (keys:cc (json-body request.ctx) *(set @t))
      (make-snapshot db namespace.session id.session)
    ?:  =(path ~['connect' 'v1' 'changes'])
      ?.  =(method %'GET')  (fail 405 'method_not_allowed' 'Use GET')
      =/  after  (~(got by args) 'after')
      =/  limit  (parameter 'limit' 100 1 100)
      =/  wait  (parameter 'wait' 0 0 25)
      =/  result  (changes-page:cs db epoch.state.world after limit)
      ?.  =(200 status.result)  (reply status.result body.result)
      =/  batches  (field:cc 'batches' body.result)
      ?.  &(=(batches [%a ~]) (gth wait 0))  (reply 200 body.result)
      ?:  (lien ~(val by polls.world) |=(p=poll:c =(session.p id.session)))
        (fail 429 'poll_capacity' 'One outstanding poll is allowed per session')
      =/  deadline  (min access-expires.session (add now.ctx (mul wait ~s1)))
      =.  polls.world  (~(put by polls.world) rid.ctx [rid.ctx id.session namespace.session after limit access.session source.ctx deadline])
      [world ~]
    (fail 404 'not_found' 'Unknown document route')
  ++  parameter
    |=  [name=@t default=@ud minimum=@ud maximum=@ud]
    ^-  @ud
    =/  value  (~(get by args) name)
    ?~  value  default
    =/  number  (revision:cc [%s u.value])
    ?>  &((gte number minimum) (lte number maximum))
    number
  ++  make-snapshot
    |=  [db=space:c namespace=@t session=@t]
    ^-  http-result:c
    =.  snapshots.world  (live-snapshots snapshots.world auth.state.world now.ctx)
    =.  snapshots.world
      %-  malt
      %+  skim  ~(tap by snapshots.world)
      |=  [p=@t q=snapshot:c]
      &((gth expires.q now.ctx) !=(session session.q))
    ?:  (gte (lent ~(tap by snapshots.world)) 4)  (fail 429 'snapshot_capacity' 'Four snapshots are already active')
    ?:  (gte (lent (skim ~(val by snapshots.world) |=(snap=snapshot:c =(namespace namespace.snap)))) 2)
      (fail 429 'snapshot_app_capacity' 'Two snapshots for this app are already active')
    =/  rows
      %+  sort  ~(val by records.db)
      |=  [a=record:c b=record:c]
      ?:  =(collection.key.a collection.key.b)  (aor id.key.a id.key.b)
      (aor collection.key.a collection.key.b)
    =/  id  (secret 'snapshot')
    =/  value=snapshot:c  [id session namespace epoch.state.world epoch.db revision.db (add now.ctx ~m1) rows]
    =.  snapshots.world  (~(put by snapshots.world) id value)
    (snapshot-page value |)
  ++  snapshot-page
    |=  [value=snapshot:c throttled=?]
    ^-  http-result:c
    ?.  &((gth expires.value now.ctx) =(global.value epoch.state.world))
      (fail 410 'snapshot_expired' 'Start a new snapshot')
    =/  space  (~(get by spaces.state.world) namespace.value)
    ?~  space  (fail 410 'epoch_changed' 'Namespace was erased')
    ?.  =(epoch.u.space epoch.value)  (fail 410 'epoch_changed' 'Namespace was erased')
    =/  offset  (parameter 'page' 0 0 (lent records.value))
    =/  limit  (parameter 'limit' 100 1 100)
    ::  Successful reads renew inactivity. A valid throttled continuation gets
    ::  the advertised 60-second retry wait plus the normal 60-second lease.
    =.  value  value(expires (add now.ctx ?:(throttled ~m2 ~m1)))
    =.  snapshots.world  (~(put by snapshots.world) id.value value)
    ?:  throttled  (fail 429 'rate_limited' 'Wait before making more document requests')
    =/  selected  (scag limit (slag offset records.value))
    =/  next  (add offset (lent selected))
    =/  result
      %-  object:cc
      :~  ['snapshotId' [%s id.value]]
          ['atCursor' [%s (cursor:cs global.value epoch.value revision.value)]]
          ['documents' [%a (turn selected document:cc)]]
          ['nextPage' ?:((gte next (lent records.value)) ~ (decimal:cc next))]
      ==
    (reply 200 result)
  --
--
