from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from ios_test import validate_real_sdk_evidence


class NativeEvidence(unittest.TestCase):
    def summary(self):return {'result':'Passed','totalTestCount':1,'passedTests':1,'failedTests':0,'skippedTests':0,'expectedFailures':0}
    def measurement(self):return {'status':'measured','passed':False,'measurementRunID':'current','documents':1000,'realShip':True,'normalSystemTLS':True,'snapshotAndSQLiteSeconds':2,'automaticForegroundObservationSeconds':.5,'networkProfile':{'profile':'100ms-1percent'}}

    def test_failed_zero_skipped_or_stale_native_run_cannot_promote_measurement(self):
        for change in [{'result':'Failed'},{'failedTests':1},{'totalTestCount':0},{'passedTests':0},{'skippedTests':1},{'expectedFailures':1}]:
            with self.subTest(change=change),self.assertRaises(ValueError):validate_real_sdk_evidence(self.measurement(),self.summary()|change,'current')
        with self.assertRaises(ValueError):validate_real_sdk_evidence(self.measurement(),self.summary(),'other-run')
        with self.assertRaises(ValueError):validate_real_sdk_evidence(self.measurement()|{'snapshotAndSQLiteSeconds':31},self.summary(),'current')

    def test_matching_complete_result_validates_without_mutating_raw_measurement(self):
        value=self.measurement();validate_real_sdk_evidence(value,self.summary(),'current')
        self.assertFalse(value['passed']);self.assertEqual(value['status'],'measured')


if __name__=='__main__':unittest.main()
