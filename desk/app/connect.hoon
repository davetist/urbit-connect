::  One agent coordinates durable state and transient authorized HTTP work.
/-  c=connect
/+  default-agent, server, ch=connect-http, cc=connect-codec, ca=connect-auth, cs=connect-store, ct=connect-state, ce=connect-entry, ci=connect-integrations
|%
+$  card  card:agent:gall
--
^-  agent:gall
=/  world=world:c  [[%2 '' '' 1 0 *auth-state:c ~ ~ ~] ~ ~]
|_  =bowl:gall
+*  this  .
    def  ~(. (default-agent this %.n) bowl)
++  on-init
  ^-  (quip card _this)
  :_  this(instance.state.world (scot %uv (shax eny.bowl)))
  :~  [%pass /bind/connect %arvo %e %connect `/connect %connect]
      [%pass /bind/ui %arvo %e %connect `/apps/connect %connect]
      [%pass /cleanup %arvo %b %wait (mul +((div now.bowl ~m1)) ~m1)]
  ==
++  on-save  !>(state.world)
++  on-load
  |=  old=vase
  ^-  (quip card _this)
  =/  paths  (turn ~(val by sup.bowl) |=([s=@p p=path] p))
  =/  cleanup=card  [%pass /cleanup %arvo %b %wait (mul +((div now.bowl ~m1)) ~m1)]
  :_  this(world (load:ct old))
  =/  restart  (payload:ch [503 (error:cc 'server_restarting' 'Connect is reloading; retry this request' ~)])
  =/  completed
    %-  zing
    %+  turn  paths
    |=  p=path
    ^-  (list card)
    ?.  ?=([%http-response @ ~] p)  ~[[%give %kick ~[p] ~]]
    (give-simple-payload:app:server i.t.p restart)
  [cleanup completed]
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?+  mark  (on-poke:def mark vase)
    %connect-revoke
      =/  req=revoke-request:c  !<(revoke-request:c vase)
      ?>  &(=(src.bowl our.bowl) =(sap.bowl /gall/[resource.req]))
      =/  existing  (~(get by sessions.auth.state.world) session.req)
      ?~  existing  `this
      =/  policy  (~(get by integrations.state.world) client.u.existing)
      ?>  ?=(^ policy)
      ?>  =(resource.req agent.u.policy)
      `this(sessions.auth.state.world (~(del by sessions.auth.state.world) session.req))
    %connect-exchange
      =/  req=exchange-request:c  !<(exchange-request:c vase)
      =/  policy  (~(get by integrations.state.world) client.req)
      ?>  ?=(^ policy)
      ?>  &(=(src.bowl our.bowl) =(sap.bowl /gall/[agent.u.policy]))
      =.  nonce.state.world  +(nonce.state.world)
      =/  seed  (shax (jam [eny.bowl now.bowl nonce.state.world req]))
      =/  result
        (exchange:ca auth.state.world code.req client.req redirect.req verifier.req now.bowl (session-id:ci seed) (scot %uv (shas %access seed)) (scot %uv (shas %refresh seed)))
      =.  auth.state.world  next.result
      =/  response=json
        ?:  !=(200 status.outcome.result)  body.outcome.result
        (field:cc 'grant' body.outcome.result)
      :_  this
      ~[[%pass /integration-result %agent [our.bowl agent.u.policy] %poke %json !>((object:cc ~[['request' [%s request.req]] ['status' (numb:enjs:format status.outcome.result)] ['grant' response]]))]]
    %handle-http-request
      =/  [rid=@ta req=inbound-request:eyre]  !<([@ta inbound-request:eyre] vase)
      ?>  (http-watch:ce sup.bowl src.bowl /http-response/[rid])
      =/  ctx=context:c
        [our.bowl src.bowl now.bowl eny.bowl rid =(src.bowl our.bowl) .^(? %j /(scot %p our.bowl)/fake/(scot %da now.bowl)) req]
      =.  nonce.state.world  +(nonce.state.world)
      =/  attempt  (mule |.(!>((handle:ch world ctx))))
      ?:  ?=(%| -.attempt)
        =/  value
          ?:  =('/connect/oauth/' (crip (scag 15 (trip url.request.req))))
            (object:cc ~[['error' [%s 'invalid_request']]])
          (error:cc 'invalid_request' 'Malformed or unsupported request' ~)
        =/  response  (payload:ch 400 value)
        [(give-simple-payload:app:server rid response) this]
      =/  result  !<(http-result:c p.attempt)
      =.  world  next.result
      =/  flushed  (drain:ch world now.bowl)
      =.  world  next.flushed
      ?~  payload.result
        =/  poll  (~(get by polls.world) rid)
        ?~  poll  [cards.flushed this]
        [[[%pass /poll/[rid] %arvo %b %wait deadline.u.poll] cards.flushed] this]
      [(weld cards.flushed (give-simple-payload:app:server rid u.payload.result)) this]
  ==
++  on-watch
  |=  =path
  ^-  (quip card _this)
  ?.  (http-watch:ce sup.bowl src.bowl path)  (on-watch:def path)
  `this
++  on-peek
  |=  =path
  ^-  (unit (unit cage))
  ?.  ?=([%x %integration @ @ ~] path)  (on-peek:def path)
  =/  value  (live:ci state.world i.t.t.path i.t.t.t.path now.bowl)
  ``[%json !>(value)]
++  on-leave
  |=  =path
  ^-  (quip card _this)
  ?.  ?=([%http-response @ ~] path)  (on-leave:def path)
  =/  rid  i.t.path
  =/  poll  (~(get by polls.world) rid)
  ?~  poll  `this
  ?.  =(source.u.poll src.bowl)  `this
  :_  this(polls.world (~(del by polls.world) rid))
  ~[[%pass /poll/[rid] %arvo %b %rest deadline.u.poll]]
++  on-agent
  |=  [=wire =sign:agent:gall]
  ?:  =(wire /integration-result)  `this
  (on-agent:def wire sign)
++  on-arvo
  |=  [=wire =sign-arvo]
  ^-  (quip card _this)
  ?+  wire  (on-arvo:def wire sign-arvo)
    [%cleanup ~]
      =.  auth.state.world  (clean:ca auth.state.world now.bowl)
      =.  spaces.state.world
        (malt (turn ~(tap by spaces.state.world) |=([p=@t q=space:c] [p (clean:cs q now.bowl)])))
      =.  csrf.state.world
        (malt (skim ~(tap by csrf.state.world) |=([p=@ux q=csrf:c] (gth expires.q now.bowl))))
      =.  snapshots.world  (live-snapshots:ch snapshots.world auth.state.world now.bowl)
      =/  flushed  (drain:ch world now.bowl)
      :_  this(world next.flushed)
      [[%pass /cleanup %arvo %b %wait (mul +((div now.bowl ~m1)) ~m1)] cards.flushed]
    [%poll *]
      =/  flushed  (drain:ch world now.bowl)
      [cards.flushed this(world next.flushed)]
    [%bind *]
      ?>  ?=([%eyre %bound *] sign-arvo)
      ?>  accepted.sign-arvo
      `this
  ==
++  on-fail  on-fail:def
--
