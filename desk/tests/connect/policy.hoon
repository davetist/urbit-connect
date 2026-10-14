/+  *test, cp=connect-policy
|%
++  test-owner-requires-authentication
  (expect-eq !>(|) !>((owner:cp | &)))
++  test-foreign-authenticated-is-not-owner
  (expect-eq !>(|) !>((owner:cp & |)))
++  test-local-authenticated-is-owner
  (expect-eq !>(&) !>((owner:cp & &)))
--
