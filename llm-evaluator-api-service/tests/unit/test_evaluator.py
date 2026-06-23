import pytest

from app.evaluator import evaluate_responses, extract_message_content, parse_action_from_content
from app.models import EvaluationResult


class TestExtractMessageContent:
    def test_extracts_valid_content(self):
        response = {
            "choices": [{"message": {"content": '{"action": "search"}'}}]
        }
        assert extract_message_content(response) == '{"action": "search"}'

    def test_returns_none_for_missing_choices(self):
        assert extract_message_content({}) is None

    def test_returns_none_for_empty_choices(self):
        assert extract_message_content({"choices": []}) is None


class TestParseActionFromContent:
    def test_valid_json_with_action(self):
        valid, action = parse_action_from_content('{"action": "book"}')
        assert valid is True
        assert action == "book"

    def test_valid_json_without_action(self):
        valid, action = parse_action_from_content('{"other": "value"}')
        assert valid is True
        assert action is None

    def test_invalid_json(self):
        valid, action = parse_action_from_content("not json")
        assert valid is False
        assert action is None

    def test_non_object_json(self):
        valid, action = parse_action_from_content("[1, 2, 3]")
        assert valid is False
        assert action is None

    def test_none_content(self):
        valid, action = parse_action_from_content(None)
        assert valid is False
        assert action is None


class TestEvaluateResponses:
    def _response(self, action: str) -> dict:
        return {
            "choices": [{"message": {"content": f'{{"action": "{action}"}}'}}]
        }

    def test_matching_actions(self):
        result = evaluate_responses(self._response("search"), self._response("search"))
        assert result == EvaluationResult(
            primary_json_valid=True,
            candidate_json_valid=True,
            primary_action="search",
            candidate_action="search",
            actions_match=True,
        )

    def test_mismatched_actions(self):
        result = evaluate_responses(self._response("search"), self._response("book"))
        assert result.actions_match is False
        assert result.primary_action == "search"
        assert result.candidate_action == "book"

    def test_invalid_primary_json(self):
        primary = {"choices": [{"message": {"content": "broken"}}]}
        candidate = self._response("search")
        result = evaluate_responses(primary, candidate)
        assert result.primary_json_valid is False
        assert result.actions_match is False

    def test_invalid_candidate_json(self):
        primary = self._response("search")
        candidate = {"choices": [{"message": {"content": "broken"}}]}
        result = evaluate_responses(primary, candidate)
        assert result.candidate_json_valid is False
        assert result.actions_match is False

    def test_missing_action_key(self):
        primary = {"choices": [{"message": {"content": '{"intent": "x"}'}}]}
        candidate = self._response("search")
        result = evaluate_responses(primary, candidate)
        assert result.primary_json_valid is True
        assert result.primary_action is None
        assert result.actions_match is False
