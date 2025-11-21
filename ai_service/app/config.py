"""Application configuration via environment variables."""

from functools import lru_cache
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    environment: str = "development"
    port: int = 8000
    log_level: str = "INFO"

    # Vertex AI
    vertex_ai_project: str = "interviewflow-local"
    vertex_ai_location: str = "us-central1"
    vertex_ai_model: str = "gemini-1.5-pro-002"

    # Security
    service_secret: str = "dev-secret"

    class Config:
        env_file = ".env"
        case_sensitive = False


@lru_cache
def get_settings() -> Settings:
    return Settings()
