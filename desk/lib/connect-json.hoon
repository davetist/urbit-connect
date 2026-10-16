::  Strict JSON; parser adapted from Urbit zuse (MIT).
::  See third_party/urbit/LICENSE.txt. No jet hint may bypass validation.
|%
++  parse  |=(text=@t (parse-depth text 16))
++  parse-wire  |=(text=@t (parse-depth text 24))
++  parse-depth
  |=  [text=@t limit=@ud]
  ^-  (unit json)
  ?.  (bounded-depth text limit)  ~
  =/  parsed  (strict text)
  ?~  parsed  ~
  ?.  (safe-value u.parsed)  ~
  parsed
++  bounded  |=(text=@t (bounded-depth text 16))
++  bounded-depth
  |=  [text=@t limit=@ud]
  ^-  ?
  =/  chars  (trip text)
  =/  depth=@ud  0
  =/  quoted=?  |
  =/  escaped=?  |
  |-  ^-  ?
  ?~  chars  &(=(0 depth) !quoted)
  =/  c  i.chars
  ?:  escaped  $(chars t.chars, escaped |)
  ?:  quoted
    ?:  =(c 92)  $(chars t.chars, escaped &)
    $(chars t.chars, quoted !=(c 34))
  ?:  =(c 34)  $(chars t.chars, quoted &)
  ?:  |(=(c 123) =(c 91))
    ?.  (lth depth limit)  |
    $(chars t.chars, depth +(depth))
  ?:  |(=(c 125) =(c 93))
    ?:  =(0 depth)  |
    $(chars t.chars, depth (dec depth))
  $(chars t.chars)
++  safe-number
  |=  text=@t
  ^-  ?
  ?:  (gth (met 3 text) 2.048)  |
  =/  parsed  (rush text json-rn:format)
  ?~  parsed  |
  =/  r  u.parsed
  ?.  ?=(%d -.r)  |
  ?:  |((gth d.b.r 1.024) (gth i.b.r 1.024))  |
  =/  numerator  (add (mul c.b.r (pow 10 d.b.r)) e.b.r)
  =/  denominator  (pow 10 d.b.r)
  =/  exponent  (pow 10 i.b.r)
  =.  numerator  ?:(f.b.r (mul numerator exponent) numerator)
  =.  denominator  ?:(f.b.r denominator (mul denominator exponent))
  (lte numerator (mul 9.007.199.254.740.991 denominator))
++  safe-value
  |=  value=json
  ^-  ?
  ?~  value  &
  ?-  -.value
    %n  (safe-number p.value)
    %a  (levy p.value safe-value)
    %o  (levy ~(val by p.value) safe-value)
    %s  &
    %b  &
  ==
++  strict                                          ::  unjetted parser
  |^  |=  txt=cord
      ^-  (unit json)
      (rush txt apex)
  ::                                                ::  ++abox:de:json:html
  ++  abox                                          ::  array
    %+  stag  %a
    (ifix [sel (wish ser)] (more (wish com) apex))
  ::                                                ::  ++apex:de:json:html
  ++  apex                                          ::  any value
    %+  knee  *json  |.  ~+
    %+  ifix  [spac spac]
    ;~  pose
      (cold ~ (jest 'null'))
      (stag %b bool)
      (stag %s stri)
      (cook |=(s=tape [%n p=(rap 3 s)]) numb)
      abox
      obox
    ==
  ::                                                ::  ++bool:de:json:html
  ++  bool                                          ::  boolean
    ;~  pose
      (cold & (jest 'true'))
      (cold | (jest 'false'))
    ==
  ::                                                ::  ++esca:de:json:html
  ++  esca                                          ::  escaped character
    ;~  pfix  bas
      =*  loo
        =*  lip
          ^-  (list (pair @t @))
          [b+8 t+9 n+10 f+12 r+13 ~]
        =*  wow
          ^~
          ^-  (map @t @)
          (malt lip)
        (sear ~(get by wow) low)
      ;~(pose doq fas bas loo unic)
    ==
  ::                                                ::  ++expo:de:json:html
  ++  expo                                          ::  exponent
    ;~  (comp weld)
      (piec (mask "eE"))
      (mayb (piec (mask "+-")))
      (plus nud)
    ==
  ::                                                ::  ++frac:de:json:html
  ++  frac                                          ::  fraction
    ;~(plug dot (plus nud))
  ::                                                ::  ++jcha:de:json:html
  ++  jcha                                          ::  string character
    ;~(pose ;~(less doq bas (shim 32 255)) esca)
  ::                                                ::  ++mayb:de:json:html
  ++  mayb                                          ::  optional
    |*(bus=rule ;~(pose bus (easy ~)))
  ::                                                ::  ++numb:de:json:html
  ++  numb                                          ::  number
    ;~  (comp weld)
      (mayb (piec hep))
      ;~  pose
        (piec (just '0'))
        ;~(plug (shim '1' '9') (star nud))
      ==
      (mayb frac)
      (mayb expo)
    ==
  ::                                                ::  ++obje:de:json:html
  ++  obje                                          ::  object list
    %+  ifix  [(wish kel) (wish ker)]
    (more (wish com) pear)
  ::                                                ::  ++obox:de:json:html
  ++  obox                                          ::  object
    (stag %o (sear unique obje))
  ::                                                ::  ++pear:de:json:html
  ++  unique
    |=  entries=(list [key=@t value=json])
    ^-  (unit (map @t json))
    =|  out=(map @t json)
    |-  ^-  (unit (map @t json))
    ?~  entries  `out
    ?:  (~(has by out) key.i.entries)  ~
    $(entries t.entries, out (~(put by out) key.i.entries value.i.entries))
  ++  pear                                          ::  key-value
    ;~(plug ;~(sfix (wish stri) (wish col)) apex)
  ::                                                ::  ++piec:de:json:html
  ++  piec                                          ::  listify
    |*  bus=rule
    (cook |=(a=@ [a ~]) bus)
  ::                                                ::  ++stri:de:json:html
  ++  stri                                          ::  string
    %+  sear
      |=  a=cord
      ?.  (sune a)  ~
      (some a)
    (cook crip (ifix [doq doq] (star jcha)))
  ::                                                ::  ++spac:de:json:html
  ++  spac                                          ::  whitespace
    (star (mask [`@`9 `@`10 `@`13 ' ' ~]))
  ::                                                ::  ++unic:de:json:html
  ++  unic                                          ::  escaped UTF16
    =*  lob  0x1
    =*  hsb  0xd800
    =*  lsb  0xdc00
    =*  hib  0xe000
    =*  hil  0x1.0000
    |^
      %+  cook
        |=  a=@
        ^-  @t
        (tuft a)
      ;~  pfix  (just 'u')
        ;~(pose solo pair)
      ==
    ++  quad                                        ::  parse num from 4 hex
      (bass 16 (stun [4 4] hit))
    ++  meat                                        ::  gen gate for sear:
      |=  [bot=@ux top=@ux flp=?]                   ::  accept num in range,
      |=  sur=@ux                                   ::  optionally reduce
      ^-  (unit @)
      ?.  &((gte sur bot) (lth sur top))
        ~
      %-  some
      ?.  flp  sur
      (sub sur bot)
    ++  solo                                        ::  single valid UTF16
      ;~  pose
        (sear (meat lob hsb |) quad)
        (sear (meat hib hil |) quad)
      ==
    ++  pair                                        ::  UTF16 surrogate pair
      %+  cook
        |=  [hig=@ low=@]
          ^-  @t
          :(add hil low (lsh [1 5] hig))
      ;~  plug
        (sear (meat hsb lsb &) quad)
        ;~  pfix  (jest '\\u')
          (sear (meat lsb hib &) quad)
        ==
      ==
    --
  ::                                                ::  ++utfe:de:json:html
  ++  utfe                                          ::  UTF-8 sequence
    ;~  less  doq  bas
      =*  qua
        %+  cook
        |=  [a=@ b=@ c=@ d=@]
          (rap 3 a b c d ~)
        ;~  pose
          ;~  plug
            (shim 241 243)
            (shim 128 191)
            (shim 128 191)
            (shim 128 191)
          ==
          ;~  plug
            (just '\F0')
            (shim 144 191)
            (shim 128 191)
            (shim 128 191)
          ==
          ;~  plug
            (just '\F4')
            (shim 128 143)
            (shim 128 191)
            (shim 128 191)
          ==
        ==
      =*  tre
        %+  cook
        |=  [a=@ b=@ c=@]
          (rap 3 a b c ~)
        ;~  pose
          ;~  plug
            ;~  pose
              (shim 225 236)
              (shim 238 239)
            ==
            (shim 128 191)
            (shim 128 191)
          ==
          ;~  plug
            (just '\E0')
            (shim 160 191)
            (shim 128 191)
          ==
          ;~  plug
            (just '\ED')
            (shim 128 159)
            (shim 128 191)
          ==
        ==
      =*  dos
        %+  cook
        |=  [a=@ b=@]
          (cat 3 a b)
        ;~  plug
          (shim 194 223)
          (shim 128 191)
        ==
      ;~(pose qua tre dos)
    ==
  ::                                                ::  ++wish:de:json:html
  ++  wish                                          ::  with whitespace
    |*(sef=rule ;~(pfix spac sef))
  ::  XX: These gates should be moved to hoon.hoon
  ::                                                ::  ++sune:de:json:html
  ++  sune                                          ::  cord UTF-8 sanity
    |=  b=@t
    ^-  ?
    ?:  =(0 b)  &
    ?.  (sung b)  |
    $(b (rsh [3 (teff b)] b))
  ::                                                ::  ++sung:de:json:html
  ++  sung                                          ::  char UTF-8 sanity
    |^  |=  b=@t
        ^-  ?
        =+  len=(teff b)
        ?:  =(4 len)  (quad b)
        ?:  =(3 len)  (tres b)
        ?:  =(2 len)  (dos b)
        (lte (end 3 b) 127)
    ::
    ++  dos
      |=  b=@t
      ^-  ?
      =+  :-  one=(cut 3 [0 1] b)
              two=(cut 3 [1 1] b)
      ?&  (rang one 194 223)
          (cont two)
      ==
    ::
    ++  tres
      |=  b=@t
      ^-  ?
      =+  :+  one=(cut 3 [0 1] b)
              two=(cut 3 [1 1] b)
              tre=(cut 3 [2 1] b)
      ?&
        ?|
          ?&  |((rang one 225 236) (rang one 238 239))
              (cont two)
          ==
          ::
          ?&  =(224 one)
              (rang two 160 191)
          ==
          ::
          ?&  =(237 one)
              (rang two 128 159)
          ==
        ==
        ::
        (cont tre)
      ==
    ::
    ++  quad
      |=  b=@t
      ^-  ?
      =+  :^  one=(cut 3 [0 1] b)
              two=(cut 3 [1 1] b)
              tre=(cut 3 [2 1] b)
              for=(cut 3 [3 1] b)
      ?&
        ?|
          ?&  (rang one 241 243)
              (cont two)
          ==
          ::
          ?&  =(240 one)
              (rang two 144 191)
          ==
          ::
          ?&  =(244 one)
              (rang two 128 143)
          ==
        ==
        ::
        (cont tre)
        (cont for)
      ==
    ::
    ++  cont
      |=  a=@
      ^-  ?
      (rang a 128 191)
    ::
    ++  rang
      |=  [a=@ bot=@ top=@]
      ^-  ?
      ?>  (lte bot top)
      &((gte a bot) (lte a top))
    --
  ::  XX: This +teff should overwrite the existing +teff
  ::                                                ::  ++teff:de:json:html
  ++  teff                                          ::  UTF-8 length
    |=  a=@t
    ^-  @
    =+  b=(end 3 a)
    ?:  =(0 b)
      ?>  =(`@`0 a)  0
    ?:  (lte b 127)  1
    ?:  (lte b 223)  2
    ?:  (lte b 239)  3
    4
  --  ::de
--
