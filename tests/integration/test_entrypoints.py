import json
import unittest
import urllib.request
import uuid
from support import API,ORIGIN

class EntryPointTests(unittest.TestCase):
    def test_generic_channel_cannot_subscribe_to_http_response_paths(self):
        api=API();channel='/~/channel/connect-test-'+uuid.uuid4().hex
        action={'id':1,'action':'subscribe','ship':'zod','app':'connect','path':'/http-response/connect-test-probe'}
        try:
            status,_,_=api.request(channel,'PUT',[action],owner=True);self.assertEqual(status,204)
            request=urllib.request.Request(ORIGIN+channel,headers={'Cookie':api.cookie,'Accept':'text/event-stream'})
            with api.opener.open(request,timeout=10)as response:
                lines=[]
                while True:
                    line=response.readline().decode().strip()
                    if line.startswith('data:'):lines.append(line[5:].strip())
                    if not line and lines:
                        event=json.loads('\n'.join(lines));lines=[]
                        if event.get('id')==1:
                            self.assertEqual(event.get('response'),'subscribe')
                            self.assertIn('err',event,'A generic channel subscription was accepted on a private HTTP response path')
                            break
        finally:api.request(channel,'DELETE',owner=True)
if __name__=='__main__':unittest.main()
