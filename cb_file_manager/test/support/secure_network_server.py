"""Loopback-only SSH/FTPS fixtures. Requires asyncssh, pyftpdlib, pyopenssl."""
import asyncio
import datetime
import ipaddress
import json
import logging
from pathlib import Path
import sys
import threading

import asyncssh
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import TLS_FTPHandler, FTPHandler
from pyftpdlib.ioloop import IOLoop
from pyftpdlib.servers import FTPServer

logging.disable(logging.CRITICAL)
root = Path(sys.argv[1]).resolve()
root.mkdir(parents=True, exist_ok=True)
(root / 'hello.txt').write_text('secure network fixture', encoding='utf8')
key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'localhost')])
now = datetime.datetime.now(datetime.timezone.utc)
cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
        .public_key(key.public_key()).serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=2))
        .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost'),
            x509.IPAddress(ipaddress.ip_address('127.0.0.1'))]), critical=False)
        .sign(key, hashes.SHA256()))
cert_path = root / 'certificate.pem'
cert_path.write_bytes(cert.public_bytes(serialization.Encoding.PEM))
key_path = root / 'certificate-key.pem'
key_path.write_bytes(key.private_bytes(serialization.Encoding.PEM,
    serialization.PrivateFormat.TraditionalOpenSSL, serialization.NoEncryption()))
authorizer = DummyAuthorizer()
authorizer.add_user('developer', 'fixture-password', str(root), perm='elradfmwMT')

class ExplicitTLS(TLS_FTPHandler):
    certfile = str(cert_path)
    keyfile = str(key_path)
    tls_control_required = True
    tls_data_required = True

ExplicitTLS.authorizer = authorizer

class ImplicitTLS(ExplicitTLS):
    def handle(self):
        self.secure_connection(self.ssl_context)
    def handle_ssl_established(self):
        super().handle()

class PlainFTP(FTPHandler):
    pass
PlainFTP.authorizer = authorizer
servers = []
ports = []
for handler in (ExplicitTLS, ImplicitTLS, PlainFTP):
    server = FTPServer(('127.0.0.1', 0), handler, ioloop=IOLoop())
    servers.append(server)
    ports.append(server.socket.getsockname()[1])
    threading.Thread(target=server.serve_forever, kwargs={'timeout': .1}, daemon=True).start()

class SSHServer(asyncssh.SSHServer):
    def begin_auth(self, username): return True
    def password_auth_supported(self): return True
    def public_key_auth_supported(self): return True
    def validate_password(self, username, password):
        return username == 'developer' and password == 'fixture-password'
    def validate_public_key(self, username, key):
        allowed = root / 'authorized_keys'
        return username == 'developer' and allowed.exists() and key in asyncssh.read_public_key_list(allowed)

class KbdintSSHServer(asyncssh.SSHServer):
    """PAM-style sshd: the password is only accepted through keyboard-interactive."""
    def begin_auth(self, username): return True
    def password_auth_supported(self): return False
    def kbdint_auth_supported(self): return True
    def get_kbdint_challenge(self, username, lang, submethods):
        return '', '', '', [('Password: ', False)]
    def validate_kbdint_response(self, username, responses):
        return username == 'developer' and responses == ['fixture-password']

async def shell(process):
    process.stdout.write('fixture terminal ready\r\n')
    async for line in process.stdin:
        if line.strip() == 'exit': break
        process.stdout.write('echo: ' + line)
    process.exit(0)

async def main():
    host_key = asyncssh.generate_private_key('ssh-ed25519')
    server = await asyncssh.create_server(SSHServer, '127.0.0.1', 0,
        server_host_keys=[host_key], process_factory=shell,
        sftp_factory=lambda channel: asyncssh.SFTPServer(channel, chroot=str(root)))
    second = await asyncssh.create_server(SSHServer, '127.0.0.1', 0,
        server_host_keys=[host_key], sftp_factory=lambda channel: asyncssh.SFTPServer(channel, chroot=str(root)))
    kbdint = await asyncssh.create_server(KbdintSSHServer, '127.0.0.1', 0,
        server_host_keys=[host_key], process_factory=shell)
    print(json.dumps({'ssh': server.get_port(), 'ssh2': second.get_port(), 'kbdint': kbdint.get_port(), 'none': ports[2], 'explicitTls': ports[0],
        'implicitTls': ports[1], 'certificate': str(cert_path)}), flush=True)
    await asyncio.to_thread(sys.stdin.readline)
    kbdint.close()
    await kbdint.wait_closed()
    second.close()
    await second.wait_closed()
    server.close()
    await server.wait_closed()
    for ftp in servers: ftp.close_all()

asyncio.run(main())
