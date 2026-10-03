"""Cost controls run offline; no real provider, token or billable request."""

import ast
import contextlib
import hashlib
import io
import json
import unittest
from pathlib import Path
from types import SimpleNamespace

import httpx


def load_controls():
    tree = ast.parse((Path(__file__).resolve().parents[2] / 'server.py').read_text())
    nodes = [node for node in tree.body if isinstance(node, ast.FunctionDef)
             and node.name in {'_bounded_llm_request', '_record_llm_usage'}]
    namespace = {'json': json}
    exec(compile(ast.fix_missing_locations(ast.Module(body=nodes, type_ignores=[])),
                 'server.py', 'exec'), namespace)
    return namespace


class DeepSeekCostControlTests(unittest.TestCase):
    def test_analysis_and_chat_have_hard_output_and_thinking_limits(self):
        build = load_controls()['_bounded_llm_request']
        for analysis, expected in ((True, 1500), (False, 600)):
            payload = build('deepseek-flash', [{'role': 'user', 'content': 'Evidence'}],
                            analysis=analysis)
            self.assertEqual(payload['max_tokens'], expected)
            self.assertEqual(payload['thinking'], {'type': 'disabled'})
            self.assertEqual(payload['temperature'], 0.0)
            self.assertEqual('response_format' in payload, analysis)

    def test_prompt_limit_is_total_utf8_bytes_without_silent_truncation(self):
        build = load_controls()['_bounded_llm_request']
        messages = [{'role': 'system', 'content': 'a' * 12000},
                    {'role': 'user', 'content': 'b' * 12000}]
        self.assertEqual(build('deepseek-flash', messages, analysis=True)['messages'], messages)
        for bad in (messages + [{'role': 'user', 'content': 'c'}],
                    [{'role': 'system', 'content': 'あ' * 8001}]):
            with self.assertRaises(ValueError):
                build('deepseek-flash', bad, analysis=True)

    def test_invalid_content_never_enters_provider_payload(self):
        build = load_controls()['_bounded_llm_request']
        for messages in ([], [{'role': 'tool', 'content': 'x'}],
                         [{'role': 'user', 'content': []}],
                         [{'role': 'user', 'content': 'x', 'other': 'secret'}]):
            with self.assertRaises(ValueError):
                build('deepseek-flash', messages, analysis=False)

    def test_usage_log_has_only_numeric_counts_and_closed_call_labels(self):
        record = load_controls()['_record_llm_usage']
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            record('smc', {'prompt_tokens': 100, 'completion_tokens': 20,
                          'total_tokens': 120, 'prompt_cache_hit_tokens': 80,
                          'prompt_cache_miss_tokens': 20,
                          'completion_tokens_details': {'reasoning_tokens': 0},
                          'api_key': 'DO_NOT_LOG', 'content': 'PRIVATE_PROMPT'})
        logged = json.loads(output.getvalue().split('] ', 1)[1])
        self.assertEqual(logged['call'], 'smc')
        self.assertEqual(logged['prompt_tokens'], 100)
        self.assertEqual(logged['completion_tokens'], 20)
        self.assertEqual(logged['reasoning_tokens'], 0)
        self.assertNotIn('DO_NOT_LOG', output.getvalue())
        self.assertNotIn('PRIVATE_PROMPT', output.getvalue())

    def test_unknown_or_invalid_usage_is_not_fabricated_as_zero(self):
        record = load_controls()['_record_llm_usage']
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            record('chat', {'prompt_tokens': True, 'completion_tokens': -1,
                            'total_tokens': '999', 'completion_tokens_details': []})
            record('chat', None)
        for line in output.getvalue().splitlines():
            logged = json.loads(line.split('] ', 1)[1])
            self.assertIsNone(logged['prompt_tokens'])
            self.assertIsNone(logged['completion_tokens'])
            self.assertIsNone(logged['total_tokens'])

    def test_paid_provider_paths_use_the_controls_and_disable_sdk_retries(self):
        tree = ast.parse((Path(__file__).resolve().parents[2] / 'server.py').read_text())
        for name in ('_run_analysis_pipeline', 'ai_chat'):
            function = next(node for node in tree.body
                            if isinstance(node, ast.AsyncFunctionDef) and node.name == name)
            source = ast.unparse(function)
            self.assertIn('_bounded_llm_request(', source)
            self.assertIn('_record_llm_usage(', source)
        chat = next(node for node in tree.body if isinstance(node, ast.AsyncFunctionDef)
                    and node.name == 'ai_chat')
        self.assertIn('max_retries=0', ast.unparse(chat))


class PaidAnalysisTransportTests(unittest.IsolatedAsyncioTestCase):
    async def test_analysis_transport_is_bounded_logs_usage_and_rejects_large_prompt(self):
        namespace = load_controls()
        tree = ast.parse((Path(__file__).resolve().parents[2] / 'server.py').read_text())
        node = next(node for node in tree.body if isinstance(node, ast.AsyncFunctionDef)
                    and node.name == '_run_analysis_pipeline')
        calls = []
        prompt = 'Measured evidence'

        async def transport(request):
            payload = json.loads(request.content)
            calls.append(payload)
            self.assertEqual(payload['max_tokens'], 1500)
            self.assertEqual(payload['thinking'], {'type': 'disabled'})
            self.assertEqual(payload['response_format'], {'type': 'json_object'})
            return httpx.Response(200, json={
                'choices': [{'message': {'content': '{"result":"ok"}'}}],
                'usage': {'prompt_tokens': 10, 'completion_tokens': 5, 'total_tokens': 15},
            })

        async def pipeline(features, *, provider, **kwargs):
            return await provider(agent='smc', model=kwargs['model'],
                                  messages=[{'role': 'user', 'content': prompt}])

        async def master():
            return 'Master'

        namespace.update(
            httpx=SimpleNamespace(AsyncClient=lambda **kwargs: httpx.AsyncClient(
                **kwargs, transport=httpx.MockTransport(transport))),
            hashlib=hashlib, DEEPSEEK_API_KEY='offline-only',
            DEEPSEEK_MODEL='deepseek-flash', get_chat_master_prompt=master,
            analysis_cache_key=lambda *args: 'analysis:EURUSD:5:100',
            run_market_pipeline=pipeline,
        )
        exec(compile(ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[])),
                     'server.py', 'exec'), namespace)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = await namespace['_run_analysis_pipeline']('EURUSD', '5',
                                                              {'analysis_available': True})
        self.assertEqual(result, {'result': 'ok'})
        self.assertEqual(len(calls), 1)
        self.assertEqual(json.loads(output.getvalue().split('] ', 1)[1])['total_tokens'], 15)
        prompt = 'a' * 24001
        with self.assertRaises(ValueError):
            await namespace['_run_analysis_pipeline']('EURUSD', '5', {'analysis_available': True})
        self.assertEqual(len(calls), 1, 'Rejected input must never make a paid HTTP request')


if __name__ == '__main__':
    unittest.main()
