import json
from typing import Any

from app.models import EvaluationResult


def extract_message_content(response: dict[str, Any]) -> str | None:
    try:
        choices = response.get("choices")
        if not choices:
            return None
        message = choices[0].get("message", {})
        content = message.get("content")
        if content is None:
            return None
        return str(content)
    except (AttributeError, IndexError, KeyError, TypeError):
        return None


def parse_action_from_content(content: str | None) -> tuple[bool, str | None]:
    if content is None:
        return False, None
    try:
        payload = json.loads(content)
    except (json.JSONDecodeError, TypeError):
        return False, None
    if not isinstance(payload, dict):
        return False, None
    action = payload.get("action")
    if action is None:
        return True, None
    return True, str(action)


def evaluate_responses(
    primary_response: dict[str, Any],
    candidate_response: dict[str, Any],
) -> EvaluationResult:
    primary_content = extract_message_content(primary_response)
    candidate_content = extract_message_content(candidate_response)

    primary_valid, primary_action = parse_action_from_content(primary_content)
    candidate_valid, candidate_action = parse_action_from_content(candidate_content)

    actions_match = (
        primary_valid
        and candidate_valid
        and primary_action is not None
        and candidate_action is not None
        and primary_action == candidate_action
    )

    return EvaluationResult(
        primary_json_valid=primary_valid,
        candidate_json_valid=candidate_valid,
        primary_action=primary_action,
        candidate_action=candidate_action,
        actions_match=actions_match,
    )
