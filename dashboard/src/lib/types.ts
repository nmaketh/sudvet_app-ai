export interface DifferentialEntry {
  disease: string;
  display_name?: string;
  score: number;
  percentage?: number;
  matched_symptoms?: string[];
}

export interface PredictionJson {
  final_label?: string;
  label?: string;
  display_label?: string;
  confidence?: number;
  method?: string;
  risk_level?: string;
  differential?: DifferentialEntry[];
  feature_importance?: Record<string, number>;
  rule_triggers?: string[];
  reasoning?: string;
  supporting_evidence?: string[];
  cautionary_evidence?: string[];
  modality_summary?: string;
  evidence_quality?: string;
  confidence_band?: string;
  recommendations?: string[];
  probabilities?: Record<string, number>;
  gradcam_url?: string | null;
  gradcam_path?: string | null;
  engine?: string;
  temperature_note?: string | null;
  severity_note?: string | null;
  [key: string]: unknown;
}

export type CaseItem = {
  id: string;
  client_case_id?: string | null;
  created_at: string;
  animal_id?: string | null;
  animal_tag?: string | null;
  submitted_by_user_id: number;
  submitted_by_name?: string | null;
  prediction_json: PredictionJson;
  method?: string | null;
  confidence?: number | null;
  risk_level: "low" | "medium" | "high";
  status: "open" | "in_treatment" | "resolved";
  /** Two-value state machine. Assignment is tracked via assigned_to_user_id, not here. */
  triage_status: "needs_review" | "escalated";
  assigned_to_user_id?: number | null;
  assigned_to_name?: string | null;
  /** CAHW-requested specific vet (optional hint; does not auto-assign) */
  requested_vet_id?: number | null;
  requested_vet_name?: string | null;
  request_note?: string | null;
  followup_date?: string | null;
  image_url?: string | null;
  symptoms_json: Record<string, unknown>;
  notes?: string | null;
  corrected_label?: string | null;
  urgent?: boolean;
  triaged_at?: string | null;
  accepted_at?: string | null;
  resolved_at?: string | null;
  rejection_reason?: string | null;
};

export type AnimalItem = {
  id: string;
  tag: string;
  name?: string | null;
  owner_id: number;
  location: string;
  created_at: string;
};

export type UserItem = {
  id: number;
  name: string;
  email: string;
  role: "CAHW" | "VET" | "ADMIN";
  location?: string | null;
  created_at: string;
};

export type AnalyticsSummary = {
  cases_by_disease: Record<string, number>;
  cases_by_day: Array<{ day: string; count: number }>;
  backlog_count: number;
  avg_resolution_time: number;
  high_risk_rate: number;
  resolution_time_trend: Array<{ day: string; avg_hours: number }>;
  backlog_trend: Array<{ day: string; backlog: number }>;
};

export type CaseTimelineEvent = {
  id: number;
  case_id: string;
  actor_user_id: number;
  event_type: string;
  payload_json: Record<string, unknown>;
  created_at: string;
};

export type SystemHealth = {
  status: string;
  api: string;
  db: string;
  db_latency_ms?: number | null;
  ml?: string;
  ml_latency_ms?: number | null;
  ml_health_url?: string | null;
  prediction_default_engine?: string | null;
  time: string;
};

export type ModelVersionItem = {
  id: number;
  type: string;
  version: string;
  metrics_json: Record<string, unknown>;
  updated_at: string;
};

export type ErrorLogItem = {
  id: number;
  source: string;
  message: string;
  created_at: string;
};

export type DashboardSettings = {
  policies: {
    vet_can_view_all: boolean;
  };
  sources: {
    vet_can_view_all: "database" | "environment" | string;
  };
  integration: {
    ml_service_url?: string | null;
    ml_enabled: boolean;
    public_base_url: string;
    cors_origins: string[];
  };
  auth: {
    strategy: string;
  };
  metadata: {
    environment: string;
    updated_at?: string | null;
  };
};
