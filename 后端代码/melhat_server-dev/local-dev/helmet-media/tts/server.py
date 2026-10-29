"""Local CPU TTS. Generates controlled asset IDs; never accepts an output path."""
import json
import os
import re
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MODEL = Path(os.environ.get('TTS_MODEL_DIR', '/models/vits-melo-tts-zh_en'))
ASSETS = Path('/data/assets')
ASSETS.mkdir(parents=True, exist_ok=True, mode=0o700)
lock = threading.Lock()
ready = all((MODEL / name).is_file() for name in ['model.onnx','lexicon.txt','tokens.txt','date.fst','number.fst','phone.fst']) and (MODEL/'dict').is_dir()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def reply(self, status, value):
        data = json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.reply(200 if self.path == '/health' else 404, {'ready': ready, 'engineLoaded': False, 'mode':'one-request-worker'})

    def do_POST(self):
        if self.path != '/synthesize' or not ready:
            return self.reply(503, {'error': 'TTS_UNAVAILABLE'})
        length = int(self.headers.get('Content-Length', '0'))
        if not 0 < length <= 16384:
            return self.reply(413, {'error': 'BODY_TOO_LARGE'})
        try:
            body = json.loads(self.rfile.read(length))
            asset_id, text = body['assetId'], body['text']
            if not re.fullmatch(r'[a-f0-9-]{36}', asset_id) or not isinstance(text, str) or not 0 < len(text) <= 1000:
                raise ValueError()
        except Exception:
            return self.reply(400, {'error': 'INVALID_REQUEST'})
        if not lock.acquire(blocking=False):
            return self.reply(429, {'error': 'TTS_BUSY'})
        wav, mp3 = ASSETS / (asset_id + '.wav'), ASSETS / (asset_id + '.mp3')
        try:
            # A short-lived worker returns ONNX memory to the OS after every request.
            subprocess.run(['python','/app/synthesize.py'], input=json.dumps({'text':text,'wav':str(wav)}).encode(),
                           check=True, timeout=75, capture_output=True)
            subprocess.run(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-i', str(wav), '-ac', '1', '-ar', '24000', '-b:a', '64k', '-n', str(mp3)], check=True, timeout=30, capture_output=True)
            os.chmod(mp3, 0o600)
            with mp3.open('rb') as output:
                os.fsync(output.fileno())
            self.reply(200, {'assetId': asset_id, 'status': 'ready'})
        except Exception:
            self.reply(500, {'error': 'SYNTHESIS_FAILED'})
        finally:
            wav.unlink(missing_ok=True)
            lock.release()


ThreadingHTTPServer(('127.0.0.1', 18192), Handler).serve_forever()
