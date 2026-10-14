::  Test consumer for the documented local resource contract.
/-  c=connect
/+  default-agent
|%
+$  card  card:agent:gall
--
^-  agent:gall
=|  result=json
|_  =bowl:gall
+*  this  .
    def  ~(. (default-agent this %|) bowl)
++  on-init  `this
++  on-save  !>(result)
++  on-load
  |=  old=vase
  `this(result !<(json old))
++  on-poke
  |=  [=mark =vase]
  ^-  (quip card _this)
  ?>  =(src.bowl our.bowl)
  ?:  =(%json mark)
    ?>  =(sap.bowl /gall/connect)
    `this(result !<(json vase))
  ?:  =(%connect-revoke mark)
    =/  req=revoke-request:c  !<(revoke-request:c vase)
    :_  this
    ~[[%pass /revoke %agent [our.bowl %connect] %poke %connect-revoke !>(req)]]
  ?>  =(%connect-exchange mark)
  =/  req=exchange-request:c  !<(exchange-request:c vase)
  :_  this
  ~[[%pass /exchange %agent [our.bowl %connect] %poke %connect-exchange !>(req)]]
++  on-peek
  |=  =path
  ^-  (unit (unit cage))
  ?:  =(path /x/result)  ``[%json !>(result)]
  ?.  ?=([%x %notes @ ~] path)  (on-peek:def path)
  =/  grant  .^(json %gx /(scot %p our.bowl)/connect/(scot %da now.bowl)/integration/grant-probe/[i.t.t.path]/json)
  =/  value=json
    ?~  grant  ~
    [%s 'Independent notes consumer: owner-approved resource access.']
  ``[%json !>(value)]
++  on-agent
  |=  [=wire =sign:agent:gall]
  ?:  ?=([%poke-ack ^] sign)
    `this(result [%s 'exchange-rejected'])
  `this
++  on-watch  on-watch:def
++  on-leave  on-leave:def
++  on-arvo  on-arvo:def
++  on-fail  on-fail:def
--
