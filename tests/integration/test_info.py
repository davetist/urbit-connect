from targets import TARGETS
import json
import unittest
import urllib.error
import urllib.request


class PublicInfoTests(unittest.TestCase):
    def test_ship_serves_versioned_development_identity(self):
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{TARGETS.port('http')}/connect/v1/info",timeout=10) as response:
                status=response.status
                self.assertIn('application/json',response.headers.get('Content-Type',''))
                result=json.load(response)
        except urllib.error.HTTPError as error:
            status=error.code
            result={}
            error.close()
        self.assertEqual(status,200)
        self.assertEqual(result["protocolVersion"],1)
        self.assertEqual(result["ship"],"~zod")
        self.assertTrue(result["development"])
        self.assertTrue(result["instanceId"])


if __name__=="__main__":
    unittest.main()
