from pydantic import BaseModel


class DashboardPolicies(BaseModel):
    vet_can_view_all: bool


class DashboardSettingsSources(BaseModel):
    vet_can_view_all: str


class DashboardSettingsIntegration(BaseModel):
    ml_service_url: str | None = None
    ml_enabled: bool
    public_base_url: str
    cors_origins: list[str]


class DashboardSettingsAuth(BaseModel):
    strategy: str


class DashboardSettingsMetadata(BaseModel):
    environment: str
    updated_at: str | None = None


class DashboardSettingsOut(BaseModel):
    policies: DashboardPolicies
    sources: DashboardSettingsSources
    integration: DashboardSettingsIntegration
    auth: DashboardSettingsAuth
    metadata: DashboardSettingsMetadata


class PatchDashboardPoliciesRequest(BaseModel):
    vet_can_view_all: bool
