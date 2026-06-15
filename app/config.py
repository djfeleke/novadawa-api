from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    # Database
    database_url: str

    # Firebase
    firebase_credentials_path: str = "./firebase-credentials.json"
    firebase_credentials_json: str = ""   # alternative: inline JSON string

    # App
    app_env: str = "development"
    require_auth: bool = False            # False during build phase; True in production
    log_level: str = "INFO"

    # Connection pool
    db_pool_min: int = 2
    db_pool_max: int = 10

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"


settings = Settings()
