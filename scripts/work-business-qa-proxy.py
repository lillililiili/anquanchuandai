"""Loopback-only HTTP bridge to one isolated Docker QA backend, with no credential logs."""
import argparse, http.server, json, re, subprocess

MAX_BODY = 12 * 1024 * 1024
MAX_LINE = 8192
MAX_TRAILERS = 64 * 1024
TOKEN = rb"[!#$%&'*+.^_`|~0-9A-Za-z-]+"
QUOTED = rb'"(?:[\t !#-\[\]-~\x80-\xff]|\\[\t -~\x80-\xff])*"'
CHUNK_LINE = re.compile(rb'([0-9A-Fa-f]+)((?:[ \t]*;[ \t]*' + TOKEN +
                        rb'(?:[ \t]*=[ \t]*(?:' + TOKEN + rb'|' + QUOTED + rb'))?)*)')


class InvalidBody(ValueError):
    def __init__(self, status=400):
        self.status = status


def read_exact(stream, size):
    chunks = []
    while size:
        chunk = stream.read(size)
        if not chunk:
            raise InvalidBody()
        chunks.append(chunk)
        size -= len(chunk)
    return b''.join(chunks)


def read_line(stream):
    line = stream.readline(MAX_LINE + 1)
    if len(line) > MAX_LINE or not line.endswith(b'\r\n'):
        raise InvalidBody()
    return line[:-2]


def read_body(headers, stream):
    """Decode HTTP framing locally; curl forwards only the bounded decoded bytes."""
    lengths = headers.get_all('Content-Length', [])
    encodings = headers.get_all('Transfer-Encoding', [])
    if encodings:
        if lengths or len(encodings) != 1 or encodings[0].strip().lower() != 'chunked':
            raise InvalidBody()
        chunks, total = [], 0
        while True:
            match = CHUNK_LINE.fullmatch(read_line(stream))
            if not match:
                raise InvalidBody()
            size = int(match[1], 16)
            if size > MAX_BODY - total:
                raise InvalidBody(413)
            if not size:
                trailer_size = 0
                while True:
                    trailer = read_line(stream)
                    trailer_size += len(trailer) + 2
                    if trailer_size > MAX_TRAILERS:
                        raise InvalidBody()
                    if not trailer:
                        return b''.join(chunks)
                    name, colon, value = trailer.partition(b':')
                    if (not colon or not re.fullmatch(TOKEN, name)
                            or name.lower() in (b'content-length', b'transfer-encoding', b'host')
                            or re.search(rb'[\x00-\x08\x0a-\x1f\x7f]', value)):
                        raise InvalidBody()
            chunks.append(read_exact(stream, size))
            total += size
            if read_exact(stream, 2) != b'\r\n':
                raise InvalidBody()
    if not lengths:
        return None
    if len(lengths) != 1 or not re.fullmatch(r'[0-9]+', lengths[0]):
        raise InvalidBody()
    try:
        size = int(lengths[0])
    except ValueError:
        raise InvalidBody() from None
    if size > MAX_BODY:
        raise InvalidBody(413)
    return read_exact(stream, size)

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def relay(self):
        if not (self.path.startswith('/api/') or self.path=='/captchaImage'):
            self.send_error(404);return
        try:
            self.connection.settimeout(45)
            body=read_body(self.headers,self.rfile)
        except InvalidBody as error:
            self.send_error(error.status);return
        except (OSError,ValueError):
            self.send_error(400);return
        command=['docker','exec','-i',self.server.backend,'curl','--silent','--show-error','--include','--max-time','40','--request',self.command,'--header','Expect:']
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

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--backend',required=True);args=parser.parse_args()
    assert args.backend.startswith('wearable-compatible-qa-') and args.backend.endswith('-backend-http')
    info=json.loads(subprocess.check_output(['docker','inspect',args.backend]))[0]
    networks=list(info['NetworkSettings']['Networks']);assert len(networks)==1
    assert json.loads(subprocess.check_output(['docker','network','inspect',networks[0]]))[0]['Internal']
    server=http.server.ThreadingHTTPServer(('127.0.0.1',18085),Handler)
    server.backend=args.backend
    print('Isolated QA relay listening on 127.0.0.1:18085',flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
