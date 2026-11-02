"""Explicit mobile conversation fixture for the isolated offline harness.

Only notes are synthetic. The capture transcript and normal persistence remain
untouched. The visible copy must identify this as a demo, not model analysis.
"""

from __future__ import annotations

import os
from collections.abc import Mapping

from models.structured import Structured


def enabled(environ: Mapping[str, str] | None = None) -> bool:
    env = os.environ if environ is None else environ
    return (
        env.get('OMI_OFFLINE_CONVERSATION_FIXTURES', '').strip().lower() in {'1', 'true'}
        and env.get('PROVIDER_MODE', '').strip().lower() == 'offline'
        and env.get('OMI_ENV_STAGE', '').strip().lower() == 'offline'
    )


def notes() -> Structured:
    return Structured(
        title='Local demo recording',
        overview='Demo summary fixture. Open Transcript to read the actual recognized speech. '
        'AI summary generation is not configured for this local demo.',
        emoji='💬',
    )
