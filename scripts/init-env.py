from pathlib import Path
import secrets
p=Path(__file__).resolve().parents[1]/".env"
if p.exists():
    print("Existing .env preserved")
else:
    p.write_text("".join(f"{key}={secrets.token_hex(32)}\n" for key in ("JWT_SECRET","DB_PASSWORD","BROKER_PASSWORD")))
    p.chmod(0o600)
    print("Created local .env; do not commit it")

# A separate refresh-signing key is needed only by the optional team Identity branch.
content = p.read_text()
if not any(line.startswith("TEAM_IDENTITY_REFRESH_SECRET=") for line in content.splitlines()):
    p.write_text(content.rstrip() + "\nTEAM_IDENTITY_REFRESH_SECRET=" + secrets.token_hex(32) + "\n")
    p.chmod(0o600)
    print("Added local team Identity refresh key")
