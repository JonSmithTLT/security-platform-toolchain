#!/usr/bin/env python3
import socket

host = "127.0.0.1"
port = 9001

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((host, port))
    server.listen(20)
    while True:
        conn, _ = server.accept()
        with conn:
            data = conn.recv(4096)
            if data.startswith(b"CRASH"):
                conn.close()
                raise SystemExit(88)
            conn.sendall(b"OK\n")
