from pathlib import Path
import ssl
import sys
import unittest
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from expired_tls import serving
from targets import TARGETS


class ExpiredTLS(unittest.TestCase):
    def test_correct_hostname_and_trusted_issuer_still_reject_expired_certificate(self):
        with serving() as origin:
            context = ssl.create_default_context(cafile=TARGETS.work / 'tls/ca.crt')
            with self.assertRaises(urllib.error.URLError) as caught:
                urllib.request.urlopen(origin, context=context, timeout=5)
            self.assertIsInstance(caught.exception.reason, ssl.SSLCertVerificationError)
            self.assertEqual(caught.exception.reason.verify_code, 10)


if __name__ == '__main__': unittest.main()
