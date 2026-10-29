import json
import struct
import unittest
import passive_tls_probe as probe


def hello(name=b'lingzhiaide.com'):
    names = b'\0' + struct.pack('!H', len(name)) + name
    sni = struct.pack('!H', len(names)) + names
    versions = b'\x04\x03\x04\x03\x03'
    extensions = struct.pack('!HH', 0, len(sni)) + sni + struct.pack('!HH', 43, len(versions)) + versions
    return b'\x03\x03' + b'0' * 32 + b'\0' + b'\0\x04\x13\x01\xc0\x2f' + b'\x01\0' + struct.pack('!H', len(extensions)) + extensions


def record(body, kind=22):
    return bytes([kind, 3, 3]) + struct.pack('!H', len(body)) + body


def handshake():
    body = hello()
    return b'\x01' + len(body).to_bytes(3, 'big') + body


def packet(payload=b'', seq=100, syn=False, port=443, outgoing=False, server=False, ipv6=False, peer=1, linktype=113):
    source = bytes([192, 0, 2, peer])
    target = bytes([203, 0, 113, 1])
    source_port, target_port = (port, 50000) if server else (50000, port)
    if server:
        source, target = target, source
    tcp = struct.pack('!HHI', source_port, target_port, seq) + b'\0' * 4 + bytes([0x50, 2 if syn else 16]) + b'\0' * 6 + payload
    if ipv6:
        ip = b'\x60\0\0\0' + struct.pack('!H', len(tcp)) + b'\x06\x40' + b'\0' * 12 + source + b'\0' * 12 + target + tcp
        protocol = 0x86dd
    else:
        ip = b'\x45\0' + struct.pack('!H', 20 + len(tcp)) + b'\0' * 4 + b'\x40\x06\0\0' + source + target + tcp
        protocol = 0x0800
    packet_type = 4 if outgoing else 0
    if linktype == 113:
        return struct.pack('!HHH', packet_type, 1, 6) + b'\0' * 8 + struct.pack('!H', protocol) + ip
    if linktype == 276:
        return struct.pack('!HHIHBB', protocol, 0, 1, 1, packet_type, 6) + b'\0' * 8 + ip
    return b'\0' * 12 + struct.pack('!H', protocol) + ip


class PassiveTests(unittest.TestCase):
    def test_hello_versions_ciphers_and_redacted_sni(self):
        parsed = probe.client_hello(hello())
        self.assertEqual(parsed['sni'], 'expected')
        self.assertEqual(parsed['offered_versions'], ['TLS1.3', 'TLS1.2'])
        self.assertEqual(parsed['cipher_ids'], ['0x1301', '0xc02f'])
        secret_name = b'never-print-this-private-name.example'
        parsed = probe.client_hello(hello(secret_name))
        self.assertEqual(parsed['sni'], 'other')
        self.assertNotIn(secret_name.decode(), json.dumps(parsed))
        with self.assertRaises(ValueError):
            probe.client_hello(hello()[:-1])

    def test_fragmented_record_handshake_and_duplicate_segments(self):
        summary = probe.Summary()
        body = handshake()
        wire = record(body[:10]) + record(body[10:])
        summary.feed(packet(syn=True), 113)
        summary.feed(packet(wire[:13], seq=101), 113)
        summary.feed(packet(wire[:13], seq=101), 113)
        summary.feed(packet(wire[8:29], seq=109), 113)  # overlapping retransmission
        summary.feed(packet(wire[29:], seq=130), 113)
        result = summary.result('test', 1)
        self.assertEqual(result['new_tcp_443'], 1)
        self.assertEqual(result['flows'][0]['client_hello']['sni'], 'expected')
        self.assertFalse(result['flows'][0]['incomplete_or_gap'])

    def test_outgoing_other_services_excluded_and_server_alert_retained(self):
        summary = probe.Summary()
        summary.feed(packet(record(handshake()), outgoing=True, syn=True), 113)
        self.assertEqual(len(summary.flows), 0)
        summary.feed(packet(syn=True), 113)
        summary.feed(packet(record(b'\x02\x28', 21), server=True, outgoing=True), 113)
        alerts = summary.result('test', 1)['flows'][0]['plaintext_alerts']
        self.assertEqual(alerts, [{'direction': 'server', 'level': 2, 'description_code': 40}])

    def test_ipv6_sll2_http_privacy_and_ephemeral_identifiers(self):
        raw_http = b'GET /private-token?password=never-print HTTP/1.1\r\nHost: secret.example\r\n\r\n'
        first, second = probe.Summary(), probe.Summary()
        for summary in (first, second):
            summary.feed(packet(raw_http, syn=True, port=80, ipv6=True, linktype=276), 276)
        result = first.result('test', 1)
        self.assertEqual(result['new_tcp_80'], 1)
        self.assertNotEqual(result['flows'][0]['peer'], second.result('test', 1)['flows'][0]['peer'])
        public = json.dumps(result)
        for forbidden in ('private-token', 'password', 'secret.example', '192.0.2', '203.0.113'):
            self.assertNotIn(forbidden, public)
        self.assertEqual(next(iter(first.flows.values()))['streams'], {})

    def test_gaps_and_malformed_payload_are_not_false_success(self):
        summary = probe.Summary()
        wire = record(handshake())
        summary.feed(packet(wire[:10], seq=100), 113)
        summary.feed(packet(wire[20:], seq=120), 113)
        flow = summary.result('test', 1)['flows'][0]
        self.assertTrue(flow['incomplete_or_gap'])
        self.assertIsNone(flow['client_hello'])
        self.assertIsNone(probe.packet_tcp(b'bad', 113))

    def test_flow_budget(self):
        summary = probe.Summary()
        for peer in range(1, 140):
            summary.feed(packet(syn=True, peer=peer), 113)
        self.assertEqual(len(summary.flows), probe.MAX_FLOWS)
        self.assertTrue(summary.result('test', 1)['flow_limit_reached'])

    def test_pcap_fragmented_pipe_and_length_guard(self):
        summary = probe.Summary()
        decoder = probe.PcapDecoder(summary)
        header = struct.pack('<IHHIIII', 0xa1b2c3d4, 2, 4, 0, 0, 8192, 113)
        frame = packet(record(handshake()), syn=True)
        wire = header + struct.pack('<IIII', 1, 0, len(frame), len(frame)) + frame
        for byte in wire:
            decoder.feed(bytes([byte]))
        self.assertEqual(summary.result('test', 1)['flows'][0]['client_hello']['sni'], 'expected')
        with self.assertRaises(ValueError):
            decoder.feed(struct.pack('<IIII', 1, 0, 65537, 65537))


if __name__ == '__main__':
    unittest.main()
