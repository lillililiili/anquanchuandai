#!/usr/bin/env python3
"""Bounded, passive Linux TCP/TLS summary. No raw capture is written to disk."""
import argparse
import datetime
import hashlib
import hmac
import json
import os
import select
import shutil
import socket
import struct
import subprocess
import sys
import time

PORTS = (80, 443)
MAX_FLOWS = 128
MAX_STREAM = 32768
MAX_PACKETS = 100000
EXPECTED_SNI = b'lingzhiaide.com'
VERSIONS = {0x0300: 'SSL3', 0x0301: 'TLS1.0', 0x0302: 'TLS1.1', 0x0303: 'TLS1.2', 0x0304: 'TLS1.3'}


def client_hello(data):
    """Parse only the TLS ClientHello structure; never return names or extensions."""
    pos = 0
    def take(size):
        nonlocal pos
        if size < 0 or pos + size > len(data):
            raise ValueError('truncated')
        value = data[pos:pos + size]
        pos += size
        return value
    def u8():
        return take(1)[0]
    def u16():
        return struct.unpack('!H', take(2))[0]
    legacy = u16()
    take(32)
    take(u8())
    cipher_bytes = take(u16())
    if len(cipher_bytes) % 2:
        raise ValueError('cipher length')
    ciphers = [struct.unpack('!H', cipher_bytes[i:i + 2])[0] for i in range(0, len(cipher_bytes), 2)]
    take(u8())
    sni, supported = 'absent', []
    if pos < len(data):
        extension_bytes = take(u16())
        if pos != len(data):
            raise ValueError('extension length')
        offset, seen = 0, set()
        while offset < len(extension_bytes):
            if offset + 4 > len(extension_bytes):
                raise ValueError('extension header')
            kind, size = struct.unpack('!HH', extension_bytes[offset:offset + 4])
            offset += 4
            value = extension_bytes[offset:offset + size]
            offset += size
            if len(value) != size or kind in seen:
                raise ValueError('extension size')
            seen.add(kind)
            if kind == 0:
                if len(value) < 2 or struct.unpack('!H', value[:2])[0] != len(value) - 2:
                    raise ValueError('sni length')
                cursor, names = 2, []
                while cursor < len(value):
                    if cursor + 3 > len(value):
                        raise ValueError('sni header')
                    name_type, name_size = value[cursor], struct.unpack('!H', value[cursor + 1:cursor + 3])[0]
                    cursor += 3
                    name = value[cursor:cursor + name_size]
                    cursor += name_size
                    if len(name) != name_size:
                        raise ValueError('sni size')
                    if name_type == 0:
                        names.append(name.lower().rstrip(b'.'))
                sni = 'expected' if names == [EXPECTED_SNI] else 'other'
            elif kind == 43:
                if not value or value[0] != len(value) - 1 or value[0] % 2:
                    raise ValueError('version length')
                supported = [struct.unpack('!H', value[i:i + 2])[0] for i in range(1, len(value), 2)]
    return {'sni': sni, 'legacy_version': VERSIONS.get(legacy, 'other'),
            'offered_versions': [VERSIONS.get(v, 'other') for v in supported],
            'cipher_count': len(ciphers), 'cipher_ids': ['0x%04x' % v for v in ciphers[:64]],
            'cipher_list_truncated': len(ciphers) > 64}


def packet_tcp(packet, linktype=1, packet_type=None):
    """Return TCP header fields and transient bytes, supporting Ethernet/Linux cooked."""
    if linktype == 1:
        if len(packet) < 14:
            return None
        ether_type, offset = struct.unpack('!H', packet[12:14])[0], 14
        for _ in range(2):
            if ether_type not in (0x8100, 0x88a8):
                break
            if len(packet) < offset + 4:
                return None
            ether_type = struct.unpack('!H', packet[offset + 2:offset + 4])[0]
            offset += 4
    elif linktype == 113:
        if len(packet) < 16:
            return None
        packet_type = struct.unpack('!H', packet[:2])[0]
        ether_type, offset = struct.unpack('!H', packet[14:16])[0], 16
    elif linktype == 276:
        if len(packet) < 20:
            return None
        packet_type = packet[10]
        ether_type, offset = struct.unpack('!H', packet[:2])[0], 20
    else:
        return None
    data = packet[offset:]
    if ether_type == 0x0800:
        if len(data) < 20 or data[0] >> 4 != 4:
            return None
        size = (data[0] & 15) * 4
        total = struct.unpack('!H', data[2:4])[0]
        if size < 20 or total < size or len(data) < total or data[9] != 6 or struct.unpack('!H', data[6:8])[0] & 0x3fff:
            return None
        source, target, tcp = data[12:16], data[16:20], data[size:total]
    elif ether_type == 0x86dd:
        if len(data) < 40 or data[0] >> 4 != 6:
            return None
        total = 40 + struct.unpack('!H', data[4:6])[0]
        if len(data) < total:
            return None
        source, target, protocol, cursor = data[8:24], data[24:40], data[6], 40
        for _ in range(8):
            if protocol == 6:
                break
            if protocol not in (0, 43, 60) or cursor + 2 > total:
                return None  # IPv6 fragments/ESP/AH are deliberately not reconstructed.
            next_protocol, length = data[cursor], (data[cursor + 1] + 1) * 8
            cursor += length
            protocol = next_protocol
        if protocol != 6 or cursor > total:
            return None
        tcp = data[cursor:total]
    else:
        return None
    if len(tcp) < 20:
        return None
    source_port, target_port, sequence = struct.unpack('!HHI', tcp[:8])
    header_size = (tcp[12] >> 4) * 4
    if header_size < 20 or header_size > len(tcp):
        return None
    # Only inbound requests to local web ports and their outbound responses.
    if target_port in PORTS and packet_type != 4:
        key, direction, peer, port = (source, source_port, target, target_port), 'client', source, target_port
    elif source_port in PORTS and packet_type == 4:
        key, direction, peer, port = (target, target_port, source, source_port), 'server', target, source_port
    else:
        return None
    return key, direction, peer, port, sequence, tcp[13], tcp[header_size:]


class Summary:
    def __init__(self):
        self.secret = os.urandom(32)
        self.flows = {}
        self.packet_count = 0
        self.flow_limit_reached = False

    def feed(self, packet, linktype=1, packet_type=None):
        self.packet_count += 1
        item = packet_tcp(packet, linktype, packet_type)
        if item is None:
            return
        key, direction, peer, port, sequence, flags, payload = item
        if key not in self.flows:
            if len(self.flows) >= MAX_FLOWS:
                self.flow_limit_reached = True
                return
            self.flows[key] = {'public': {'peer': hmac.new(self.secret, peer, hashlib.sha256).hexdigest()[:12],
                'port': port, 'new_tcp_syn': False, 'client_hello': None, 'plaintext_alerts': [], 'incomplete_or_gap': False},
                'streams': {}}
        flow, out = self.flows[key], self.flows[key]['public']
        if direction == 'client' and flags & 2 and not flags & 16:
            out['new_tcp_syn'] = True
        if port != 443 or not payload:
            return  # No HTTP parsing, URI capture or body buffering.
        stream = flow['streams'].setdefault(direction, {'next': sequence, 'bytes': bytearray(), 'handshake': bytearray(), 'disabled': False})
        if stream['disabled']:
            return
        difference = (sequence - stream['next']) & 0xffffffff
        if difference >= 0x80000000:
            overlap = (stream['next'] - sequence) & 0xffffffff
            if overlap >= len(payload):
                return
            payload = payload[overlap:]
        elif difference:
            out['incomplete_or_gap'] = True
            stream['disabled'] = True
            stream['bytes'].clear()
            stream['handshake'].clear()
            return
        stream['next'] = (sequence + len(item[-1])) & 0xffffffff
        stream['bytes'].extend(payload)
        if len(stream['bytes']) + len(stream['handshake']) > MAX_STREAM:
            out['incomplete_or_gap'] = True
            stream['disabled'] = True
            stream['bytes'].clear()
            stream['handshake'].clear()
            return
        while len(stream['bytes']) >= 5:
            header = stream['bytes'][:5]
            kind, size = header[0], struct.unpack('!H', header[3:5])[0]
            if kind not in (20, 21, 22, 23) or header[1] != 3 or size > 18432:
                out['incomplete_or_gap'] = True
                stream['disabled'] = True
                stream['bytes'].clear()
                return
            if len(stream['bytes']) < size + 5:
                break
            body = bytes(stream['bytes'][5:5 + size])
            del stream['bytes'][:5 + size]
            if kind == 21 and len(body) == 2 and body[0] in (1, 2) and len(out['plaintext_alerts']) < 8:
                out['plaintext_alerts'].append({'direction': direction, 'level': body[0], 'description_code': body[1]})
            if kind != 22 or direction != 'client' or out['client_hello'] is not None:
                continue
            stream['handshake'].extend(body)
            handshake = stream['handshake']
            if len(handshake) < 4:
                continue
            length = int.from_bytes(handshake[1:4], 'big')
            if handshake[0] != 1 or length > MAX_STREAM - 4:
                out['incomplete_or_gap'] = True
                handshake.clear()
                continue
            if len(handshake) >= length + 4:
                try:
                    out['client_hello'] = client_hello(bytes(handshake[4:4 + length]))
                except (ValueError, IndexError, struct.error):
                    out['client_hello'] = {'parse_status': 'malformed'}
                handshake.clear()

    def result(self, backend, seconds):
        public = [flow['public'] for flow in self.flows.values()]
        return {'utc': datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00', 'Z'), 'backend': backend,
            'elapsed_seconds': round(seconds, 2), 'packets_examined': self.packet_count,
            'flow_limit_reached': self.flow_limit_reached,
            'packet_limit_reached': self.packet_count >= MAX_PACKETS,
            'new_tcp_80': sum(f['new_tcp_syn'] and f['port'] == 80 for f in public),
            'new_tcp_443': sum(f['new_tcp_syn'] and f['port'] == 443 for f in public),
            'flows': public,
            'limitations': ['peer hashes expire after this run', 'traffic is not proof of device identity',
                'no TCP/IP fragment reassembly; gaps and capture truncation can hide ClientHello',
                'encrypted TLS alerts and failures before the server are not observable']}


class PcapDecoder:
    def __init__(self, summary):
        self.summary, self.buffer, self.endian, self.linktype = summary, bytearray(), None, None

    def feed(self, chunk):
        self.buffer.extend(chunk)
        buffer = self.buffer
        if self.endian is None and len(buffer) >= 24:
            magic = bytes(buffer[:4])
            self.endian = '<' if magic in (b'\xd4\xc3\xb2\xa1', b'\x4d\x3c\xb2\xa1') else '>' if magic in (b'\xa1\xb2\xc3\xd4', b'\xa1\xb2\x3c\x4d') else None
            if self.endian is None:
                raise ValueError('unsupported capture format')
            self.linktype = struct.unpack(self.endian + 'I', buffer[20:24])[0] & 0xffff
            if self.linktype not in (1, 113, 276):
                raise ValueError('unsupported capture link')
            del buffer[:24]
        while self.endian is not None and len(buffer) >= 16 and self.summary.packet_count < MAX_PACKETS:
            size = struct.unpack(self.endian + 'I', buffer[8:12])[0]
            if size > 65536:
                raise ValueError('capture record limit')
            if len(buffer) < 16 + size:
                break
            self.summary.feed(bytes(buffer[16:16 + size]), self.linktype)
            del buffer[:16 + size]
        if len(buffer) > 131072:
            raise ValueError('capture buffer limit')


def pcap_capture(command, summary, deadline):
    import fcntl
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    decoder = PcapDecoder(summary)
    fd = process.stdout.fileno()
    fcntl.fcntl(fd, fcntl.F_SETFL, fcntl.fcntl(fd, fcntl.F_GETFL) | os.O_NONBLOCK)
    try:
        while time.monotonic() < deadline and summary.packet_count < MAX_PACKETS:
            if not select.select([fd], [], [], min(0.25, max(0, deadline - time.monotonic())))[0]:
                if process.poll() is not None:
                    break
                continue
            chunk = os.read(fd, 65536)
            if not chunk:
                if time.monotonic() < deadline - 0.5:
                    raise RuntimeError('capture ended early')
                break
            decoder.feed(chunk)
        if decoder.endian is None or (process.poll() not in (None, 0)):
            raise RuntimeError('capture unavailable')
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=1)
        process.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=int, default=45, choices=range(1, 61), metavar='1..60')
    parser.add_argument('--backend', choices=('auto', 'tcpdump', 'tshark', 'packet'), default='auto')
    args = parser.parse_args()
    if not sys.platform.startswith('linux') or os.geteuid() != 0:
        parser.error('Run only as root on the Linux server; no capture was started.')
    backend = args.backend
    if backend == 'auto':
        backend = 'tcpdump' if shutil.which('tcpdump') else 'tshark' if shutil.which('tshark') else 'packet'
    summary, started = Summary(), time.monotonic()
    # Reserve two seconds for terminating the capture child within the 60s cap.
    deadline = started + min(args.seconds, 58)
    status = 'completed'
    try:
        capture_filter = 'tcp and (port 443 or port 80)'
        if backend == 'tcpdump':
            pcap_capture(['tcpdump', '-n', '-U', '-i', 'any', '-s', '8192', '-w', '-', capture_filter], summary, deadline)
        elif backend == 'tshark':
            pcap_capture(['tshark', '-n', '-i', 'any', '-s', '8192', '-F', 'pcap', '-w', '-', '-f', capture_filter,
                          '-a', 'duration:' + str(args.seconds)], summary, deadline)
        else:
            with socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3)) as capture:
                while time.monotonic() < deadline and summary.packet_count < MAX_PACKETS:
                    capture.settimeout(min(0.25, max(0.001, deadline - time.monotonic())))
                    try:
                        packet, address = capture.recvfrom(65536)
                    except socket.timeout:
                        continue
                    summary.feed(packet, 1, address[2])
    except KeyboardInterrupt:
        status = 'interrupted'
    except Exception:
        status = 'capture_unavailable_or_incomplete'
    result = summary.result(backend, time.monotonic() - started)
    result['status'] = status
    print(json.dumps(result, ensure_ascii=True, separators=(',', ':')))
    return 0 if status == 'completed' else 1


if __name__ == '__main__':
    sys.exit(main())
