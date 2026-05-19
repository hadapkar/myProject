import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let cached: SupabaseClient | null = null;

export function getSupabaseClient(): SupabaseClient | null {
  if (cached) return cached;

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  // Allow Next.js build/prerender to succeed even if env vars are not set.
  // The UI will show an error state at runtime instead.
  if (!url || !anonKey) {
    return null;
  }

  cached = createClient(url, anonKey);
  return cached;
}

