# ProTrading AI VIP V2.1 - Authoritative Requirements

Status: draft for stakeholder sign-off. This document consolidates the V2.1 Master PDF and the Tab 1 correction PDF. It does not mark implementation progress; `tasks/acceptance-matrix.md` holds evidence status.

## Source precedence

1. The Tab 1 correction applies only to Trading Room and wins any direct conflict with V2.1 Master.
2. V2.1 additions continue to apply when the correction does not contradict them.
3. The client is a renderer. Analytical labels, colors, coordinates, probabilities, stage decisions, and risk decisions originate from validated backend output.
4. Unsupported analysis is omitted. It must never be fabricated to make a chart appear complete.
5. Paper and live execution are distinct products. Live broker execution requires explicit approval and separate acceptance evidence.

## A. Architecture and cross-cutting requirements

| ID | Requirement | Source |
|---|---|---|
| ARC-01 | Flutter renders validated backend geometry and must not calculate analytical structures or invent labels/colors. | Master p1; Correction pp2-3 |
| ARC-02 | FastAPI is the authoritative analysis and execution-policy boundary. | Master p1 |
| ARC-03 | Analysis follows Soft Alert then Hard Alert; Layer 4 and execution are unavailable until price touches a valid zone and an approved confirmation candle exists. | Master pp1,7; Correction p9 |
| ARC-04 | Broker keys/credentials are entered only through the approved Web flow and relayed by the backend; mobile must not expose broker credential forms. | Master pp1,10 |
| ARC-05 | AI output is deterministic for identical market inputs; DeepSeek uses temperature 0 and fallback contains no randomness. | Master p7; Correction p10 |
| ARC-06 | Shared cache hits do not call the LLM and cache misses use single-flight protection. | Master pp7,10 |
| ARC-07 | LLM/provider failures yield a labeled, deterministic, user-friendly fallback and never raw provider JSON/errors. | Master pp3,7,10 |
| ARC-08 | User data, roles, Admin operations, broker actions, risk decisions, and money-related operations are authorized server-side from verified identity. | Master pp1,8-10 |
| ARC-09 | Web and the contractually approved mobile targets must pass the same applicable acceptance behavior. | Master p11 |

## B. Master checklist - 16 contractual outcomes

| ID | Requirement | Source |
|---|---|---|
| M-01 | Position P&L always uses the mark price bound to that position's symbol. | Master pp2,10 |
| M-02 | Symbol change resets Execution Panel levels/state and loads correct tick size, pip value, spread, swap, and lot constraints. | Master pp2,10 |
| M-03 | Chart supports Y-axis price scale, X-axis time scale, wheel/pinch zoom, center pan, and correct layer remapping. | Master pp2,10 |
| M-04 | Normal candles are only `#00FF7F` or `#FF3B30`; other colors require real backend Layer 3 evidence. | Master pp2,4,10 |
| M-05 | Mode matrix is Scalping M5/M15/H1, Day Trading M15/H1/H4, Swing H1/H4/D1; out-of-mode frames are disabled. | Master pp2,5,10 |
| M-06 | Analyze initially publishes waiting zones/forecast only; Entry/SL/TP appear only after a valid Hard Alert. | Master pp2,10 |
| M-07 | Three specialist agents plus one aggregator reach at least 75% consensus, enforce HTF Veto, and use Redis caching. | Master pp7,10 |
| M-08 | Exactly one SL is derived from trap/swing structure. | Master pp3-4,10 |
| M-09 | TP allocation supports TP1/TP2/TP3 volume distribution; selecting TP3 dims TP1/TP2 to 40%. | Master pp3-4,10 |
| M-10 | SIG1 uses quadratic and SIG2 cubic Bezier, dashed glow, and both terminate exactly at TP3. | Master pp3-5,10 |
| M-11 | Entry/SL/TP labels are compact badges at the right price axis without large chart-obscuring highlights. | Master pp3-4,10 |
| M-12 | HTF trend uses valid HH/HL or LH/LL histories and HTF legend navigation opens the selected parent timeframe. | Master pp3,5,10 |
| M-13 | AI chat/analysis hides raw 402/429/provider errors and returns a friendly fallback. | Master pp3,7,10 |
| M-14 | First-run Sync Gate appears; unlinked manual users see the Journal funnel lock/CTA. | Master pp3,8,10 |
| M-15 | Secure Admin prompt and Radar watchlist changes take effect without rebuilding the client. | Master pp9-10 |
| M-16 | Mobile has no broker credential form; approved Web/API relay owns broker linking and any separately approved broker execution. | Master pp1,10 |

## C. Mandatory analysis request and response contracts

### Recorded conflict resolutions

- The correction's later §7.3 instruction that the backend must fetch and validate trusted HTF history overrides the earlier example that sends client candle arrays as authoritative input. The external request therefore carries only market selection; the server owns the three validated candle sets.
- Wire values for `execution_tf` follow both PDF payload examples: `5`, `15`, and `60`. UI labels remain M5, M15, and H1.
- The correction fixes Entry/SL/TP colors while its abbreviated Layer 4 JSON omits their color fields. To satisfy the iron rule that Flutter receives colors from the backend, the canonical Layer 4 adds required `entry_color`, `sl_color`, and `tp_color` fields with the corrected constants.
- Render items add required `evidence` provenance and backend Hex colors where the abbreviated JSON omits them. These are non-render-decision metadata/extensions required by the correction's truthfulness and acceptance-traceability rules.
- The correction requires probability to come from real backtest evidence or be hidden. `layer4_execution.prob` is therefore nullable; consensus percentage is not silently presented as win probability.
- The repository-wide cache key remains `analysis:{SYMBOL}:{timeframe}:{last_closed_candle_timestamp}`. Because each mode has a unique execution timeframe, adding `trading_mode` would be redundant and would conflict with the fixed shared-cache contract.

### Request

- Identity is derived from the Firebase ID token, not `userId` in JSON.
- Required market fields: `symbol`, `trading_mode`, `execution_tf`.
- The only valid mode/execution pairs are Scalping/`5`, Day Trading/`15`, and Swing/`60`.
- Server obtains and validates three closed-candle sets:
  - Scalping: M5 120, M15 120, H1 150.
  - Day Trading: M15 120, H1 120, H4 150.
  - Swing: H1 120, H4 120, D1 150.
- Every candle has `t`, `o`, `h`, `l`, `c`, `v`.
- Account context is private and applied after shared market analysis; it must not pollute shared cache artifacts.

### Response

- Required envelope: `chart_id`, `setup_ready`, `veto`, `veto_data`, `fallback`, `forecast_text`, `layers`.
- `chart_id` is `{SYMBOL}_{TF}_{TIMESTAMP}` with underscores.
- `layers` is an object with `layer1_structural`, `layer2_trap`, `layer3_candle`, `layer4_execution`, and `layer5_overlay`.
- Every analytical color is a Hex string supplied by the backend.
- Soft/Veto response has no active Layer 4 and no executable Entry/SL/TP values.
- Every analytical component carries sufficient evidence/provenance to trace it to market/news inputs.
- Backend validates output before persistence; Dart rejects malformed payloads safely.

## D. Tab 1 - 27 render components

| ID | Component | Exact requirement | Source |
|---|---|---|---|
| R-01 | Dashed structural line | Arbitrary `(x1,y1)` to `(x2,y2)`, gold/orange Hex, supports diagonals. | Master p4; Correction p6 |
| R-02 | Solid structural box | Bullish OB `#00FF7F`, bearish OB `#FF4500`, FVG/Mitigation `#BA55D3`; fill 8%, border 40%. | Master p4; Correction p6 |
| R-03 | Bordered box | Transparent fill with `#F0E68C` border. | Correction pp4,6 |
| R-04 | Structural label | Backend text, maximum four characters, attached to the box/line without covering candles. | Master p4; Correction p6 |
| R-05 | `$$$` tag | Backend-supplied text, red or gold, at a measured liquidity pool. | Master p4; Correction pp4,6 |
| R-06 | `LIQ` tag | Backend-supplied gray liquidity marker and zone where specified. | Correction pp4,6 |
| R-07 | Trap arrow | Backend direction and label, maximum eight characters. | Master p4; Correction p6 |
| R-08 | STOP volume tag | Purple STOP only when measured `volume_spike=true`. | Master p4; Correction pp6,13 |
| R-09 | Default candle fill | Bull `#00FF7F`, bear `#FF3B30`. | Master p4; Correction p7 |
| R-10 | Climax candle | Purple `#8A2BE2` only for measured buying/selling climax. | Master p4; Correction pp7,13 |
| R-11 | ND/NS candle | White or corrected gray variant only with backend evidence. | Master p4; Correction p7 |
| R-12 | Candle text | Maximum two characters above the candle. | Correction p7 |
| R-13 | Spread border | Gold `#FFD700` candle border when backend `spread_alert=true`. | Master p4; Correction p7 |
| R-14 | Divergence arrow | Small backend-directed arrow on the relevant candle. | Correction p7 |
| R-15 | Stage gate | Layer 4 exists only when `setup_ready=true` and `veto=false`. | Master p4; Correction pp7,9 |
| R-16 | Entry line | Solid 1.5 px, `#0000FF`. | Correction pp2,7 |
| R-17 | SL line | One dashed 1.5 px line, `#FF0000`. | Correction pp2,7 |
| R-18 | TP lines | TP1/2/3 dashed 1.0 px, `#00FF00`; inactive earlier targets dim to 40%. | Correction pp2,7 |
| R-19 | Partial TP | User-configured volume allocation totals 100% and is honored by execution/simulation. | Master pp3-4; Correction p7 |
| R-20 | Probability badge | Real backtest probability or hidden/null; consensus percentage must not be presented as win probability. | Master p4; Correction p7 |
| R-21 | Momentum signs | Large arrow plus backend text up to three characters. | Correction pp2,7 |
| R-22 | SIG paths | SIG1 quadratic, SIG2 cubic, dashed/glowing, terminate at TP3. | Master pp3-5; Correction pp2,7 |
| R-23 | Ghost box | Backend Hex, danger/magnet semantics, 15% opacity, derived from real HTF zone. | Master p5; Correction p8 |
| R-24 | Ghost interaction | Hit test provides the specified tooltip/zoom behavior. | Correction p8 |
| R-25 | Red Zone | Actual `start_time` and `duration_min`, event label and live countdown in future chart space. | Master p5; Correction p8 |
| R-26 | Wyckoff watermark | Large subtle text from measured Wyckoff analysis; omit when unknown. | Master p5; Correction pp8,13 |
| R-27 | HTF legend | Shows HTF1/HTF2 trend and opens the selected timeframe on click/tap. | Master p5; Correction p8 |

## E. Tab 1 - eight functional requirements

| ID | Requirement | Source |
|---|---|---|
| F-01 | Exclusive Sync Gate: only the approved Verified Partner role can see/use broker API linking; backend enforces the same claim. | Correction p11 |
| F-02 | Smart popup: eligible unlinked users receive a dismissible, remembered broker-sync prompt. | Correction p11 |
| F-03 | Real-time account data: Balance, Equity, Leverage, Swap, and Spread come from real authorized sources or display unavailable. | Correction p11 |
| F-04 | Input constraint: Balance, risk/trade, and max daily loss are required before chart use. | Correction p11 |
| F-05 | Three-timeframe matrix and disabled out-of-mode frames work on Web/mobile. | Correction pp11-12 |
| F-06 | Forecast panel is below the chart; Soft Alert exposes no Entry/SL/TP in the side panel. | Correction p12 |
| F-07 | Level 1 vibrates/pushes on waiting-zone entry; Level 2 sounds/flashes/pushes on Hard Alert. | Master p8; Correction p12 |
| F-08 | Lot sizing uses Entry-SL and risk%; realized plus floating daily loss locks analysis/execution and requires an AI/rule-based session review before unlock. | Master p8; Correction p12 |

## F. Tabs 2-7

| ID | Requirement | Source |
|---|---|---|
| J-01 | Unlinked/manual Journal is blurred with the approved partner CTA. | Master p8 |
| J-02 | Journal records real Swap, Commission, and Slippage with source/currency. | Master p8 |
| J-03 | Loss-time heatmap and playable AI TTS warn about measured behavior patterns. | Master p8 |
| N-01 | Approved ForexFactory-equivalent and Twitter/X sources produce deduplicated -100..100 sentiment with provenance. | Master p8 |
| N-02 | Dedicated What-If scenarios return structured projected reactions and invalidation/risk notes. | Master p8 |
| N-03 | HIGH-impact events propagate scheduled Red Zones and alerts into Tab 1. | Master p8 |
| B-01 | Historical candles replay one bar at a time at supported speeds including x5/x10. | Master p8 |
| B-02 | No-Repaint prevents access to future bars for AI and simulation. | Master p8 |
| B-03 | Simulated max loss locks the session until the user acknowledges the generated review. | Master p8 |
| C-01 | Authenticated community supports posts, discussions, comments, reactions, and sharing. | Master p8 |
| C-02 | Privacy Masker converts real monetary amounts to permitted percentage growth before sharing. | Master p8 |
| C-03 | Leaderboard uses verified percentage growth and real unit volume. | Master p8 |
| REF-01 | Each user receives a canonical referral link and QR code. | Master p8 |
| REF-02 | Approved Marketing Kit media is personalized with the user's code before download. | Master p8 |
| REF-03 | F1/F2 commission ledger and withdrawal requests flow to authorized Super Admin review. | Master p8 |
| ROLE-01 | Standard: two requests/week and approved AdMob placements. | Master p8 |
| ROLE-02 | Verified Partner: unlimited realtime signals and multi-timeframe access under approved partner rules. | Master p8 |
| ROLE-03 | Professional: validated IAP entitlement and 50 requests/day. | Master p8 |
| ROLE-04 | Enterprise: 300 requests/day and master/sub-account risk management. | Master pp8-9 |
| ROLE-05 | Fifth role is reserved pending stakeholder clarification; no behavior may be invented. | Master p8 ambiguity |

## G. Admin and platform operations

| ID | Requirement | Source |
|---|---|---|
| ADM-01 | Admin-only master prompt editor saves to `AdminSettings/ai_config.ai_master_prompt`; backend uses a five-minute cache and has no operational hard-coded prompt dependency. | Master p9 |
| ADM-02 | Radar scans an Admin-configured 50-100 asset watchlist continuously using Redis-backed workers: volume/barrier filter first, DeepSeek confirmation second, FCM deep link last. | Master p9 |
| ADM-03 | Admin-only manual push targets all users or approved role/country/device segments, honors opt-out, and records delivery audit. | Master p9 |
| ADM-04 | `data_masker.py` removes/pseudonymizes PII before Data Lake export under approved consent/retention rules. | Master p9 |
| ADM-05 | Global risk, kill switch, approvals, watchlist, and service status are enforced by backend behavior, not cosmetic UI state. | Master pp9-10 |

## H. Evidence required for acceptance

- Automated: Python unit/integration tests, Dart unit/widget/golden tests, Firestore Emulator rules tests, schema validation, security abuse cases, concurrency and load tests.
- Runtime: authenticated Web and approved mobile devices; console/network clean; screenshots/video for gestures, all 27 components, two-level sound/vibration/push, role gates, cutoff review, and deep links.
- Data provenance: sampled volume/HTF/news/broker values traced to approved sources.
- Release identity: commit, build number, environment, provider configuration version, test user role, symbol/timeframe, chart/signal ID, and timestamp.
- Production: only after staging passes, rollback is rehearsed, and deployment approval is recorded.

## I. Unresolved contractual decisions

1. Identify the fifth account role.
2. Confirm whether 100% requires live MetaApi execution or paper execution for this release.
3. Approve providers/licensing for economic calendar, Twitter/X, historical bars, TTS, IAP, AdMob, and Data Lake.
4. Define role-country-device segments, privacy consent, retention, export, and deletion policy.
5. Define F1/F2 commission rates, reward currency, minimum withdrawal, and Admin SLA.
6. Confirm Android/iOS/Web acceptance targets and required store distribution channels.
