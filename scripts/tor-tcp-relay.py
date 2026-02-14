#!/usr/bin/env python3
"""TCP relay that forwards connections through Tor SOCKS5 to a .onion:443"""
import socket, select, threading, struct, sys

LISTEN_PORT = 10443
SOCKS_HOST = '127.0.0.1'
SOCKS_PORT = 9050
TARGET_HOST = sys.argv[1] if len(sys.argv) > 1 else 'awzw4a5nptwsvnqovihlyascb34jyivrbnbucxipqu6haqun6gxd6sad.onion'
TARGET_PORT = 443

def socks5_connect(target_host, target_port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((SOCKS_HOST, SOCKS_PORT))
    s.sendall(b'\x05\x01\x00')
    resp = s.recv(2)
    if resp != b'\x05\x00':
        raise Exception(f'SOCKS5 handshake failed: {resp}')
    domain = target_host.encode()
    req = b'\x05\x01\x00\x03' + bytes([len(domain)]) + domain + struct.pack('!H', target_port)
    s.sendall(req)
    resp = s.recv(10)
    if resp[1] != 0:
        raise Exception(f'SOCKS5 connect failed: status {resp[1]}')
    return s

def relay(a, b):
    while True:
        r, _, _ = select.select([a, b], [], [], 60)
        if not r:
            break
        for sock in r:
            data = sock.recv(65536)
            if not data:
                return
            (b if sock is a else a).sendall(data)

def handle(client):
    try:
        remote = socks5_connect(TARGET_HOST, TARGET_PORT)
        relay(client, remote)
    except Exception as e:
        print(f'Error: {e}')
    finally:
        client.close()

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('127.0.0.1', LISTEN_PORT))
srv.listen(5)
print(f'Listening on 127.0.0.1:{LISTEN_PORT} -> {TARGET_HOST}:{TARGET_PORT} via SOCKS5', flush=True)

while True:
    client, addr = srv.accept()
    print(f'Connection from {addr}', flush=True)
    threading.Thread(target=handle, args=(client,), daemon=True).start()
