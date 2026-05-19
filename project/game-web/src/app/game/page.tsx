"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { getSupabaseClient } from "../../lib/supabaseClient";
import type { FunTargetStateRow } from "../../lib/types";

function parseJsonObject(v: string): Record<string, number> {
  if (!v.trim()) return {};
  const parsed = JSON.parse(v) as unknown;
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
  const obj = parsed as Record<string, unknown>;
  const out: Record<string, number> = {};
  for (const key of Object.keys(obj)) {
    const n = Number(obj[key]);
    if (Number.isFinite(n) && n > 0) out[key] = n;
  }
  return out;
}

export default function GamePage() {
  const supabase = getSupabaseClient();
  const [userId, setUserId] = useState<string | null>(null);
  const [email, setEmail] = useState<string | null>(null);
  const [row, setRow] = useState<FunTargetStateRow | null>(null);
  const [status, setStatus] = useState<string>("");

  const [betsJsonText, setBetsJsonText] = useState<string>("{}");

  const last10Text = useMemo(() => {
    if (!row?.last10_results?.length) return "-";
    return row.last10_results.join(", ");
  }, [row]);

  const loadOrCreate = async () => {
    if (!supabase) return;
    setStatus("Loading state...");
    const { data: userRes } = await supabase.auth.getUser();
    const uid = userRes.user?.id ?? null;
    if (!uid) {
      setStatus("Not signed in.");
      setRow(null);
      return;
    }

    // Create row if missing (RLS allows insert with user_id = auth.uid())
    await supabase.from("fun_target_state").upsert({ user_id: uid }, { onConflict: "user_id" });

    const { data, error } = await supabase
      .from("fun_target_state")
      .select("*")
      .eq("user_id", uid)
      .maybeSingle();

    if (error) {
      setStatus(`Error: ${error.message}`);
      return;
    }

    setRow((data as FunTargetStateRow | null) ?? null);
    setBetsJsonText(JSON.stringify((data as any)?.bets_json ?? {}, null, 2));
    setStatus("Loaded.");
  };

  const saveBets = async () => {
    if (!supabase) return;
    if (!userId) return;
    setStatus("Saving bets...");
    try {
      const bets = parseJsonObject(betsJsonText);
      const total = Object.values(bets).reduce((acc, n) => acc + n, 0);

      const { error } = await supabase
        .from("fun_target_state")
        .update({
          bets_json: bets,
          total_bet_amount: total,
          last_updated_from: "Site",
        })
        .eq("user_id", userId);

      if (error) throw error;
      await loadOrCreate();
    } catch (e) {
      setStatus(`Error: ${(e as Error).message}`);
    }
  };

  const resetGame = async () => {
    if (!supabase) return;
    if (!userId) return;
    setStatus("Resetting game...");
    const { error } = await supabase
      .from("fun_target_state")
      .update({
        score: 0,
        bets_json: {},
        total_bet_amount: 0,
        winner_amount: 0,
        last10_results: [8, 8, 9, 0, 2, 9, 6, 4, 3, 7],
        last_updated_from: "Site",
        last_round_at: new Date().toISOString(),
        predefined_wheel_number: null,
      })
      .eq("user_id", userId);
    setStatus(error ? `Error: ${error.message}` : "Reset done.");
    await loadOrCreate();
  };

  useEffect(() => {
    const init = async () => {
      if (!supabase) return;
      const { data } = await supabase.auth.getSession();
      setUserId(data.session?.user?.id ?? null);
      setEmail(data.session?.user?.email ?? null);
    };
    void init();

    if (!supabase) return;
    const { data: sub } = supabase.auth.onAuthStateChange((_evt, s) => {
      setUserId(s?.user?.id ?? null);
      setEmail(s?.user?.email ?? null);
      setRow(null);
      setStatus("");
      if (s?.user?.id) void loadOrCreate();
    });

    return () => {
      sub.subscription.unsubscribe();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [supabase]);

  useEffect(() => {
    if (userId) void loadOrCreate();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId]);

  return (
    <div className="container">
      <div className="row" style={{ justifyContent: "space-between" }}>
        <div>
          <h1 style={{ marginBottom: 4 }}>Game State</h1>
          <div className="muted">User: {email ?? "-"}</div>
        </div>
        <div className="row">
          <Link className="btn secondary" href="/">
            Home
          </Link>
          <button className="btn secondary" onClick={loadOrCreate} disabled={!userId}>
            Refresh
          </button>
          <button className="btn danger" onClick={resetGame} disabled={!userId}>
            Reset
          </button>
        </div>
      </div>

      <div className="card" style={{ marginTop: 16 }}>
        <div className="row">
          <div style={{ minWidth: 240 }}>
            <div className="muted">Score</div>
            <div style={{ fontSize: 22, fontWeight: 700 }}>{row ? Number(row.score).toFixed(2) : "-"}</div>
          </div>
          <div style={{ minWidth: 240 }}>
            <div className="muted">Total Bet Amount</div>
            <div style={{ fontSize: 18, fontWeight: 700 }}>{row ? Number(row.total_bet_amount).toFixed(2) : "-"}</div>
          </div>
          <div style={{ minWidth: 240 }}>
            <div className="muted">Winner Amount</div>
            <div style={{ fontSize: 18, fontWeight: 700 }}>{row ? Number(row.winner_amount).toFixed(2) : "-"}</div>
          </div>
        </div>
        <div className="row" style={{ marginTop: 10 }}>
          <div className="muted">Predefined Wheel Number:</div>
          <div>{row?.predefined_wheel_number ?? "-"}</div>
          <div className="muted">Last10:</div>
          <div>{last10Text}</div>
        </div>
        <div className="row" style={{ marginTop: 10 }}>
          <div className="muted">Last updated from:</div>
          <div>{row?.last_updated_from ?? "-"}</div>
          <div className="muted">Last round at:</div>
          <div>{row?.last_round_at ?? "-"}</div>
        </div>
      </div>

      <div className="card" style={{ marginTop: 16 }}>
        <h2 style={{ marginTop: 0 }}>Bets (JSON)</h2>
        <p className="muted" style={{ marginTop: 0 }}>
          Update bets by editing JSON like: <span className="mono">{`{ "1": 10, "7": 5 }`}</span>
        </p>
        <textarea
          className="input mono"
          style={{ width: "100%", minHeight: 160 }}
          value={betsJsonText}
          onChange={(e) => setBetsJsonText(e.target.value)}
          disabled={!supabase || !userId}
        />
        <div className="row" style={{ marginTop: 12 }}>
          <button className="btn" onClick={saveBets} disabled={!supabase || !userId}>
            Save Bets
          </button>
          <span className="muted">{status}</span>
        </div>
      </div>
    </div>
  );
}
