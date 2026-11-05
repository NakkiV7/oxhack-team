# Original coach audio authoring

The consumer app never needs ElevenLabs access. Keep synthesis in a separate authoring step and bundle reviewed files. Existing private credentials have expired; no new ElevenLabs audio is claimed in this build.

The phrase source is `TrainerCueLibrary.lines(reason:tone:)` in Shared/Core/OfflineExperience.swift. Export all eight CoachingReason cases for every TrainerTone and for the two original voices. Common form/stop instructions deliberately have the same calm content at every tone. Encouragement has eight rotating variants for each tone. Do not generate celebrity imitations or change existing recordings as part of this job.

For a replacement bank, each manifest entry must contain coach (`maya` or `leo`), tone, event reason, variant index, exact approved text, source voice name/category, model, format, content SHA-256, duration and measured peak/RMS levels. Keep provider IDs and credentials in the private authoring receipt, not the app. Reject missing/extra combinations, duplicate content accidentally mapped to different instructions, truncated speech, clipped peaks and unsafe wording before importing. Review safety and tracking clips end to end. Rotate by semantic event so an instruction cannot be mapped to a different event merely because its file index matches.

Use licensed original/premade human voices. The UI uses coloured waveforms rather than photos or human faces. Maya/Leo are product labels, not claims about real people or a voice actor's identity.

Runtime import target: a bundled bank adapter implementing `VoicePlayback`. If a recording is missing, use the same approved text with iPhone speech. Missing stop audio must always speak the stop instruction immediately. Visibility instructions may finish their sentence, after which current tracking is reassessed. Mute, pause, input changes, backgrounding and discomfort cancel stale feedback.
