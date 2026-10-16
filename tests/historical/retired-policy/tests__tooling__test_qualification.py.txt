from pathlib import Path
import json
import sys
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import qualify_alpha as qa
import release_check

class QualificationTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        original = qa.ROOT
        self.addCleanup(setattr, qa, 'ROOT', original)
        qa.ROOT = Path(self.folder.name)
        evidence = qa.ROOT / 'artifacts/alpha/evidence.json'
        evidence.parent.mkdir(parents=True)
        evidence.write_text('{"fixture": "qualification-policy"}\n')

    def manifest(self):
        return {'version':'candidate','source':{},'artifacts':{},'toolchain':{},'publicationBlockers':[]}
    def checks(self):
        return {'scope':['all'],'source':{},'checks':[{'check':name,'passed':True,'cases':1 if name in qa.COUNTED else None} for name in qa.AUTOMATED]}
    def manual(self, manifest):
        return {name: {'status':'passed','releaseIdentity':qa.identity(manifest),
                       'performedBy':'unit-test-fixture','evidence':['artifacts/alpha/evidence.json'],
                       'operators':2,'rehearsals':2,'independent':True,
                       'durationSeconds':7*86400,'testers':2} for name in qa.MANUAL}

    def test_private_alpha_can_qualify_with_contacts_deferred_for_publication(self):
        ownership = qa.ROOT / 'release/ownership.json'
        ownership.parent.mkdir()
        ownership.write_text(json.dumps({'sourceOwner':None,'maintenanceContact':None,
                                        'securityContact':None,'landscapeNoticeResolved':True,
                                        'publicationAuthorized':False}))
        original = release_check.ROOT
        try:
            release_check.ROOT = qa.ROOT
            blockers = release_check.publication_blockers()
        finally:
            release_check.ROOT = original
        self.assertEqual(blockers, ['sourceOwner','maintenanceContact','securityContact','publication authorization'])
        manifest = self.manifest(); manifest['publicationBlockers'] = blockers
        value = qa.evaluate(manifest, self.checks(), self.manual(manifest))
        self.assertTrue(value['qualified'], value['failures'])
        self.assertEqual(value.get('qualificationScope'), 'private-alpha')
        self.assertEqual(value.get('publicationBlockers'), blockers)
        self.assertEqual(json.loads(ownership.read_text())['sourceOwner'], None)

    def test_deferring_contacts_preserves_independent_and_elapsed_gates(self):
        manifest = self.manifest()
        manifest['publicationBlockers'] = ['sourceOwner','maintenanceContact','securityContact']
        for name, field, shortfall in [('restore-operators','operators',1),
                                        ('independent-sdk-integration','independent',False),
                                        ('real-arm64-install-update','independent',False),
                                        ('real-host-soak','durationSeconds',21599),
                                        ('practical-trial','durationSeconds',604799)]:
            with self.subTest(gate=name):
                manual = self.manual(manifest); manual[name][field] = shortfall
                value = qa.evaluate(manifest, self.checks(), manual)
                self.assertFalse(value['qualified'])
                self.assertEqual(value['failures'], ['Required evidence below gate: '+name+'/'+field])

    def test_six_actual_hours_satisfy_only_the_soak_duration_gate(self):
        manifest = self.manifest(); manual = self.manual(manifest)
        manual['real-host-soak']['durationSeconds'] = 21600
        value = qa.evaluate(manifest, self.checks(), manual)
        self.assertTrue(value['qualified'], value['failures'])

    def test_failed_soak_cannot_pass_with_six_hours_of_elapsed_time(self):
        manifest = self.manifest(); manual = self.manual(manifest)
        manual['real-host-soak'].update(status='failed', durationSeconds=21600)
        value = qa.evaluate(manifest, self.checks(), manual)
        self.assertEqual(value['failures'], ['Required evidence pending: real-host-soak'])

    def test_unresolved_provenance_still_blocks_private_qualification(self):
        manifest = self.manifest()
        manifest['publicationBlockers'] = ['sourceOwner','landscapeNoticeResolved','publication authorization']
        value = qa.evaluate(manifest, self.checks(), self.manual(manifest))
        self.assertFalse(value['qualified'])
        self.assertEqual(value['failures'], ['Release prerequisite pending: landscapeNoticeResolved'])
    def test_stale_checks_cannot_qualify_changed_sources(self):
        checks=self.checks();checks['source']={'sdk':'old'}
        value=qa.evaluate(self.manifest(),checks,{})
        self.assertIn('Automated results do not match the release sources',value['failures'])
    def test_missing_manual_rows_cannot_be_claimed_qualified(self):
        value=qa.evaluate(self.manifest(),self.checks(),{})
        self.assertFalse(value['qualified']);self.assertEqual(len(value['failures']),len(qa.MANUAL))
    def test_zero_or_skipped_required_suites_fail_even_with_exit_success(self):
        for change in [{'cases':0},{'skipped':1},{'passed':False}]:
            checks=self.checks();next(row for row in checks['checks']if row['check']=='sdk').update(change)
            value=qa.evaluate(self.manifest(),checks,{})
            self.assertTrue(any('sdk' in issue for issue in value['failures']))
    def test_short_soak_and_trial_or_wrong_release_are_refused(self):
        bound=qa.identity(self.manifest())
        for name in ['real-host-soak','practical-trial']:
            row={'status':'passed','releaseIdentity':bound,'performedBy':'independent-test','evidence':['artifacts/alpha/checks.json'],'durationSeconds':10,'testers':3}
            value=qa.evaluate(self.manifest(),self.checks(),{name:row})
            self.assertTrue(any('durationSeconds' in issue for issue in value['failures']))
            row['releaseIdentity']='other';value=qa.evaluate(self.manifest(),self.checks(),{name:row})
            self.assertIn('Required evidence pending: '+name,value['failures'])

if __name__ == '__main__':unittest.main()
