"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { getSupabaseClient } from "../lib/supabaseClient";

export default function HomePage() {
  const supabase = getSupabaseClient();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [status, setStatus] = useState<string>("");
  const [sessionEmail, setSessionEmail] = useState<string | null>(null);

  useEffect(() => {
    if (!supabase) return;
    const load = async () => {
      const { data } = await supabase.auth.getSession();
      setSessionEmail(data.session?.user?.email ?? null);
    };
    void load();

    const { data: sub } = supabase.auth.onAuthStateChange((_evt, s) => {
      setSessionEmail(s?.user?.email ?? null);
    });
    return () => {
      sub.subscription.unsubscribe();
    };
  }, [supabase]);

  const signUp = async () => {
    if (!supabase) return;
    setStatus("Signing up...");
    const { error } = await supabase.auth.signUp({ email, password });
    setStatus(error ? `Error: ${error.message}` : "Signed up. If email confirmations are enabled, check your inbox.");
  };

  const signIn = async () => {
    if (!supabase) return;
    setStatus("Signing in...");
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setStatus(error ? `Error: ${error.message}` : "Signed in.");
  };

  const signOut = async () => {
    if (!supabase) return;
    await supabase.auth.signOut();
  };

  return (
    <div className="container">
      <h1>FunTarget</h1>
      <p className="muted">Supabase email/password auth + game state stored in Postgres.</p>

      {!supabase && (
        <div className="card" style={{ marginTop: 16 }}>
          <div>Missing Supabase env vars.</div>
          <div className="muted" style={{ marginTop: 8 }}>
            Set <span className="mono">NEXT_PUBLIC_SUPABASE_URL</span> and{" "}
            <span className="mono">NEXT_PUBLIC_SUPABASE_ANON_KEY</span>.
          </div>
        </div>
      )}

      <div className="card" style={{ marginTop: 16 }}>
        <div className="row" style={{ justifyContent: "space-between" }}>
          <div>
            <div className="muted">Signed in as</div>
            <div>{sessionEmail ?? "-"}</div>
          </div>
          <div className="row">
            <Link className="btn secondary" href="/game">
              Open Game
            </Link>
            <Link className="btn secondary" href="/admin">
              Admin
            </Link>
            <button className="btn danger" onClick={signOut} disabled={!sessionEmail}>
              Sign out
            </button>
          </div>
        </div>
      </div>

      <div className="card" style={{ marginTop: 16 }}>
        <h2 style={{ marginTop: 0 }}>Login / Signup</h2>
        <div className="row">
          <input
            className="input"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="email"
            autoComplete="email"
          />
          <input
            className="input"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="password"
            type="password"
            autoComplete="current-password"
          />
        </div>
        <div className="row" style={{ marginTop: 12 }}>
          <button className="btn" onClick={signIn} disabled={!email || !password}>
            Sign in
          </button>
          <button className="btn secondary" onClick={signUp} disabled={!email || !password}>
            Sign up
          </button>
          <span className="muted">{status}</span>
        </div>
      </div>
    </div>
  );
}
