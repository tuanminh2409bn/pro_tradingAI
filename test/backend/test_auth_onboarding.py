"""Self-onboarding grants only the Standard role and preserves existing claims."""
import ast
import asyncio
from pathlib import Path
from types import SimpleNamespace
import unittest
import weakref


class HttpError(Exception):
    def __init__(self, status_code, detail):
        self.status_code, self.detail = status_code, detail


def load_handler(records, writes):
    names = {'complete_standard_onboarding', 'onboard_account'}
    nodes = [n for n in ast.parse(Path('server.py').read_text()).body
             if getattr(n, 'name', None) in names]
    for node in nodes:
        node.decorator_list = []

    async def verify(header):
        if header != 'Bearer owner':
            raise HttpError(401, 'Authentication required')
        return 'owner'

    def grant(uid, claims):
        writes.append((uid, claims))
        records[uid].custom_claims = dict(claims)

    scope = dict(asyncio=asyncio, auth=SimpleNamespace(get_user=lambda uid: records[uid],
                 set_custom_user_claims=grant), HTTPException=HttpError,
                 Header=lambda default=None: default, verified_user_id=verify,
                 refresh_onboarding_quota=lambda uid, role: None,
                 _onboarding_locks=weakref.WeakValueDictionary())
    exec(compile(ast.fix_missing_locations(ast.Module(body=nodes, type_ignores=[])),
                 'server.py', 'exec'), scope)
    return scope


class OnboardingTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.records = {'owner': SimpleNamespace(uid='owner', disabled=False, custom_claims={})}
        self.writes = []
        self.scope = load_handler(self.records, self.writes)

    async def test_no_role_is_granted_standard_and_retry_does_not_write_again(self):
        self.records['owner'].custom_claims = {'locale': 'vi'}
        handler = self.scope['onboard_account']
        self.assertEqual(await handler('Bearer owner'), {'status': 'ready', 'role': 'standard'})
        self.assertEqual(await handler('Bearer owner'), {'status': 'ready', 'role': 'standard'})
        self.assertEqual(self.writes, [('owner', {'locale': 'vi', 'role': 'standard'})])

    async def test_existing_roles_and_admin_are_never_modified(self):
        for role in ('standard', 'verified_partner', 'professional', 'enterprise'):
            for admin in (False, True):
                self.records['owner'].custom_claims = {'role': role, 'admin': admin, 'tenant_id': 'tenant'}
                self.assertEqual((await self.scope['onboard_account']('Bearer owner'))['role'], role)
        self.assertEqual(self.writes, [])

    async def test_unknown_blank_reserved_admin_without_role_and_disabled_fail_closed(self):
        for claims in ({'role': None}, {'role': ''}, {'role': 'reserved_fifth'},
                       {'role': 'surprise'}, {'admin': True}, {'admin': False}):
            self.records['owner'].custom_claims = claims
            with self.assertRaises(HttpError) as error:
                await self.scope['onboard_account']('Bearer owner')
            self.assertEqual(error.exception.status_code, 403)
        self.records['owner'].custom_claims = {}
        self.records['owner'].disabled = True
        with self.assertRaises(HttpError):
            await self.scope['onboard_account']('Bearer owner')
        self.assertEqual(self.writes, [])

    async def test_anonymous_and_provider_failure_never_leak_details(self):
        with self.assertRaises(HttpError) as error:
            await self.scope['onboard_account'](None)
        self.assertEqual(error.exception.status_code, 401)
        del self.records['owner']
        with self.assertRaises(HttpError) as error:
            await self.scope['onboard_account']('Bearer owner')
        self.assertEqual(error.exception.status_code, 503)
        self.assertEqual(error.exception.detail, 'Account onboarding unavailable')

    async def test_same_uid_concurrent_retries_grant_once_and_do_not_reset_quota(self):
        results = await asyncio.gather(*[self.scope['onboard_account']('Bearer owner') for _ in range(80)])
        self.assertEqual(len(self.writes), 1)
        self.assertTrue(all(r == {'status': 'ready', 'role': 'standard'} for r in results))

    async def test_quota_publish_failure_keeps_grant_for_retry_and_never_leaks_error(self):
        def unavailable(uid, role):
            self.assertEqual((uid, role), ('owner', 'standard'))
            raise ValueError('private provider details')
        self.scope['refresh_onboarding_quota'] = unavailable
        with self.assertRaises(HttpError) as error:
            await self.scope['onboard_account']('Bearer owner')
        self.assertEqual(error.exception.status_code, 503)
        self.assertEqual(error.exception.detail, 'Account onboarding unavailable')
        self.assertEqual(self.records['owner'].custom_claims, {'role': 'standard'})
        self.scope['refresh_onboarding_quota'] = lambda uid, role: None
        self.assertEqual(await self.scope['onboard_account']('Bearer owner'), {'status': 'ready', 'role': 'standard'})
        self.assertEqual(len(self.writes), 1)
