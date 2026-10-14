/-  c=connect
/+  *test, cc=connect-codec, ci=connect-integrations
|%
++  test-native-resource-callback
  =/  policy=json
    (object:cc ~[['agent' s+'sample'] ['scopes' a+~[s+'sample:read']] ['redirectURIs' a+~[s+'sample://callback']]])
  =/  result  (mule |.((decode:ci policy)))
  (expect-eq !>(%&) !>(-.result))
++  test-single-label-schemes-retain-exact-registration
  =/  redirects=(list @t)
    ~['sample://sso-callback' 'sample://callback' 'a://callback' 'sample+v2.test-app://callback/path']
  =/  policy=json
    (object:cc ~[['agent' s+'sample'] ['scopes' a+~[s+'sample:read']] ['redirectURIs' a+(turn redirects |=(r=@t s+r))]])
  =/  result  (decode:ci policy)
  (expect-eq !>((silt redirects)) !>(redirects.result))
++  test-existing-callbacks-stay-supported
  =/  policy=json
    (object:cc ~[['agent' s+'sample'] ['scopes' a+~[s+'sample:read']] ['redirectURIs' a+~[s+'https://example.invalid/callback' s+'http://localhost:8065']]])
  =/  result  (mule |.((decode:ci policy)))
  (expect-eq !>(%&) !>(-.result))
--
