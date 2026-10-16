/-  c=connect
/+  cc=connect-codec, cj=connect-json
|%
++  empty  ^-  space:c  [1 0 ~ ~ ~ ~ 0]
++  clean
  |=  [db=space:c now=@da]
  ^-  space:c
  =.  receipts.db
    %-  malt
    %+  skim  ~(tap by receipts.db)
    |=  item=[p=@t q=receipt:c]
    (gth expires.q.item now)
  =.  tombstones.db
    %-  malt
    %+  skim  ~(tap by tombstones.db)
    |=  item=[p=key:c q=tombstone:c]
    (gth expires.q.item now)
  db
++  mutate
  |=  [db=space:c auth=authority:c now=@da request=mutation:c]
  ^-  transition:c
  |^
  ?.  =(epoch.auth epoch.db)  (fail 401 'epoch_changed' 'Namespace was erased')
  ?.  (levy operations.request |=(op=operation:c ?:(?=(%put -.op) write.auth delete.auth)))
    (fail 403 'insufficient_scope' 'The current grant cannot perform this operation')
  =/  count  (lent operations.request)
  ?.  (gth count 0)  (fail 400 'invalid_batch' 'Use at least one operation')
  =/  targets  (turn operations.request |=(op=operation:c key.op))
  ?.  =(count (lent ~(tap in (silt targets))))  (fail 400 'duplicate_target' 'A batch may touch each document once')
  =/  work  (clean db now)
  =/  prior  (~(get by receipts.work) id.request)
  ?^  prior
    ?.  =(digest.u.prior digest.request)  (fail 409 'idempotency_mismatch' 'Request ID already identifies different bytes')
    [db [200 result.u.prior]]
  =/  revision  +(revision.work)
  =/  expiry  (add now ~d30)
  =/  ops  operations.request
  =/  results  *(list json)
  =/  changes  *(list json)
  |-  ^-  transition:c
  ?~  ops
    =/  bytes  (roll ~(val by records.work) |=([row=record:c total=@ud] (add total (met 3 (en:json:html data.row)))))
    =/  commit  (object:cc ~[['revision' (decimal:cc revision)] ['results' [%a (flop results)]]])
    =/  ordered  (flop changes)
    =/  size  (met 3 (en:json:html [%a ordered]))
    =/  log  (trim-log (weld journal.work ~[[revision ordered size]]))
    :_  [200 commit]
    work(revision revision, bytes bytes, journal log, receipts (~(put by receipts.work) id.request [digest.request expiry commit]))
  =/  op  i.ops
  =/  current  (~(get by records.work) key.op)
  =/  deleted  (~(get by tombstones.work) key.op)
  =/  version=(unit @ud)  ?:(?=(%put -.op) expected.op `expected.op)
  =/  matches
    ?~  version  &(=(~ current) =(~ deleted))
    ?~  current  |
    =(u.version revision.u.current)
  ?.  matches
    =/  detail
      %-  object:cc
      :~  ['code' [%s 'conflict']]
          ['message' [%s 'The document changed; preserve the draft and resolve the conflict']]
          ['requestId' [%s id.request]]
          ['collection' [%s collection.key.op]]
          ['id' [%s id.key.op]]
          ['current' ?~(current ~ ?:(read.auth (document:cc u.current) ~))]
          ['currentRevision' ?~(current ?~(deleted ~ (decimal:cc revision.u.deleted)) (decimal:cc revision.u.current))]
          ['deleted' [%b &(=(~ current) !=(~ deleted))]]
      ==
    [db [409 (object:cc ~[['error' detail]])]]
  =/  result
    %-  object:cc
    :~  ['collection' [%s collection.key.op]]
        ['id' [%s id.key.op]]
        ['revision' (decimal:cc revision)]
        ['deleted' [%b ?=(%delete -.op)]]
    ==
  ?:  ?=(%delete -.op)
    =.  work  work(records (~(del by records.work) key.op), tombstones (~(put by tombstones.work) key.op [revision expiry]))
    $(ops t.ops, results [result results], changes [result changes])
  ?.  ?=([%o *] data.op)  (fail 400 'invalid_document' 'Documents must be JSON objects')
  ?.  (bounded:cj (en:json:html data.op))  (fail 400 'invalid_document' 'Document exceeds 16 levels of nesting')
  =/  row=record:c  [key.op data.op revision now]
  =.  work  work(records (~(put by records.work) key.op row))
  =/  change  (object:cc ~[['document' (document:cc row)] ['deleted' [%b |]]])
  $(ops t.ops, results [result results], changes [change changes])
  ++  fail
    |=  [status=@ud code=@t message=@t]
    ^-  transition:c
    [db [status (error:cc code message `id.request)]]
  --
++  trim-log
  |=  log=(list batch:c)
  ^-  (list batch:c)
  =/  bytes  (roll log |=([entry=batch:c total=@ud] (add total bytes.entry)))
  =/  count  (lent log)
  |-  ^+  log
  ?~  log  ~
  ?:  &((lte count 1.024) (lte bytes 1.048.576))  log
  $(log t.log, count (dec count), bytes (sub bytes bytes.i.log))
++  cursor
  |=  [global=@ud namespace=@ud revision=@ud]
  ^-  @t
  (crip "{(trip (ud:cc global))}:{(trip (ud:cc namespace))}:{(trip (ud:cc revision))}")
++  decode-cursor
  |=  raw=@t
  ^-  (unit [global=@ud namespace=@ud revision=@ud])
  (rush raw ;~(plug (bass 10 (plus dit)) ;~(pfix col (bass 10 (plus dit))) ;~(pfix col (bass 10 (plus dit)))))
++  changes
  |=  [db=space:c global=@ud raw=@t]
  (changes-page db global raw 100)
++  changes-page
  |=  [db=space:c global=@ud raw=@t limit=@ud]
  ^-  outcome:c
  =/  parsed  (decode-cursor raw)
  ?~  parsed  [400 (error:cc 'invalid_cursor' 'Invalid cursor' ~)]
  ?.  &(=(global global.u.parsed) =(epoch.db namespace.u.parsed))
    [410 (error:cc 'epoch_changed' 'Snapshot required for changed epoch' ~)]
  =/  since  revision.u.parsed
  ?:  (gth since revision.db)  [410 (error:cc 'cursor_ahead' 'Restore recovery is required' ~)]
  =/  earliest  ?~(journal.db +(revision.db) revision.i.journal.db)
  ?:  (lth +(since) earliest)  [410 (error:cc 'cursor_expired' 'Snapshot required after journal gap' ~)]
  =/  entries  (skim journal.db |=(entry=batch:c (gth revision.entry since)))
  =/  selected=(list batch:c)  (scag limit entries)
  =/  last  (max since (roll selected |=([item=batch:c result=@ud] revision.item)))
  =/  encoded
    %+  turn  selected
    |=  entry=batch:c
    (object:cc ~[['revision' (decimal:cc revision.entry)] ['changes' [%a changes.entry]]])
  :-  200
  %-  object:cc
  :~  ['batches' [%a encoded]]
      ['nextCursor' [%s (cursor global epoch.db last)]]
      ['hasMore' [%b (gth (lent entries) (lent selected))]]
  ==
--
