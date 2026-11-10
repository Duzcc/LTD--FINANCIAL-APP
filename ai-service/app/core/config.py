from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = "Finance AI Service"
    environment: str = "development"
    service_api_key: str = ""
    artifacts_dir: Path = Path(__file__).resolve().parents[2] / "artifacts"

    llm_provider: str = ""
    llm_api_key: str = ""
    llm_model: str = ""
    llm_base_url: str = ""
    llm_max_tokens: int = 900
    llm_timeout_seconds: float = 45.0
    vision_model: str = ""

    @property
    def llm_enabled(self) -> bool:
        if self.llm_provider == "anthropic":
            return bool(self.llm_api_key and self.llm_model)
        if self.llm_provider == "openai":
            return bool(self.llm_model and (self.llm_base_url or self.llm_api_key))
        return False


@lru_cache
def get_settings() -> Settings:
    return Settings()
