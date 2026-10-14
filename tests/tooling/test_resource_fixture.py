"""Fail closed before live generic contract tests can mutate a fixture."""
import json
from pathlib import Path
import socket
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from resource_fixture import Fixture, cell, hoon_text, jam


class ResourceFixtureGuards(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='generic-guard-', dir=ROOT / '.work')
        self.directory = Path(self.temporary.name)
        self.marker = self.directory / '.owned-fixture.json'
        self.marker.write_text(json.dumps({'project': str(ROOT), 'fixture': 'generic-guard'}))
        self.marker.chmod(0o600)
        self.owner = self.directory / 'owner.json'
        self.owner.write_text('{}')
        self.owner.chmod(0o600)
        self.ca = self.directory / 'ca.pem'
        self.ca.touch()
        self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.socket.bind(str(self.directory / 'control.sock'))
        self.arguments = dict(directory=self.directory, fixture_id='generic-guard',
                              origin='https://localhost:19781', ca=self.ca, owner_file=self.owner,
                              control_socket=self.directory / 'control.sock', vere=sys.executable)

    def tearDown(self):
        self.socket.close()
        self.temporary.cleanup()

    def test_explicit_owned_private_fixture_is_accepted(self):
        self.assertEqual(Fixture(**self.arguments).directory, self.directory)

    def test_wrong_fixture_identity_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'ownership'):
            Fixture(**dict(self.arguments, fixture_id='other-fixture'))

    def test_non_loopback_non_https_or_ambiguous_origin_is_rejected(self):
        for origin in ['http://localhost:19781', 'https://ship.example:19781',
                       'https://localhost', 'https://localhost:443', 'https://localhost:19781/path',
                       'https://user@localhost:19781', 'https://localhost:19781?x=y']:
            with self.subTest(origin=origin), self.assertRaisesRegex(ValueError, 'loopback HTTPS'):
                Fixture(**dict(self.arguments, origin=origin))

    def test_unrelated_private_owner_file_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'must belong'):
            Fixture(**dict(self.arguments, owner_file=ROOT / 'toolchain.json'))

    def test_public_owner_credentials_are_rejected(self):
        self.owner.chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'credential file must be private'):
            Fixture(**self.arguments)

    def test_symlink_input_is_rejected(self):
        link = self.directory / 'owner-link.json'
        link.symlink_to(self.owner)
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            Fixture(**dict(self.arguments, owner_file=link))

    def test_control_must_be_a_live_unix_socket(self):
        with self.assertRaisesRegex(ValueError, 'not a live Unix socket'):
            Fixture(**dict(self.arguments, control_socket=self.ca))

    def test_minimal_control_codec_known_nouns(self):
        self.assertEqual(jam(0), b'\x02')
        self.assertEqual(jam(1), b'\x0c')
        self.assertEqual(jam(cell(0, 0)), b'\x29')
        self.assertEqual(hoon_text("a'b\\c"), "'a\\'b\\\\c'")


if __name__ == '__main__':
    unittest.main()
