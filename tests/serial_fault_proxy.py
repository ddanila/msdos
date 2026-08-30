#!/usr/bin/env python3
"""Bridge two TCP serial endpoints and inject deterministic protocol faults."""

import argparse
import selectors
import socket


parser = argparse.ArgumentParser()
parser.add_argument("--listen", type=int, required=True)
parser.add_argument("--upstream", type=int, required=True)
parser.add_argument("--inject", required=True, help="hex bytes sent upstream first")
parser.add_argument("--corrupt-sector", type=int, default=0,
                    help="flip one byte in this 1-based read-sector response")
parser.add_argument("--drop-sector", type=int, default=0,
                    help="drop this 1-based read-sector response")
parser.add_argument("--truncate-sector", type=int, default=0,
                    help="truncate this 1-based read-sector response mid-payload")
parser.add_argument("--corrupt-request", type=int, default=0,
                    help="flip one byte in this 1-based request header")
parser.add_argument("--corrupt-write", type=int, default=0,
                    help="flip one byte in this 1-based write payload")
parser.add_argument("--truncate-write", type=int, default=0,
                    help="truncate this 1-based write request mid-payload")
args = parser.parse_args()

upstream = socket.create_connection(("127.0.0.1", args.upstream), timeout=10)
listener = socket.socket()
listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
listener.bind(("127.0.0.1", args.listen))
listener.listen(1)
client, _ = listener.accept()
listener.close()
upstream.sendall(bytes.fromhex(args.inject))

selector = selectors.DefaultSelector()
selector.register(client, selectors.EVENT_READ, upstream)
selector.register(upstream, selectors.EVENT_READ, client)
client_stream = bytearray()
server_stream = bytearray()
pending = []
sector_response = 0
request_number = 0
write_request = 0
retry_identity = None


def forward_requests(data):
    """Frame requests for fault injection and record their reply types."""
    global request_number, write_request, retry_identity
    client_stream.extend(data)
    while True:
        marker = client_stream.find(b"\xa5\x5a")
        if marker < 0:
            if len(client_stream) > 1:
                upstream.sendall(client_stream[:-1])
                del client_stream[:-1]
            return
        if marker:
            upstream.sendall(client_stream[:marker])
            del client_stream[:marker]
        if len(client_stream) < 9:
            return
        command = client_stream[2]
        request_size = 9 + (514 if command == 3 else 0)
        if len(client_stream) < request_size:
            return
        request = bytearray(client_stream[:request_size])
        del client_stream[:request_size]
        request_number += 1
        identity = bytes(request[3:8])
        if command == 2 and retry_identity == identity:
            print("retried corrupted read sector", flush=True)
            retry_identity = None
        if command == 3:
            write_request += 1
        if request_number == args.corrupt_request:
            request[3] ^= 0x01
            print(f"corrupted request header {request_number}", flush=True)
        elif command == 3 and write_request == args.truncate_write:
            upstream.sendall(request[:100])
            print(f"truncated write payload {write_request}", flush=True)
            continue
        else:
            pending.append((command, identity))
            if command == 3 and write_request == args.corrupt_write:
                request[9 + 100] ^= 0x40
                print(f"corrupted write payload {write_request}", flush=True)
        upstream.sendall(request)


def forward_replies(data):
    """Frame successful replies and optionally corrupt one sector payload."""
    global sector_response, retry_identity
    server_stream.extend(data)
    while pending:
        command, identity = pending[0]
        response_size = 4 if command == 0 else (517 if command in (1, 2) else 3)
        if len(server_stream) < response_size:
            return
        response = bytearray(server_stream[:response_size])
        del server_stream[:response_size]
        pending.pop(0)
        if command == 2 and response[:3] == b"\x5a\xa5\x00":
            sector_response += 1
            if sector_response == args.drop_sector:
                retry_identity = identity
                print(f"dropped sector response {sector_response}", flush=True)
                continue
            if sector_response == args.truncate_sector:
                retry_identity = identity
                client.sendall(response[:131])
                print(f"truncated sector response {sector_response}", flush=True)
                continue
            if sector_response == args.corrupt_sector:
                response[3 + 100] ^= 0x40
                retry_identity = identity
                print(f"corrupted sector response {sector_response}", flush=True)
        client.sendall(response)


while selector.get_map():
    for key, _ in selector.select():
        data = key.fileobj.recv(65536)
        peer = key.data
        if not data:
            selector.unregister(key.fileobj)
            try:
                peer.shutdown(socket.SHUT_WR)
            except OSError:
                pass
            continue
        if key.fileobj is client:
            forward_requests(data)
        elif args.corrupt_sector or args.drop_sector or args.truncate_sector:
            forward_replies(data)
        else:
            peer.sendall(data)
