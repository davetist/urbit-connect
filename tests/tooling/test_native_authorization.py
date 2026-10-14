from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from native_harness import load_authorization_path,owner_load_document


class NativeAuthorizationBoundary(unittest.TestCase):
    def test_only_the_selected_https_origin_and_exact_load_client_can_use_test_consent(self):
        origin='https://selected.example:8443'
        path='/connect/oauth/authorize?client_id=connect-load-test'
        self.assertEqual(load_authorization_path(origin+path,origin),path)
        for value in ['https://other.example:8443'+path,'http://selected.example:8443'+path,origin+path+'&client_id=other',origin+path+'#fragment',origin+'/unrelated?client_id=connect-load-test',origin+'/connect/oauth/authorize?client_id=connect-todo-prototype']:
            with self.subTest(value=value),self.assertRaises(ValueError):load_authorization_path(value,origin)

    def test_foreground_probe_finds_a_document_beyond_the_first_owner_page(self):
        class API:
            def request(self,path,owner):
                offset=int(path.split('page=')[1])
                return 200,{'documents':[{'id':str(n),'collection':'lists','revision':'1'}for n in range(offset,offset+100)],'nextPage':str(offset+100)if offset+100<1000 else None},{}
        self.assertEqual(owner_load_document(API(),'space','999')['id'],'999')


if __name__=='__main__':unittest.main()
