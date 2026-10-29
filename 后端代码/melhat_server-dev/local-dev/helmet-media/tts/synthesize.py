"""Private subprocess: one request, one model lifetime. Parent validates input."""
import json
import os
import sys
from pathlib import Path
import sherpa_onnx
import soundfile

model = Path(os.environ.get('TTS_MODEL_DIR', '/models/vits-melo-tts-zh_en'))
config = sherpa_onnx.OfflineTtsConfig(
    model=sherpa_onnx.OfflineTtsModelConfig(
        vits=sherpa_onnx.OfflineTtsVitsModelConfig(model=str(model/'model.onnx'),lexicon=str(model/'lexicon.txt'),
            tokens=str(model/'tokens.txt'),dict_dir=str(model/'dict')),num_threads=1,provider='cpu'),
    rule_fsts=','.join(str(model/name) for name in ['date.fst','number.fst','phone.fst']))
if not config.validate():
    raise SystemExit('Invalid offline model')
body=json.load(sys.stdin)
engine=sherpa_onnx.OfflineTts(config)
audio=engine.generate(body['text'],sid=0,speed=1.0)
if len(audio.samples)<=0:
    raise SystemExit('Synthesis returned no audio')
soundfile.write(body['wav'],audio.samples,audio.sample_rate,subtype='PCM_16')
