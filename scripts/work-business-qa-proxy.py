"""Loopback-only HTTP bridge to one isolated Docker QA backend, with no credential logs."""
import argparse, http.server, json, subprocess
parser=argparse.ArgumentParser();parser.add_argument('--backend',required=True);args=parser.parse_args()
assert args.backend.startswith('wearable-compatible-qa-') and args.backend.endswith('-backend-http')
info=json.loads(subprocess.check_output(['docker','inspect',args.backend]))[0]
networks=list(info['NetworkSettings']['Networks']);assert len(networks)==1
assert json.loads(subprocess.check_output(['docker','network','inspect',networks[0]]))[0]['Internal']

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def relay(self):
        if not (self.path.startswith('/api/') or self.path=='/captchaImage'):
            self.send_error(404);return
        size=int(self.headers.get('Content-Length','0'))
        if size>12*1024*1024:self.send_error(413);return
        body=self.rfile.read(size) if size else None
        command=['docker','exec','-i',args.backend,'curl','--silent','--show-error','--include','--max-time','40','--request',self.command,'--header','Expect:']
        for key in ('Content-Type','X-Wearable-Token','Range'):
            if self.headers.get(key):command+=['--header',key+': '+self.headers[key]]
        if body is not None:command+=['--data-binary','@-']
        command+=['http://127.0.0.1:18084'+self.path]
        try:
            result=subprocess.run(command,input=body,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=45)
            if result.returncode:raise RuntimeError('QA relay request failed')
            head,data=result.stdout.split(b'\r\n\r\n',1)
            lines=head.decode('iso-8859-1').split('\r\n');status=int(lines[0].split()[1]);self.send_response(status)
            for line in lines[1:]:
                key,_,value=line.partition(':')
                if key.lower() in ('content-type','cache-control','content-range','accept-ranges'):self.send_header(key,value.strip())
            self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
        except (OSError,RuntimeError,ValueError,subprocess.TimeoutExpired):self.send_error(502,'Isolated QA backend unavailable')
    do_GET=do_POST=do_PUT=do_PATCH=do_DELETE=relay

server=http.server.ThreadingHTTPServer(('127.0.0.1',18085),Handler)
print('Isolated QA relay listening on 127.0.0.1:18085',flush=True)
server.serve_forever()
