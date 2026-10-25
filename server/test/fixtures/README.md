# Silent MP3 compatibility fixture

`silence-22050-32-info.mp3` is locally generated synthetic silence, with no speech, personal data or provider request. It is a codec fixture, not recovered ElevenLabs audio.

Generated with existing FFmpeg 8.1.2 on 25 October 2026:

```sh
ffmpeg -nostdin -hide_banner -loglevel error -f lavfi -i anullsrc=r=22050:cl=mono -t 0.25 -c:a libmp3lame -b:a 32k -map_metadata -1 -id3v2_version 3 -write_xing 1 -y silence-22050-32-info.mp3
ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels,bit_rate,duration -of json silence-22050-32-info.mp3
ffmpeg -nostdin -hide_banner -loglevel error -i silence-22050-32-info.mp3 -f null -
```

Actual probe: MP3, 22,050 Hz, mono, 32,000 bit/s, 0.250023 seconds. Full decode exited 0. The file is 1,481 bytes, SHA-256 `e9022bee525ccd77e2293500c06fa2a585888d6ca4c1edac538011be04bc525f`. Its 45-byte ID3 prefix precedes header `ff f3 70 c0`: a complete 182-byte, 56 kbps Info metadata frame. Subsequent audio frames use 32 kbps. The HTTP behavior test also exercises the file with the ID3 prefix removed. Exact output bytes may differ with another encoder version.

[ElevenLabs](https://elevenlabs.io/docs/api-reference/text-to-speech/convert) specifies `mp3_22050_32` as codec/sample-rate/bitrate, without promising that the first metadata frame uses that bitrate. [FFmpeg's MP3 muxer](https://github.com/FFmpeg/FFmpeg/blob/master/libavformat/mp3enc.c) increases the Xing frame bitrate until metadata fits and writes Info for CBR. [RFC 3119, section 2](https://www.rfc-editor.org/rfc/rfc3119.html#section-2) describes MP3 frame headers, optional CRC and side information.

The fixture first returned HTTP 502 against the gateway and now returns its unchanged bytes. Negative cases retain rejection of incomplete frames (including padding), reserved bitrate indices, a different sample rate and non-MP3 garbage. Gateway validation remains bounded header/frame-length validation; it does not fully decode audio. Native AVAudioPlayer remains the decoder. This standards regression does not establish the cause of the separately observed Roger response, whose original bytes were not retained at this checkpoint.
