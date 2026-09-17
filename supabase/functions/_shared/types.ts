/**
 * TypeScript type definitions for database models
 * Matches the schema defined in migrations/
 */

/**
 * Profile (auth.users extended data)
 */
export interface Profile {
  id: string; // UUID
  email: string;
  display_name: string | null;
  created_at: string;
  updated_at: string;
}

/**
 * Subscription status
 */
export type SubscriptionTier = "free" | "monthly" | "yearly" | "starter" | "pro" | "lifetime";
export type SubscriptionStatus = "active" | "past_due" | "canceled" | "expired";

export interface Subscription {
  id: string; // UUID
  user_id: string; // UUID
  tier: SubscriptionTier;
  status: SubscriptionStatus;
  stripe_customer_id: string | null;
  stripe_subscription_id: string | null;
  current_period_start: string | null; // ISO timestamp
  current_period_end: string | null; // ISO timestamp
  created_at: string;
  updated_at: string;
}

/**
 * Usage log entry
 */
export interface UsageLog {
  id: string; // UUID
  user_id: string; // UUID
  word_count: number;
  recording_seconds: number;
  style: string;
  script_mode: string | null;
  created_at: string;
}

/**
 * Monthly usage aggregation (from view)
 */
export interface MonthlyUsage {
  user_id: string;
  riffs_used: number;
  words_used: number;
  seconds_used: number;
  period_start: string;
}

/**
 * Device registration
 */
export type DeviceType = "mac" | "windows" | "ios" | "android" | "unknown";

export interface Device {
  id: string; // UUID
  user_id: string; // UUID
  device_id: string;
  device_name: string | null;
  device_type: DeviceType;
  os_version: string | null;
  app_version: string | null;
  last_seen_at: string;
  last_ip_address: string | null;
  last_location_hint: string | null;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

/**
 * Riff history entry
 */
export interface RiffHistoryEntry {
  id: string; // UUID
  user_id: string; // UUID
  timestamp: string; // ISO string (not TIMESTAMPTZ)
  original: string;
  refined: string;
  style: string;
  script_mode: string | null;
  device_id: string | null;
  created_at: string;
}

/**
 * Suspicious activity
 */
export type SuspiciousActivityType =
  | "concurrent_usage"
  | "device_limit_exceeded"
  | "quota_exceeded"
  | "invalid_signature"
  | "geolocation_anomaly"
  | "rapid_requests"
  | "token_reuse"
  | "failed_auth"
  | "other";

export type Severity = "low" | "medium" | "high" | "critical";

export interface SuspiciousActivity {
  id: string; // UUID
  user_id: string | null; // UUID (nullable for unauthenticated attempts)
  activity_type: SuspiciousActivityType;
  severity: Severity;
  description: string | null;
  metadata: Record<string, any> | null;
  ip_address: string | null;
  device_id: string | null;
  created_at: string;
}

/**
 * API Response Types
 */

export interface ValidateSubscriptionResponse {
  valid: boolean;
  tier: SubscriptionTier;
  status: SubscriptionStatus;
  quota: {
    riffs_limit: number | null;
    riffs_used: number;
    seconds_limit: number | null;
    seconds_used: number;
  };
  features: {
    all_styles: boolean;
    custom_prompts: boolean;
    priority: boolean;
    byok: boolean;
  };
  managed_key_available: boolean;
}

export interface LogUsageResponse {
  success: boolean;
  quota: {
    riffs_used: number;
    seconds_used: number;
  };
}

export interface RegisterDeviceResponse {
  success: boolean;
  device_id: string;
  is_new: boolean;
  message: string;
  error?: string;
  active_devices?: number;
}

export interface SyncHistoryUploadResponse {
  success: boolean;
  timestamp: string;
}

export interface SyncHistoryDownloadResponse {
  success: boolean;
  history: RiffHistoryEntry[];
  count: number;
}

export interface CreateCheckoutResponse {
  url: string;
  session_id: string;
}

export interface CreatePortalResponse {
  url: string;
}
