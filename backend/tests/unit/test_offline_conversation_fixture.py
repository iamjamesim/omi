import pytest

from utils.llm.offline_conversation_fixture import enabled, notes


@pytest.mark.parametrize('mode', ['', 'real', 'offline'])
@pytest.mark.parametrize('stage', ['', 'local', 'offline', 'prod', 'production'])
@pytest.mark.parametrize('flag', ['', '0', '1'])
def test_requires_explicit_flag_and_both_offline_boundaries(mode, stage, flag):
    env = {'PROVIDER_MODE': mode, 'OMI_ENV_STAGE': stage, 'OMI_OFFLINE_CONVERSATION_FIXTURES': flag}
    assert enabled(env) is (mode == stage == 'offline' and flag == '1')


def test_visible_fixture_does_not_invent_claims_or_actions():
    fixture = notes()
    assert 'demo' in fixture.title.lower()
    assert 'fixture' in fixture.overview.lower()
    assert 'actual recognized speech' in fixture.overview
    assert not fixture.action_items
    assert not fixture.events
    assert not fixture.sections
    assert not fixture.participants


def test_runtime_notes_and_relevance_use_explicit_offline_fixture(monkeypatch):
    from utils.llm.conversation_processing import get_conversation_notes, should_discard_conversation

    monkeypatch.setenv('PROVIDER_MODE', 'offline')
    monkeypatch.setenv('OMI_ENV_STAGE', 'offline')
    monkeypatch.setenv('OMI_OFFLINE_CONVERSATION_FIXTURES', '1')
    monkeypatch.setenv('OMI_SHAPED_AGENT_MODE', 'off')
    assert get_conversation_notes(None).title == 'Local demo recording'
    assert not should_discard_conversation('Actual recognized speech from a local recording.')
    assert should_discard_conversation('')
    monkeypatch.setenv('OMI_ENV_STAGE', 'prod')
    with pytest.raises(RuntimeError, match='Shaped notes disabled'):
        get_conversation_notes(None)
