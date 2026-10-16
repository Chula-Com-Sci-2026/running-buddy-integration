from pathlib import Path
import secrets
p=Path(__file__).resolve().parents[1]/".env"
if p.exists():
    print("Existing .env preserved")
else:
    p.write_text("".join(f"{key}={secrets.token_hex(32)}\n" for key in ("JWT_SECRET","DB_PASSWORD","BROKER_PASSWORD")))
    p.chmod(0o600)
    print("Created local .env; do not commit it")
