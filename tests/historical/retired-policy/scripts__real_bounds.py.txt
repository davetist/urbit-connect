"""Exercise eight registrations, 32 sessions and four snapshots on connect-dev.

Creates/removes only this qualification's empty registration slots; never
revokes or removes another application's registration. Keeps credentials remote.
"""
from real_reference import Reference, ROOT, CLIENT, REDIRECT, private_json


def run():
    assert (ROOT / 'reference-update.json').is_file()
    api = Reference(); api.register()
    other = 'connect-reference-reader'; callback = 'org.example.connect.reader:/callback'; api.register(other, callback)
    created = []
    try:
        status, apps = api.request('/connect/owner/v1/clients', owner=True); assert status == 200
        existing = len(apps['clients'])
        for number in range(8 - existing):
            client = 'connect-reference-slot' + str(number); redirect = 'org.example.connect.slot' + str(number) + ':/callback'
            status, app = api.request('/connect/owner/v1/clients', 'POST', {'id': client, 'name': 'Empty owned capacity fixture', 'redirectURI': redirect}, owner=True)
            assert status == 200, 'Unexpected occupied qualification slot'; created.append(app)
        status, apps = api.request('/connect/owner/v1/clients', owner=True); assert status == 200 and len(apps['clients']) == 8
        assert api.request('/connect/owner/v1/clients', 'POST', {'id': 'connect-reference-overflow', 'name': 'Rejected ninth fixture', 'redirectURI': 'org.example.connect.overflow:/callback'}, owner=True)[0] == 429
    finally:
        for app in created:
            assert api.request('/connect/owner/v1/clients/' + app['id'] + '/remove', 'POST', {'confirmClientId': app['id'], 'confirmNamespace': app['namespace']}, owner=True)[0] == 200
    for client in [CLIENT, other]: assert api.request('/connect/owner/v1/revoke', 'POST', {'clientId': client}, owner=True)[0] == 200
    try:
        status, sessions = api.request('/connect/owner/v1/sessions', owner=True); assert status == 200
        count = len(sessions['sessions']); assert count <= 32
        for number in range(32 - count):
            api.connect(*((CLIENT, REDIRECT) if number % 2 == 0 else (other, callback)))
        status, sessions = api.request('/connect/owner/v1/sessions', owner=True); assert status == 200 and len(sessions['sessions']) == 32
        status, _ = api.connect(CLIENT, REDIRECT, allow_capacity=True); assert status == 429
    finally:
        for client in [CLIENT, other]: assert api.request('/connect/owner/v1/revoke', 'POST', {'clientId': client}, owner=True)[0] == 200
    try:
        tokens = [api.connect(*args)['access_token'] for args in [(CLIENT, REDIRECT), (CLIENT, REDIRECT), (other, callback), (other, callback)]]
        statuses = [api.request('/connect/v1/snapshots', 'POST', {}, token=token)[0] for token in tokens]
        assert statuses == [200] * 4
        extra = api.connect(CLIENT, REDIRECT)['access_token']
        assert api.request('/connect/v1/snapshots', 'POST', {}, token=extra)[0] == 429
    finally:
        for client in [CLIENT, other]: assert api.request('/connect/owner/v1/revoke', 'POST', {'clientId': client}, owner=True)[0] == 200
    report = {'passed': True, 'realShip': True, 'appRegistrations': 8, 'ninthRegistrationRejected': True, 'sessions': 32, 'nextSessionRejected': True, 'globalSnapshots': 4, 'snapshotsPerApp': 2, 'nextSnapshotRejected': True, 'createdEmptySlotsRemoved': len(created), 'otherRegistrationsPreserved': True}
    private_json('reference-bounds.json', report); print(report)


if __name__ == '__main__': run()
