from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import doctor

class DoctorTests(unittest.TestCase):
    def test_invalid_paths_credentials_and_redirect_targets_are_not_origins(self):
        for address in ['http://ship.example','https://owner:secret@ship.example','https://ship.example/apps/connect/','https://ship.example?secret=x','https://ship.example#owner','https://ship.example:0','https://ship.example:99999']:
            with self.subTest(address=address), self.assertRaises(ValueError):doctor.origin(address)
        self.assertEqual(doctor.origin('https://SHIP.example/'),'https://ship.example')

    def info(self):
        return {'protocolVersion':1,'configured':True,'instanceId':'instance','ship':'~zod','syncEpoch':'123','development':True}

    def test_missing_versions_configuration_and_identity_are_distinct_failures(self):
        for change,message in [({'protocolVersion':2},'protocol'),({'protocolVersion':True},'protocol'),({'configured':False},'configured'),({'instanceId':''},'identity'),({'syncEpoch':'01'},'generation')]:
            with self.subTest(change=change),self.assertRaisesRegex(ValueError,message):doctor.inspect_info(self.info()|change)
        with self.assertRaisesRegex(ValueError,'selected target'):doctor.inspect_info(self.info(),expected_instance='other')
        with self.assertRaisesRegex(ValueError,'selected target'):doctor.inspect_info(self.info(),expected_ship='~nec')

    def test_report_omits_tokens_and_raw_identity(self):
        value=doctor.inspect_info(self.info()|{'access_token':'CANARY_ACCESS','refresh_token':'CANARY_REFRESH','cookie':'CANARY_COOKIE','ownerCode':'CANARY_OWNER','data':{'body':'CANARY_BODY','title':'CANARY_TITLE'}})
        self.assertNotIn('CANARY',str(value));self.assertNotIn('instanceId',value)
        self.assertTrue(value['development'])

    def test_local_diagnostic_export_has_a_fixed_field_allowlist(self):
        import json,tempfile
        with tempfile.TemporaryDirectory() as folder:
            target=Path(folder)/'diagnostic.json'
            doctor.write_report(target,doctor.inspect_info(self.info())|{'access_token':'CANARY_ACCESS','refresh_token':'CANARY_REFRESH','ownerCode':'CANARY_OWNER','cookie':'CANARY_COOKIE','title':'CANARY_TITLE','data':{'body':'CANARY_BODY'}})
            raw=target.read_text();self.assertNotIn('CANARY',raw)
            self.assertTrue(json.loads(raw)['configured'])
            self.assertEqual(target.stat().st_mode & 0o777,0o600)

if __name__ == '__main__':unittest.main()
