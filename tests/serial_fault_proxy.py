#!/usr/bin/env python3
"""Bridge two TCP serial endpoints and inject bytes before the first packet."""

import argparse
import selectors
import socket


parser = argparse.ArgumentParser()
parser.add_argument("--listen", type=int, required=True)
parser.add_argument("--upstream", type=int, required=True)
parser.add_argument("--inject", required=True, help="hex bytes sent upstream first")
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
        peer.sendall(data)
