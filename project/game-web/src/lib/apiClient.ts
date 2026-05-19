import type { SupabaseClient } from "@supabase/supabase-js";

export type ApiClient = {
  get<T>(path: string): Promise<T>;
  post<T>(path: string, body: unknown): Promise<T>;
};

export function createApiClient(supabase: SupabaseClient): ApiClient | null {
  const baseUrl = process.env.NEXT_PUBLIC_API_BASE_URL;
  if (!baseUrl) {
    return null;
  }

  const request = async <T>(method: string, path: string, body?: unknown): Promise<T> => {
    const { data } = await supabase.auth.getSession();
    const token = data.session?.access_token;
    if (!token) throw new Error("Not signed in");

    const res = await fetch(`${baseUrl}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      cache: "no-store",
    });

    const text = await res.text();
    if (!res.ok) {
      throw new Error(text || `HTTP ${res.status}`);
    }

    return (text ? (JSON.parse(text) as T) : (null as T));
  };

  return {
    get: <T>(path: string) => request<T>("GET", path),
    post: <T>(path: string, body: unknown) => request<T>("POST", path, body),
  };
}
