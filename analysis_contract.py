"""Pure validation and legacy adaptation for the Appendix-8 V2.1 contract."""

from __future__ import annotations

import re
from copy import deepcopy
from math import isfinite
from typing import Any


_MODE_EXECUTION_TF = {
    "scalping": "5",
    "day_trading": "15",
    "swing": "60",
}
_MODE_ALLOWED_TF = {
    "scalping": {"5", "15", "60"},
    "day_trading": {"15", "60", "240"},
    "swing": {"60", "240", "1440"},
}
_HEX_COLOR = re.compile(r"^#[0-9A-Fa-f]{6}$")
_CHART_ID = re.compile(
    r"^[A-Z0-9._-]{2,20}_(?:M5|M15|H1|H4|D1|5|15|60|240|1440|UNKNOWN)_[1-9][0-9]*$"
)
_TOP_LEVEL_KEYS = {
    "chart_id",
    "setup_ready",
    "veto",
    "veto_data",
    "fallback",
    "forecast_text",
    "layers",
}
_LAYER_KEYS = {
    "layer1_structural",
    "layer2_trap",
    "layer3_candle",
    "layer4_execution",
    "layer5_overlay",
}


def _number(value: Any) -> bool:
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and isfinite(float(value))
    )


def _positive_number(value: Any) -> bool:
    return _number(value) and float(value) > 0


def _positive_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def _hex(value: Any) -> bool:
    return isinstance(value, str) and _HEX_COLOR.fullmatch(value) is not None


def _unexpected_keys(
    value: dict[str, Any], allowed: set[str], path: str, errors: list[str]
) -> None:
    unexpected = sorted(value.keys() - allowed)
    if unexpected:
        errors.append(f"{path} has unexpected keys: {unexpected}")


def validate_analysis_request_v21(payload: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(payload, dict):
        return ["request must be an object"]
    allowed = {"symbol", "trading_mode", "execution_tf"}
    _unexpected_keys(payload, allowed, "request", errors)
    for key in sorted(allowed):
        if not isinstance(payload.get(key), str) or not payload[key].strip():
            errors.append(f"{key} is required")

    symbol = str(payload.get("symbol") or "")
    if re.fullmatch(r"[A-Z0-9._-]{2,20}", symbol) is None:
        errors.append("symbol must be normalized uppercase market text")
    mode = str(payload.get("trading_mode") or "")
    timeframe = str(payload.get("execution_tf") or "")
    expected = _MODE_EXECUTION_TF.get(mode)
    if expected is None:
        errors.append("trading_mode is invalid")
    elif timeframe != expected:
        errors.append(f"execution_tf must be {expected} for {mode}")
    return errors


def validate_client_analysis_request(payload: Any) -> list[str]:
    """Validate the Firestore queue envelope before scheduling provider work."""
    if not isinstance(payload, dict):
        return ["request must be an object"]
    errors: list[str] = []
    allowed = {
        "symbol", "timeframe", "execution_tf", "trading_mode", "userId",
        "status", "requestedAt",
    }
    _unexpected_keys(payload, allowed, "request", errors)
    uid = payload.get("userId")
    if not isinstance(uid, str) or not 1 <= len(uid) <= 128:
        errors.append("userId is invalid")
    symbol = payload.get("symbol")
    if not isinstance(symbol, str) or re.fullmatch(r"[A-Z0-9._-]{2,20}", symbol) is None:
        errors.append("symbol is invalid")
    mode = payload.get("trading_mode")
    timeframe = payload.get("timeframe")
    if (
        not isinstance(mode, str)
        or not isinstance(timeframe, str)
        or timeframe not in _MODE_ALLOWED_TF.get(mode, set())
    ):
        errors.append("mode/timeframe is invalid")
    if payload.get("execution_tf") != timeframe:
        errors.append("execution_tf mismatch")
    if payload.get("status") != "PENDING":
        errors.append("status is invalid")
    return errors


def _validate_evidence(item: dict[str, Any], path: str, errors: list[str]) -> None:
    evidence = item.get("evidence")
    if not isinstance(evidence, dict):
        errors.append(f"{path}.evidence is required")
        return
    _unexpected_keys(
        evidence, {"source", "source_id", "timestamp"}, f"{path}.evidence", errors
    )
    if not isinstance(evidence.get("source"), str) or not evidence["source"].strip():
        errors.append(f"{path}.evidence.source is required")
    if not isinstance(evidence.get("source_id"), str) or not evidence["source_id"].strip():
        errors.append(f"{path}.evidence.source_id is required")
    if not _positive_int(evidence.get("timestamp")):
        errors.append(f"{path}.evidence.timestamp is invalid")


def _validate_layer1_item(item: dict[str, Any], path: str, errors: list[str]) -> None:
    item_type = item.get("type")
    if item_type == "dashed_line":
        allowed = {"type", "color", "x1", "y1", "x2", "y2", "label", "evidence"}
        _unexpected_keys(item, allowed, path, errors)
        if item.get("color") not in {"#FFD700", "#FF8C00"}:
            errors.append(f"{path}.color must be #FFD700 or #FF8C00")
        if not (
            _positive_int(item.get("x1"))
            and _number(item.get("y1"))
            and _positive_int(item.get("x2"))
            and _number(item.get("y2"))
        ):
            errors.append(f"{path} dashed line requires two points")
        elif item["x2"] <= item["x1"]:
            errors.append(f"{path}.x2 must be after x1")
    elif item_type in {"solid_box", "bordered_box"}:
        allowed = {
            "type", "color", "x", "x_end", "y_top", "y_bottom", "label", "evidence"
        }
        _unexpected_keys(item, allowed, path, errors)
        expected_colors = (
            {"#F0E68C"}
            if item_type == "bordered_box"
            else {"#00FF7F", "#FF4500", "#BA55D3"}
        )
        if item.get("color") not in expected_colors:
            errors.append(f"{path}.color is invalid for {item_type}")
        if not (
            _positive_int(item.get("x"))
            and _positive_int(item.get("x_end"))
            and _number(item.get("y_top"))
            and _number(item.get("y_bottom"))
        ):
            errors.append(f"{path} box requires x/x_end/y_top/y_bottom")
        elif item["x_end"] <= item["x"]:
            errors.append(f"{path}.x_end must be after x")
    else:
        errors.append(f"{path}.type is invalid for Layer 1")

    label = item.get("label")
    if label is not None and (
        not isinstance(label, str) or not label or len(label) > 4
    ):
        errors.append(f"{path}.label must contain at most four characters")
    _validate_evidence(item, path, errors)


def _validate_layer2_item(item: dict[str, Any], path: str, errors: list[str]) -> None:
    item_type = item.get("type")
    common = {"type", "color", "x", "y", "evidence"}
    if item_type in {"text_tag", "volume_tag"}:
        _unexpected_keys(item, common | {"text", "background_color"}, path, errors)
        text = item.get("text")
        if not isinstance(text, str) or not text or len(text) > 8:
            errors.append(f"{path}.text must contain one to eight characters")
        if item_type == "volume_tag" and (
            text != "STOP" or item.get("color") != "#8A2BE2"
        ):
            errors.append(f"{path} volume_tag must be purple STOP")
        if text == "$$$" and item.get("color") not in {"#FF0000", "#FFD700"}:
            errors.append(f"{path} $$$ color must be #FF0000 or #FFD700")
        if text == "LIQ" and item.get("color") != "#A9A9A9":
            errors.append(f"{path} LIQ color must be #A9A9A9")
        background = item.get("background_color")
        if background is not None and not _hex(background):
            errors.append(f"{path}.background_color must be a #RRGGBB Hex color")
    elif item_type == "arrow":
        _unexpected_keys(item, common | {"direction", "label"}, path, errors)
        if item.get("direction") not in {"up", "down"}:
            errors.append(f"{path}.direction must be up or down")
        label = item.get("label")
        if not isinstance(label, str) or not label or len(label) > 8:
            errors.append(f"{path}.label must contain one to eight characters")
    else:
        errors.append(f"{path}.type is invalid for Layer 2")
    if not _hex(item.get("color")):
        errors.append(f"{path}.color must be a #RRGGBB Hex color")
    if not _positive_int(item.get("x")) or not _number(item.get("y")):
        errors.append(f"{path} requires x/y coordinates")
    _validate_evidence(item, path, errors)


def _validate_layer3_item(item: dict[str, Any], path: str, errors: list[str]) -> None:
    allowed = {
        "timestamp", "fill_color", "text", "border", "divergence",
        "divergence_color", "evidence",
    }
    _unexpected_keys(item, allowed, path, errors)
    if not _positive_int(item.get("timestamp")):
        errors.append(f"{path}.timestamp is invalid")
    fill = item.get("fill_color")
    if fill is not None and fill not in {"#8A2BE2", "#A9A9A9"}:
        errors.append(f"{path}.fill_color must be #8A2BE2 or #A9A9A9")
    text = item.get("text")
    if text is not None and (
        not isinstance(text, str) or not text or len(text) > 2
    ):
        errors.append(f"{path}.text must contain at most two characters")
    border = item.get("border")
    if border is not None and border != "#FFD700":
        errors.append(f"{path}.border must be #FFD700")
    divergence = item.get("divergence")
    if divergence is not None and divergence not in {"up", "down"}:
        errors.append(f"{path}.divergence must be up or down")
    divergence_color = item.get("divergence_color")
    if divergence is not None and not _hex(divergence_color):
        errors.append(f"{path}.divergence_color must be a #RRGGBB Hex color")
    elif divergence_color is not None and not _hex(divergence_color):
        errors.append(f"{path}.divergence_color must be a #RRGGBB Hex color")
    if fill is None and text is None and border is None and divergence is None:
        errors.append(f"{path} must contain a candle override")
    _validate_evidence(item, path, errors)


def _validate_momentum(value: Any, path: str, errors: list[str]) -> None:
    if not isinstance(value, dict):
        errors.append(f"{path} is required")
        return
    _unexpected_keys(value, {"arrow", "label", "color"}, path, errors)
    if value.get("arrow") not in {"up", "down"}:
        errors.append(f"{path}.arrow must be up or down")
    label = value.get("label")
    if not isinstance(label, str) or len(label) != 3:
        errors.append(f"{path}.label must contain exactly three characters")
    if not _hex(value.get("color")):
        errors.append(f"{path}.color must be a #RRGGBB Hex color")


def _validate_curve(
    curve: Any,
    index: int,
    entry: Any,
    tp3: Any,
    errors: list[str],
) -> None:
    path = f"layers.layer4_execution.curves[{index}]"
    if not isinstance(curve, dict):
        errors.append(f"{path} must be an object")
        return
    _unexpected_keys(curve, {"id", "type", "style", "color", "points"}, path, errors)
    expected_id = "SIG_1" if index == 0 else "SIG_2"
    expected_type = "bezier_quadratic" if index == 0 else "bezier_cubic"
    expected_color = "#00F0FF" if index == 0 else "#1E90FF"
    expected_points = 3 if index == 0 else 4
    if curve.get("id") != expected_id:
        errors.append(f"{path}.id must be {expected_id}")
    if curve.get("type") != expected_type:
        errors.append(f"{path}.type must be {expected_type}")
    if curve.get("style") != "dashed":
        errors.append(f"{path}.style must be dashed")
    if curve.get("color") != expected_color:
        errors.append(f"{path}.color must be {expected_color}")
    points = curve.get("points")
    if not isinstance(points, list) or len(points) != expected_points:
        errors.append(f"{path}.points must contain exactly {expected_points} points")
        return
    for point_index, point in enumerate(points):
        point_path = f"{path}.points[{point_index}]"
        if not isinstance(point, dict):
            errors.append(f"{point_path} must be an object")
            continue
        _unexpected_keys(point, {"x", "y"}, point_path, errors)
        if not _positive_int(point.get("x")) or not _number(point.get("y")):
            errors.append(f"{point_path} requires x/y coordinates")
    if isinstance(points[0], dict) and points[0].get("y") != entry:
        errors.append(f"{path} must start at Entry")
    if isinstance(points[-1], dict) and points[-1].get("y") != tp3:
        errors.append(f"{path} must terminate exactly at TP3")


def _validate_execution(layer: Any, errors: list[str]) -> None:
    path = "layers.layer4_execution"
    if not isinstance(layer, dict):
        errors.append("Hard Setup requires layers.layer4_execution")
        return
    allowed = {
        "active", "entry", "entry_color", "sl", "sl_color", "tp", "tp_color",
        "prob", "momentum", "curves",
    }
    _unexpected_keys(layer, allowed, path, errors)
    missing = sorted(allowed - layer.keys())
    if missing:
        errors.append(f"{path} missing keys: {missing}")
    if layer.get("active") is not True:
        errors.append(f"{path}.active must be true")
    entry = layer.get("entry")
    stop = layer.get("sl")
    targets = layer.get("tp")
    if not _positive_number(entry) or not _positive_number(stop):
        errors.append("Hard Setup requires positive Entry and SL")
    if not isinstance(targets, list) or len(targets) != 3 or not all(
        _positive_number(target) for target in targets
    ):
        errors.append("layer4_execution.tp must contain exactly three positive targets")
        tp3 = None
    else:
        tp3 = targets[2]
    if layer.get("entry_color") != "#0000FF":
        errors.append("layer4_execution.entry_color must be #0000FF")
    if layer.get("sl_color") != "#FF0000":
        errors.append("layer4_execution.sl_color must be #FF0000")
    if layer.get("tp_color") != "#00FF00":
        errors.append("layer4_execution.tp_color must be #00FF00")
    probability = layer.get("prob")
    if probability is not None and (
        not _number(probability) or not 0 <= float(probability) <= 100
    ):
        errors.append("layer4_execution.prob must be null or between 0 and 100")
    _validate_momentum(layer.get("momentum"), f"{path}.momentum", errors)

    momentum = layer.get("momentum")
    direction = momentum.get("arrow") if isinstance(momentum, dict) else None
    if _positive_number(entry) and _positive_number(stop) and isinstance(targets, list) and len(targets) == 3:
        if direction == "up" and not (stop < entry < targets[0] < targets[1] < targets[2]):
            errors.append(f"{path} up levels must satisfy SL < Entry < TP1 < TP2 < TP3")
        if direction == "down" and not (stop > entry > targets[0] > targets[1] > targets[2]):
            errors.append(f"{path} down levels must satisfy SL > Entry > TP1 > TP2 > TP3")

    curves = layer.get("curves")
    if not isinstance(curves, list) or len(curves) != 2:
        errors.append("layer4_execution.curves must contain exactly SIG_1 and SIG_2")
    elif tp3 is not None:
        for index, curve in enumerate(curves):
            _validate_curve(curve, index, entry, tp3, errors)


def _validate_layer5_item(item: dict[str, Any], path: str, errors: list[str]) -> None:
    item_type = item.get("type")
    if item_type == "ghost_box":
        allowed = {
            "type", "opacity", "color", "x", "x_end", "y_top", "y_bottom",
            "tooltip", "evidence",
        }
        _unexpected_keys(item, allowed, path, errors)
        if item.get("opacity") != 0.15:
            errors.append(f"{path}.opacity must be 0.15")
        if not (
            _positive_int(item.get("x"))
            and _positive_int(item.get("x_end"))
            and _number(item.get("y_top"))
            and _number(item.get("y_bottom"))
        ):
            errors.append(f"{path} ghost_box requires x/x_end/y_top/y_bottom")
        elif item["x_end"] <= item["x"]:
            errors.append(f"{path}.x_end must be after x")
        tooltip = item.get("tooltip")
        if not isinstance(tooltip, str) or not tooltip or len(tooltip) > 50:
            errors.append(f"{path}.tooltip must contain at most 50 characters")
    elif item_type == "red_zone":
        allowed = {"type", "start_time", "duration_min", "label", "color", "evidence"}
        _unexpected_keys(item, allowed, path, errors)
        if not _positive_int(item.get("start_time")) or not _positive_number(item.get("duration_min")):
            errors.append(f"{path} red_zone requires start_time/duration_min")
        label = item.get("label")
        if not isinstance(label, str) or not label or len(label) > 20:
            errors.append(f"{path}.label must contain at most 20 characters")
    elif item_type == "phase_tracker_text":
        allowed = {"type", "label", "color", "evidence"}
        _unexpected_keys(item, allowed, path, errors)
        label = item.get("label")
        if not isinstance(label, str) or not label or len(label) > 50:
            errors.append(f"{path}.label must contain at most 50 characters")
    elif item_type == "htf_trend":
        allowed = {
            "type", "htf1_label", "htf1_trend", "htf2_label", "htf2_trend",
            "color", "evidence",
        }
        _unexpected_keys(item, allowed, path, errors)
        for key in ("htf1_label", "htf1_trend"):
            if not isinstance(item.get(key), str) or not item[key]:
                errors.append(f"{path}.{key} is required")
        for key in ("htf2_label", "htf2_trend"):
            if item.get(key) is not None and not isinstance(item[key], str):
                errors.append(f"{path}.{key} must be a string or null")
    else:
        errors.append(f"{path}.type is invalid for Layer 5")
    if not _hex(item.get("color")):
        errors.append(f"{path}.color must be a #RRGGBB Hex color")
    _validate_evidence(item, path, errors)


def _validate_veto_data(value: Any, veto: bool, errors: list[str]) -> None:
    if not veto:
        if value is not None and not isinstance(value, dict):
            errors.append("veto_data must be an object or null")
        return
    if not isinstance(value, dict):
        errors.append("Veto response requires veto_data")
        return
    required = {"veto_reason", "conflict_htf", "danger_zone"}
    missing = sorted(required - value.keys())
    if missing:
        errors.append(f"veto_data missing keys: {missing}")
    danger = value.get("danger_zone")
    if not isinstance(danger, dict) or not all(
        _number(danger.get(key)) for key in ("top", "bottom")
    ):
        errors.append("veto_data.danger_zone requires top/bottom")


def validate_analysis_response_v21(payload: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(payload, dict):
        return ["response must be an object"]
    missing = sorted(_TOP_LEVEL_KEYS - payload.keys())
    if missing:
        errors.append(f"response missing keys: {missing}")
    _unexpected_keys(payload, _TOP_LEVEL_KEYS, "response", errors)
    if missing:
        return errors
    if not isinstance(payload["chart_id"], str) or _CHART_ID.fullmatch(payload["chart_id"]) is None:
        errors.append("chart_id must use {SYMBOL}_{TF}_{TIMESTAMP}")
    if not isinstance(payload["setup_ready"], bool) or not isinstance(payload["veto"], bool):
        errors.append("setup_ready and veto must be booleans")
    if not isinstance(payload["fallback"], bool):
        errors.append("fallback must be a boolean")
    if not isinstance(payload["forecast_text"], str) or len(payload["forecast_text"]) > 500:
        errors.append("forecast_text must be a string up to 500 characters")
    veto = payload["veto"] is True
    ready = payload["setup_ready"] is True
    _validate_veto_data(payload["veto_data"], veto, errors)
    if veto and ready:
        errors.append("Veto response cannot be setup_ready")

    layers = payload["layers"]
    if not isinstance(layers, dict):
        return errors + ["layers must be an object"]
    missing_layers = sorted(_LAYER_KEYS - layers.keys())
    if missing_layers:
        errors.append(f"layers missing keys: {missing_layers}")
    _unexpected_keys(layers, _LAYER_KEYS, "layers", errors)
    validators = {
        "layer1_structural": _validate_layer1_item,
        "layer2_trap": _validate_layer2_item,
        "layer3_candle": _validate_layer3_item,
        "layer5_overlay": _validate_layer5_item,
    }
    for key, validator in validators.items():
        items = layers.get(key)
        if not isinstance(items, list):
            errors.append(f"layers.{key} must be an array")
            continue
        for index, item in enumerate(items):
            path = f"layers.{key}[{index}]"
            if not isinstance(item, dict):
                errors.append(f"{path} must be an object")
            else:
                validator(item, path, errors)

    execution = layers.get("layer4_execution")
    if ready and not veto:
        _validate_execution(execution, errors)
    elif execution is not None:
        errors.append("Soft/Veto response cannot contain executable Layer 4")
    return errors


def _valid_evidence(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    source = value.get("source")
    source_id = value.get("source_id")
    timestamp = value.get("timestamp")
    if (
        not isinstance(source, str)
        or not source.strip()
        or not isinstance(source_id, str)
        or not source_id.strip()
        or not _positive_int(timestamp)
    ):
        return None
    return {"source": source, "source_id": source_id, "timestamp": timestamp}


def _legacy_layer_items(grouped: dict[int, dict[str, Any]], number: int) -> list[dict[str, Any]]:
    raw_items = grouped.get(number, {}).get("items") or []
    return [item for item in raw_items if isinstance(item, dict)]


def _convert_layer1(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    converted: list[dict[str, Any]] = []
    for raw in items:
        evidence = _valid_evidence(raw.get("evidence"))
        item_type = raw.get("type") or raw.get("kind")
        color = raw.get("color")
        if evidence is None or not _hex(color):
            continue
        if item_type == "dashed_line":
            item = {
                "type": item_type,
                "color": color,
                "x1": raw.get("x1", raw.get("time_start")),
                "y1": raw.get("y1", raw.get("price_start")),
                "x2": raw.get("x2", raw.get("time_end")),
                "y2": raw.get("y2", raw.get("price_end")),
                "evidence": evidence,
            }
        elif item_type in {"solid_box", "bordered_box"}:
            item = {
                "type": item_type,
                "color": color,
                "x": raw.get("x", raw.get("time_start")),
                "x_end": raw.get("x_end", raw.get("time_end")),
                "y_top": raw.get("y_top", raw.get("price_top")),
                "y_bottom": raw.get("y_bottom", raw.get("price_bottom")),
                "evidence": evidence,
            }
        else:
            continue
        label = raw.get("label")
        if isinstance(label, str) and label:
            item["label"] = label[:4]
        converted.append(item)
    return converted


def _convert_layer2(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    converted: list[dict[str, Any]] = []
    for raw in items:
        evidence = _valid_evidence(raw.get("evidence"))
        color = raw.get("color")
        x = raw.get("x", raw.get("time_x"))
        y = raw.get("y", raw.get("price_y"))
        if evidence is None or not _hex(color) or not _positive_int(x) or not _number(y):
            continue
        raw_type = raw.get("type") or raw.get("kind")
        if raw_type in {"stop_marker", "volume_tag"}:
            item = {"type": "volume_tag", "text": "STOP"}
        elif raw_type == "arrow":
            item = {
                "type": "arrow",
                "direction": raw.get("direction"),
                "label": str(raw.get("label") or raw.get("text") or "")[:8],
            }
        else:
            item = {"type": "text_tag", "text": str(raw.get("text") or "")[:8]}
            if _hex(raw.get("background_color")):
                item["background_color"] = raw["background_color"]
        item.update({"color": color, "x": x, "y": y, "evidence": evidence})
        converted.append(item)
    return converted


def _convert_layer3(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    converted: list[dict[str, Any]] = []
    for raw in items:
        evidence = _valid_evidence(raw.get("evidence"))
        timestamp = raw.get("timestamp", raw.get("candle_time"))
        if evidence is None or not _positive_int(timestamp):
            continue
        item: dict[str, Any] = {"timestamp": timestamp, "evidence": evidence}
        fill = raw.get("fill_color")
        if fill == "#FFFFFF":
            fill = "#A9A9A9"
        if _hex(fill):
            item["fill_color"] = fill
        text = raw.get("text", raw.get("label_top", raw.get("label_bottom")))
        if isinstance(text, str) and text:
            item["text"] = text[:2]
        border = raw.get("border", raw.get("border_color"))
        if _hex(border):
            item["border"] = border
        divergence = raw.get("divergence", raw.get("divergence_direction"))
        divergence_color = raw.get("divergence_color")
        if divergence in {"up", "down"} and _hex(divergence_color):
            item["divergence"] = divergence
            item["divergence_color"] = divergence_color
        if len(item) > 2:
            converted.append(item)
    return converted


def _convert_execution(raw: Any, signal: dict[str, Any]) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    entry_line = raw.get("entry_line")
    stop_line = raw.get("sl_line")
    target_lines = raw.get("tp_lines")
    entry = entry_line.get("price") if isinstance(entry_line, dict) else signal.get("entryPrice")
    stop = stop_line.get("price") if isinstance(stop_line, dict) else signal.get("slPrice")
    targets = (
        [target.get("price") for target in target_lines if isinstance(target, dict)]
        if isinstance(target_lines, list)
        else deepcopy(signal.get("tpPrices") or [])
    )
    if not _positive_number(entry) or not _positive_number(stop) or len(targets) != 3:
        return None
    direction = str(signal.get("type") or "").upper()
    if direction not in {"BUY", "SELL"}:
        return None
    converted_curves: list[dict[str, Any]] = []
    raw_curves = raw.get("curves")
    if not isinstance(raw_curves, list) or len(raw_curves) != 2:
        return None
    for index, curve in enumerate(raw_curves):
        if not isinstance(curve, dict):
            return None
        points = curve.get("points")
        if not isinstance(points, list):
            return None
        converted_points = [
            {"x": point.get("x", point.get("x_time")), "y": point.get("y", point.get("y_price"))}
            for point in points
            if isinstance(point, dict)
        ]
        converted_curves.append({
            "id": "SIG_1" if index == 0 else "SIG_2",
            "type": "bezier_quadratic" if index == 0 else "bezier_cubic",
            "style": "dashed",
            "color": "#00F0FF" if index == 0 else "#1E90FF",
            "points": converted_points,
        })
    probability = (
        signal.get("probability")
        if signal.get("probability_source") == "backtest"
        else signal.get("backtest_probability")
    )
    if not _number(probability) or not 0 <= float(probability) <= 100:
        probability = None
    return {
        "active": True,
        "entry": entry,
        "entry_color": "#0000FF",
        "sl": stop,
        "sl_color": "#FF0000",
        "tp": targets,
        "tp_color": "#00FF00",
        "prob": probability,
        "momentum": {
            "arrow": "up" if direction == "BUY" else "down",
            "label": "SIG",
            "color": "#00FF7F" if direction == "BUY" else "#FF3B30",
        },
        "curves": converted_curves,
    }


def _convert_layer5(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    converted: list[dict[str, Any]] = []
    for raw in items:
        evidence = _valid_evidence(raw.get("evidence"))
        raw_type = raw.get("type") or raw.get("kind")
        if evidence is None:
            continue
        if raw_type == "ghost_box":
            x = raw.get("x", raw.get("time_start"))
            x_end = raw.get("x_end", raw.get("time_end"))
            y_top = raw.get("y_top", raw.get("price_top"))
            y_bottom = raw.get("y_bottom", raw.get("price_bottom"))
            tooltip = raw.get("tooltip")
            color = raw.get("color")
            if not (
                _positive_int(x) and _positive_int(x_end) and _number(y_top) and _number(y_bottom)
                and isinstance(tooltip, str) and tooltip and _hex(color)
            ):
                continue
            item = {
                "type": "ghost_box", "opacity": 0.15, "color": color,
                "x": x, "x_end": x_end, "y_top": y_top, "y_bottom": y_bottom,
                "tooltip": tooltip[:50], "evidence": evidence,
            }
        elif raw_type in {"news_column", "red_zone"}:
            start = raw.get("start_time", raw.get("time_x"))
            duration = raw.get("duration_min")
            label = raw.get("label", raw.get("text"))
            color = raw.get("color")
            if not (_positive_int(start) and _positive_number(duration) and isinstance(label, str) and _hex(color)):
                continue
            item = {
                "type": "red_zone", "start_time": start, "duration_min": duration,
                "label": label[:20], "color": color, "evidence": evidence,
            }
        elif raw_type in {"wyckoff_phase", "phase_tracker_text"}:
            label = raw.get("label", raw.get("text"))
            color = raw.get("color")
            if not isinstance(label, str) or not label or not _hex(color):
                continue
            item = {
                "type": "phase_tracker_text", "label": label[:50],
                "color": color, "evidence": evidence,
            }
        elif raw_type == "htf_trend":
            color = raw.get("color")
            if not _hex(color):
                continue
            item = {
                "type": "htf_trend",
                "htf1_label": raw.get("htf1_label"),
                "htf1_trend": raw.get("htf1_trend"),
                "htf2_label": raw.get("htf2_label"),
                "htf2_trend": raw.get("htf2_trend"),
                "color": color,
                "evidence": evidence,
            }
        else:
            continue
        converted.append(item)
    return converted


def _convert_veto_data(value: Any) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        return None
    reason = value.get("veto_reason", value.get("reason"))
    conflict = value.get(
        "conflict_htf",
        value.get("conflict_timeframe", value.get("htf_tf")),
    )
    danger = value.get("danger_zone")
    if (
        not isinstance(reason, str)
        or not reason.strip()
        or not isinstance(conflict, str)
        or not conflict.strip()
        or not isinstance(danger, dict)
        or not _number(danger.get("top"))
        or not _number(danger.get("bottom"))
    ):
        return None
    normalized_danger = {
        "top": danger["top"],
        "bottom": danger["bottom"],
    }
    if danger.get("bias") in {"bullish", "bearish"}:
        normalized_danger["bias"] = danger["bias"]
    return {
        "veto_reason": reason.strip()[:160],
        "conflict_htf": conflict.strip()[:20],
        "danger_zone": normalized_danger,
    }


def legacy_to_analysis_response_v21(signal: dict[str, Any]) -> dict[str, Any]:
    """Adapt the current list envelope to the exact Appendix-8 object envelope."""
    grouped: dict[int, dict[str, Any]] = {}
    for raw_layer in signal.get("layers") or []:
        if not isinstance(raw_layer, dict):
            continue
        try:
            layer_number = int(raw_layer.get("layer"))
        except (TypeError, ValueError):
            continue
        grouped[layer_number] = raw_layer

    chart_id = str(signal.get("chart_id") or "")
    if ":" in chart_id:
        chart_id = chart_id.replace(":", "_")
    veto = bool(signal.get("veto"))
    ready = bool(signal.get("setup_ready")) and not veto
    execution = _convert_execution(grouped.get(4), signal) if ready else None
    return {
        "chart_id": chart_id,
        "setup_ready": ready,
        "veto": veto,
        "veto_data": _convert_veto_data(signal.get("veto_data")) if veto else None,
        "fallback": bool(signal.get("fallback")),
        "forecast_text": str(signal.get("forecast_text") or "")[:500],
        "layers": {
            "layer1_structural": _convert_layer1(_legacy_layer_items(grouped, 1)),
            "layer2_trap": _convert_layer2(_legacy_layer_items(grouped, 2)),
            "layer3_candle": _convert_layer3(_legacy_layer_items(grouped, 3)),
            "layer4_execution": execution,
            "layer5_overlay": _convert_layer5(_legacy_layer_items(grouped, 5)),
        },
    }
