# Local recording demo with real transcription

This branch adds an explicitly gated summary fixture for the local offline
backend. It preserves the recognized transcript and normal conversation save
path. The fixture is labelled in the UI and does not generate memories, events,
embeddings, app actions or notifications.

## Start the local backend

Use the repository's normal local-harness prerequisites and setup. Set
`OMI_DEV_HOST` to the Mac's private LAN address for a physical iPhone; the phone
and Mac must be able to reach each other. Use loopback for Simulator-only work.
From the repository root:

```bash
export OMI_DEV_HOST='<mac-private-lan-address>'
OMI_ENV_STAGE=offline PROVIDER_MODE=offline OMI_OFFLINE_CONVERSATION_FIXTURES=1 make dev-up
```

All three settings are required for synthetic summaries. The fixture is disabled
unless `OMI_ENV_STAGE=offline`, `PROVIDER_MODE=offline` and the explicit fixture
flag are set together. Production and ordinary development processing retain
their existing behavior. The local harness remains the owner of its services;
use `make dev-status` and `make dev-down` to inspect or stop it.

## Start Local Whisper

Omi already supports the Local Whisper custom transcription provider. Prepare a
separate whisper.cpp checkout, its `whisper-server` binary, and the `base.en`
model. The demo was exercised with whisper.cpp v1.8.2. Do not add binaries,
models, captured audio or service credentials to this repository.

Run the server from that separate checkout:

```bash
./build/bin/whisper-server --host "$OMI_DEV_HOST" --port 8080 \
  --model ./models/ggml-base.en.bin --threads 4 --no-context
```

This is real speech recognition on the Mac. The summary fixture does not
substitute transcript text. An unavailable microphone or silent input cannot be
repaired by enabling the fixture.

## Configure and run the app

Follow the [app's local iPhone build instructions](../../../app/README.md#building-and-deploying-to-iphone)
and select the dev/local_dev profile with this Mac's API and Auth Emulator
addresses. Use the setup wrapper with `OMI_MOBILE_BUILD_MODE=profile` for a build
that opens untethered. Device signing uses the developer's own account; no
personal signing settings are part of this branch.

In Settings → Recording & Transcription → Transcription, choose Cloud Provider,
then Local Whisper. Set Host to the Mac's private address, Port to `8080`, and
Language to English. Turn **Send raw audio to Omi** off and save.

Tap Record, speak for about 15 seconds, open the expanded pill's Transcript, and
wait for recognized text before tapping End. The saved conversation should keep
those words. Its title is **Local demo recording**, and its summary explicitly
identifies itself as a fixture. Ask opens the chat UI, but this setup does not
configure a real chat model.

## Verification and boundaries

The fixture unit tests cover the three-way gate, visibly synthetic summary
content, preservation of recognized speech in the relevance path, and refusal
to activate when the stage is production. Notes/relevance regression tests also
exercise the existing paths.

A live local acceptance run used a public speech sample through Whisper, Omi's
custom transcription socket, the normal End endpoint and a persisted-read
check. This verifies that real recognized speech can be saved; it does not
claim physical microphone or playback acceptance for another device.

This setup is for new live recordings. It does not retroactively transcribe
previously queued audio. Saved-audio playback is not included: the details player
requires a published audio attachment, which this local setup has not verified.
