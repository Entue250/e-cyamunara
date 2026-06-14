from __future__ import annotations

import os
import pathlib

try:
    from dotenv import load_dotenv
    load_dotenv(dotenv_path=pathlib.Path(__file__).parent / ".env", override=False)
except ImportError:
    pass

_AI_ROOT = pathlib.Path(__file__).resolve().parent.parent


class Settings:
    def __init__(self) -> None:
        self.supabase_url: str = os.environ.get("SUPABASE_URL", "")
        self.supabase_service_role_key: str = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

        registry_env = os.environ.get("REGISTRY_PATH", "")
        self.registry_path: pathlib.Path = (
            pathlib.Path(registry_env)
            if registry_env
            else _AI_ROOT / "trained_models" / "registry.json"
        )

        self.log_level: str = os.environ.get("LOG_LEVEL", "INFO")
        self.prediction_store_enabled: bool = (
            os.environ.get("PREDICTION_STORE_ENABLED", "true").lower() == "true"
        )
        self.host: str = os.environ.get("HOST", "0.0.0.0")
        self.port: int = int(os.environ.get("PORT", "8000"))

    @property
    def store_configured(self) -> bool:
        return bool(self.supabase_url and self.supabase_service_role_key)


settings = Settings()
