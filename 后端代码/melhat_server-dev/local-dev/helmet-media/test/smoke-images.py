"""Start only disposable, network-isolated media images; never publish host ports."""
import json
import subprocess
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN = 'helmet-media-smoke-' + uuid.uuid4().hex[:10]
DIRECTORY = ROOT / '.local' / RUN
DIRECTORY.mkdir(parents=True, mode=0o700)
secrets = json.loads((ROOT / '.local/secrets.json').read_text())


def run(args, required=True):
    p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
    text = p.stdout.decode('utf-8', errors='replace')
    for value in secrets.values():
        text = text.replace(value, '[redacted]')
    with (DIRECTORY / 'checks.log').open('a', encoding='utf-8') as out:
        out.write(text + '\n')
    if required and p.returncode:
        raise RuntimeError('Isolated media check failed; inspect owned private checks.log')
    return p.returncode, text


def copy_config(source, target):
    text = source.read_text()
    for value in secrets.values():
        text = text.replace(value, 'smoke-only-not-a-production-key')
    text = text.replace('10.255.1.1', '127.0.0.1').replace('39.106.212.138', '127.0.0.1')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)


created = []
try:
    for source in (ROOT / '.local/freeswitch').rglob('*.xml'):
        copy_config(source, DIRECTORY / 'fs' / source.relative_to(ROOT / '.local/freeswitch'))
    for name in ['srs.conf', 'turn.conf']:
        copy_config(ROOT / '.local' / name, DIRECTORY / name)
    fs_name = RUN + '-fs'
    run(['docker', 'run', '-d', '--network', 'none', '--name', fs_name,
         '-v', str(DIRECTORY / 'fs') + ':/helmet-conf:ro', 'helmet-media-freeswitch:1.10.12'])
    created.append(fs_name)
    for attempt in range(30):
        code, status = run(['docker', 'exec', fs_name, '/usr/local/freeswitch/bin/fs_cli', '-p',
                           'smoke-only-not-a-production-key', '-x', 'sofia status'], required=False)
        if code == 0 and 'helmet' in status and 'RUNNING' in status:
            break
        time.sleep(1)
    else:
        run(['docker', 'logs', fs_name], required=False)
        raise RuntimeError('SIP profile did not start in isolated image')
    _, codecs = run(['docker', 'exec', fs_name, '/usr/local/freeswitch/bin/fs_cli', '-p',
                     'smoke-only-not-a-production-key', '-x', 'show codecs'])
    if 'H264' not in codecs or 'VP8' not in codecs or 'OPUS' not in codecs.upper():
        raise RuntimeError('Required audio/video codecs not loaded')
    print('FreeSWITCH actual SIP profile and H264/VP8/Opus codecs ready', flush=True)
    run(['docker', 'run', '--rm', '--network', 'none', '-v', str(DIRECTORY / 'srs.conf') + ':/smoke.conf:ro',
         'ossrs/srs:6', './objs/srs', '-t', '-c', '/smoke.conf'])
    print('SRS configuration accepted by the real binary', flush=True)
    turn_name = RUN + '-turn'
    run(['docker', 'run', '-d', '--network', 'none', '--user', '0:0', '--cap-drop', 'ALL', '--cap-add', 'NET_BIND_SERVICE', '--security-opt', 'no-new-privileges:true', '--name', turn_name,
         '-v', str(DIRECTORY / 'turn.conf') + ':/smoke.conf:ro', 'coturn/coturn:4.6.3', '-c', '/smoke.conf'])
    created.append(turn_name)
    time.sleep(2)
    _, alive = run(['docker', 'inspect', turn_name, '--format', '{{.State.Running}}'])
    if alive.strip() != 'true':
        run(['docker', 'logs', turn_name], required=False)
        raise RuntimeError('Coturn configuration did not stay running')
    print('Coturn private configuration started with only its required bind-port capability', flush=True)
    run(['docker', 'run', '--rm', '--network', 'none', '--entrypoint', 'python', 'helmet-media-tts:1', '-c',
         'import sherpa_onnx,soundfile; c=sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(vits=sherpa_onnx.OfflineTtsVitsModelConfig(model="/model/model.onnx",tokens="/model/tokens.txt",dict_dir="/model/dict"),num_threads=1,provider="cpu")); print("TTS API imports and config construct successfully")'])
    print('Installed TTS native Python APIs verified', flush=True)
    if (ROOT / '.local/models/model-source.json').is_file():
        run(['docker', 'run', '--rm', '--network', 'none', '--memory', '1g', '--entrypoint', 'python',
             '-v', str(ROOT / '.local/models') + ':/models:ro', '-v', str(DIRECTORY) + ':/out',
             'helmet-media-tts:1', '-c',
             'import sherpa_onnx,soundfile; p="/models/vits-melo-tts-zh_en/"; c=sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(vits=sherpa_onnx.OfflineTtsVitsModelConfig(model=p+"model.onnx",lexicon=p+"lexicon.txt",tokens=p+"tokens.txt",dict_dir=p+"dict"),num_threads=2,provider="cpu"),rule_fsts=",".join(p+x for x in ["date.fst","number.fst","phone.fst"])); assert c.validate(); e=sherpa_onnx.OfflineTts(c); a=e.generate("安全帽语音广播测试，请注意安全。",sid=0,speed=1.0); assert len(a.samples)>a.sample_rate; soundfile.write("/out/tts-test.wav",a.samples,a.sample_rate); print("Chinese speech synthesized:",round(len(a.samples)/a.sample_rate,2),"seconds")'])
        print('Chinese speech synthesized from the downloaded model within 1 GiB container memory', flush=True)
finally:
    for name in reversed(created):
        run(['docker', 'rm', '-f', name], required=False)
