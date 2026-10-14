/-  c=connect
/+  cj=connect-json
|%
++  object  pairs:enjs:format
++  string  |=(s=@t ^-(json [%s s]))
++  ud
  |=  n=@ud
  ^-  @t
  (crip (skim (trip (scot %ud n)) |=(ch=@tD !=(ch '.'))))
++  decimal  |=(n=@ud (string (ud n)))
++  field
  |=  [name=@t value=json]
  ^-  json
  ?>  ?=([%o *] value)
  (~(got by p.value) name)
++  text
  |=  value=json
  ^-  @t
  ?>  ?=([%s *] value)
  p.value
++  keys
  |=  [value=json allowed=(set @t)]
  ^-  ?
  ?.  ?=([%o *] value)  |
  (levy ~(tap in ~(key by p.value)) |=(k=@t (~(has in allowed) k)))
++  name
  |=  value=@t
  ^-  ?
  =/  chars  (trip value)
  ?~  chars  |
  ?.  &((gte i.chars 'a') (lte i.chars 'z'))  |
  ?.  (lte (lent chars) 48)  |
  %+  levy  t.chars
  |=  ch=@tD
  |(&((gte ch 'a') (lte ch 'z')) &((gte ch '0') (lte ch '9')) =(ch '-'))
++  uuid
  |=  value=@t
  ^-  ?
  =/  chars  (trip value)
  ?.  =(36 (lent chars))  |
  =/  index=@ud  0
  |-  ^-  ?
  ?~  chars  &
  =/  ch  i.chars
  =/  dash  |(=(index 8) =(index 13) =(index 18) =(index 23))
  ?.  ?:(dash =(ch '-') |(&((gte ch 'a') (lte ch 'f')) &((gte ch '0') (lte ch '9'))))  |
  $(chars t.chars, index +(index))
++  revision
  |=  value=json
  ^-  @ud
  =/  raw  (text value)
  ?>  (lte (met 3 raw) 128)
  =/  parsed  (rush raw (bass 10 (plus dit)))
  ?>  ?=(^ parsed)
  ?>  =(raw (ud u.parsed))
  u.parsed
++  error
  |=  [code=@t message=@t request-id=(unit @t)]
  ^-  json
  =/  detail
    %-  object
    :~  ['code' (string code)]
        ['message' (string message)]
        ['requestId' ?~(request-id ~ (string u.request-id))]
    ==
  (object ~[['error' detail]])
++  timestamp
  |=  value=@da
  ^-  @t
  =/  date  (yore value)
  =/  pad  |=(n=@ud ?:(=(1 (met 3 (ud n))) (cat 3 '0' (ud n)) (ud n)))
  (crip "{(trip (ud y.date))}-{(trip (pad m.date))}-{(trip (pad d.t.date))}T{(trip (pad h.t.date))}:{(trip (pad m.t.date))}:{(trip (pad s.t.date))}Z")
++  document
  |=  row=record:c
  ^-  json
  %-  object
  :~  ['id' (string id.key.row)]
      ['collection' (string collection.key.row)]
      ['data' data.row]
      ['revision' (decimal revision.row)]
      ['updatedAt' (string (timestamp updated.row))]
  ==
++  decode-mutation
  |=  body=@t
  ^-  mutation:c
  =/  parsed  (parse-wire:cj body)
  ?>  ?=(^ parsed)
  =/  value  u.parsed
  ?>  (keys value (silt ~['requestId' 'operations']))
  =/  id  (text (field 'requestId' value))
  ?>  (uuid id)
  =/  ops  (field 'operations' value)
  ?>  ?=([%a *] ops)
  ?>  &((gth (lent p.ops) 0) (lte (lent p.ops) 32))
  [id (shax body) (turn p.ops decode-operation)]
++  decode-operation
  |=  value=json
  ^-  operation:c
  =/  kind  (text (field 'type' value))
  =/  col  (text (field 'collection' value))
  =/  id  (text (field 'id' value))
  ?>  &((name col) (uuid id))
  =/  exp  (field 'expectedRevision' value)
  ?:  =(kind 'delete')
    ?>  (keys value (silt ~['type' 'collection' 'id' 'expectedRevision']))
    [%delete [col id] (revision exp)]
  ?>  =(kind 'put')
  ?>  (keys value (silt ~['type' 'collection' 'id' 'expectedRevision' 'data']))
  =/  data  (field 'data' value)
  ?>  ?=([%o *] data)
  ?>  (bounded:cj (en:json:html data))
  [%put [col id] data ?~(exp ~ `(revision exp))]
--
