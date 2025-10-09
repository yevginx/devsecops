import hashlib, os, secrets

_MASTER_PASSWORD   = os.getenv('TRANSFER_PASSWORD')
_EXPECTED_USERNAME = os.getenv('TRANSFER_USERNAME', 'lomalinda')
_HOME_DIRECTORY    = os.getenv('TRANSFER_HOME_DIRECTORY', '')
_ROLE              = os.getenv('TRANSFER_ROLE', '')
_UID               = int(os.getenv('TRANSFER_UID', '1000'))
_GID               = int(os.getenv('TRANSFER_GID', '100'))
_UNAUTHENTICATED   = {}

def digest(pw: str) -> str:
    dk = hashlib.pbkdf2_hmac('sha256', pw.encode(), b'uMaVww64FUnDLcWF', 1_000_000)
    return dk.hex()

def lambda_handler(event, _):
    user = event.get('username', '')
    print(f"Auth attempt user={user} ip={event.get('sourceIp')} protocol={event.get('protocol')}")
    if user != _EXPECTED_USERNAME or not _MASTER_PASSWORD:
        return _UNAUTHENTICATED
    pw = event.get('password') or ""
    if secrets.compare_digest(digest(pw), _MASTER_PASSWORD):
        return {
            "Role": _ROLE,
            "HomeDirectory": _HOME_DIRECTORY,
            "HomeDirectoryType": "PATH",
            "PosixProfile": {"Uid": _UID, "Gid": _GID}
        }
    return _UNAUTHENTICATED
