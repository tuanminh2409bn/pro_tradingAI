"""Runtime orchestration; technical gates and trade prices remain deterministic."""

import asyncio
import json

from feature_engine import (
    build_signal_from_features, evaluate_setup_and_veto, features_prompt_block,
    market_analysis_features,
)
from specialist_analysis import run_specialist_analysis


async def run_market_pipeline(features, *, provider, master_prompt, model, correlation_id,
                              timeout_seconds=15):
    features = market_analysis_features(features)
    events = []
    specialists = await run_specialist_analysis(
        features, provider=provider, model=model, correlation_id=correlation_id,
        timeout_seconds=timeout_seconds, audit_sink=events.append,
        master_prompt=master_prompt,
    )
    voted = {**features, 'specialist_outputs': specialists['outputs']}
    gate = evaluate_setup_and_veto(voted, features.get('htf1'), features.get('htf2'))
    voted.update(gate)
    signal = build_signal_from_features(voted)
    audit = {'correlation_id': correlation_id, 'model': model, 'specialists': events,
             'consensus': gate['consensus_audit'], 'aggregator': 'skipped'}
    signal['analysis_audit'] = audit
    if not specialists['complete']:
        return signal

    try:
        summary = features_prompt_block(voted)
        result = await asyncio.wait_for(provider(
            agent='aggregator', model=model, correlation_id=correlation_id,
            messages=[{'role': 'system', 'content': master_prompt + '\nReturn JSON only. Do not invent missing evidence.'},
                      {'role': 'user', 'content': summary + '\nSPECIALIST VOTES: ' +
                       json.dumps(gate['consensus_audit'], sort_keys=True) +
                       '\nSummarize the measured evidence and final_decision only. '
                       'Return exactly {"forecast_text":"a concise explanation"}. '
                       'Do not provide execution prices or alter setup/veto.'}],
            response_format={'type': 'json_object'}, temperature=0.0,
        ), timeout=timeout_seconds)
        text = result.get('forecast_text') if isinstance(result, dict) else None
        if not isinstance(text, str) or not text.strip() or len(text) > 1000 or set(result) != {'forecast_text'}:
            audit['aggregator'] = 'invalid_response'
            return signal
        signal['forecast_text'] = text.strip()
        signal['fallback'] = False
        audit['aggregator'] = 'success'
    except asyncio.TimeoutError:
        audit['aggregator'] = 'timeout'
    except Exception:
        audit['aggregator'] = 'unavailable'
    return signal
