"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { getSupabaseClient } from "../../lib/supabaseClient";
import type { FunTargetStateRow } from "../../lib/types";

type AdminUserRow = { user_id: string };

export default function AdminPage() {
  const supabase = getSupabaseClient();
  const [userId, setUserId] = useState<string | null>(null);
  const [email, setEmail] = useState<string | null>(null);
  const [isAdmin, setIsAdmin] = useState<boolean>(false);
  const [rows, setRows] = useState<FunTargetStateRow[]>([]);
  const [status, setStatus] = useState<string>("");

  const [selectedUserId, setSelectedUserId] = useState<string>("");
  const [scoreDelta, setScoreDelta] = useState<number>(0);
  const [scoreMode, setScoreMode] = useState<"ADD" | "SUBTRACT" | "SET">("ADD");
  const [predefinedWheelNumber, setPredefinedWheelNumber] = useState<number | "">("");

  const selectedRow = useMemo(
    () => rows.find((r) => r.user_id === selectedUserId) ?? null,
    [rows, selectedUserId]
  );

  const refresh = async () => {
    if (!supabase) return;
    setStatus("Loading...");
    const { data, error } = await supabase.from("fun_target_state").select("*").order("updated_at", { ascending: false });
    if (error) {
      setStatus(`Error: ${error.message}`);
      return;
    }
    setRows((data as FunTargetStateRow[]) ?? []);
    setStatus("Loaded.");
  };

  const checkAdmin = async (uid: string) => {
    if (!supabase) return false;
    const { data, error } = await supabase
      .from("admin_users")
      .select("user_id")
      .eq("user_id", uid)
      .maybeSingle();
    if (error) return false;
    return !!(data as AdminUserRow | null);
  };

  const applyScore = async () => {
    if (!supabase) return;
    if (!selectedUserId) return;
    const currentScore = Number(selectedRow?.score ?? 0);
    const delta = Number(scoreDelta);

    let nextScore = currentScore;
    if (scoreMode === "ADD") nextScore = currentScore + delta;
    if (scoreMode === "SUBTRACT") nextScore = Math.max(0, currentScore - delta);
    if (scoreMode === "SET") nextScore = delta;

    setStatus("Saving score...");
    const { error } = await supabase
      .from("fun_target_state")
      .update({ score: nextScore, last_updated_from: "Admin" })
      .eq("user_id", selectedUserId);
    setStatus(error ? `Error: ${error.message}` : "Saved.");
    await refresh();
  };

  const applyWheel = async () => {
    if (!supabase) return;
    if (!selectedUserId) return;
    setStatus("Saving wheel number...");
    const payload =
      predefinedWheelNumber === ""
        ? { predefined_wheel_number: null, last_updated_from: "Admin" }
        : { predefined_wheel_number: Number(predefinedWheelNumber), last_updated_from: "Admin" };
    const { error } = await supabase.from("fun_target_state").update(payload).eq("user_id", selectedUserId);
    setStatus(error ? `Error: ${error.message}` : "Saved.");
    await refresh();
  };

  useEffect(() => {
    const init = async () => {
      if (!supabase) return;
      const { data } = await supabase.auth.getSession();
      const uid = data.session?.user?.id ?? null;
      setUserId(uid);
      setEmail(data.session?.user?.email ?? null);
      if (!uid) return;
      const ok = await checkAdmin(uid);
      setIsAdmin(ok);
      if (ok) await refresh();
    };
    void init();

    if (!supabase) return;
    const { data: sub } = supabase.auth.onAuthStateChange((_evt, s) => {
      const uid = s?.user?.id ?? null;
      setUserId(uid);
      setEmail(s?.user?.email ?? null);
      setIsAdmin(false);
      setRows([]);
      setSelectedUserId("");
      setStatus("");
      if (uid) {
        void checkAdmin(uid).then((ok) => {
          setIsAdmin(ok);
          if (ok) void refresh();
        });
      }
    });

    return () => sub.subscription.unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [supabase]);

  useEffect(() => {
    if (!supabase || !isAdmin) return;
    const channel = supabase
      .channel("realtime:fun_target_state")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "fun_target_state" },
        () => {
          void refresh();
        }
      )
      .subscribe();

    return () => {
      void supabase.removeChannel(channel);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [supabase, isAdmin]);

  return (
    <div className="container">
      <div className="row" style={{ justifyContent: "space-between" }}>
        <div>
          <h1 style={{ marginBottom: 4 }}>Admin</h1>
          <div className="muted">User: {email ?? "-"}</div>
        </div>
        <div className="row">
          <Link className="btn secondary" href="/">
            Home
          </Link>
          <button className="btn secondary" onClick={refresh} disabled={!isAdmin}>
            Refresh
          </button>
        </div>
      </div>

      {!userId && (
        <div className="card" style={{ marginTop: 16 }}>
          <div>You must sign in first.</div>
        </div>
      )}

      {userId && !supabase && (
        <div className="card" style={{ marginTop: 16 }}>
          <div>Missing Supabase env vars.</div>
        </div>
      )}

      {userId && !isAdmin && (
        <div className="card" style={{ marginTop: 16 }}>
          <div>Not an admin. Add your auth user id to `public.admin_users` in Supabase.</div>
          <div className="muted" style={{ marginTop: 8 }}>
            Your user id: <span className="mono">{userId}</span>
          </div>
        </div>
      )}

      {isAdmin && (
        <>
          <div className="card" style={{ marginTop: 16 }}>
            <div className="row" style={{ justifyContent: "space-between" }}>
              <div>
                <div className="muted">States</div>
                <div>{rows.length} row(s)</div>
              </div>
              <div className="muted">{status}</div>
            </div>
            <div style={{ marginTop: 12, overflowX: "auto" }}>
              <table style={{ width: "100%", borderCollapse: "collapse" }}>
                <thead>
                  <tr style={{ textAlign: "left" }}>
                    <th style={{ padding: 8 }}>User</th>
                    <th style={{ padding: 8 }}>Score</th>
                    <th style={{ padding: 8 }}>Total Bet</th>
                    <th style={{ padding: 8 }}>Winner</th>
                    <th style={{ padding: 8 }}>Predef</th>
                    <th style={{ padding: 8 }}>Updated</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr
                      key={r.user_id}
                      style={{
                        cursor: "pointer",
                        background: r.user_id === selectedUserId ? "rgba(44,102,255,0.18)" : "transparent",
                      }}
                      onClick={() => {
                        setSelectedUserId(r.user_id);
                        setPredefinedWheelNumber(r.predefined_wheel_number ?? "");
                      }}
                    >
                      <td style={{ padding: 8 }}>
                        <span className="mono">{r.user_id}</span>
                      </td>
                      <td style={{ padding: 8 }}>{Number(r.score).toFixed(2)}</td>
                      <td style={{ padding: 8 }}>{Number(r.total_bet_amount).toFixed(2)}</td>
                      <td style={{ padding: 8 }}>{Number(r.winner_amount).toFixed(2)}</td>
                      <td style={{ padding: 8 }}>{r.predefined_wheel_number ?? "-"}</td>
                      <td style={{ padding: 8 }}>{new Date(r.updated_at).toLocaleString()}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          <div className="card" style={{ marginTop: 16 }}>
            <h2 style={{ marginTop: 0 }}>Edit Selected User</h2>
            <div className="muted">Selected user id: {selectedUserId ? <span className="mono">{selectedUserId}</span> : "-"}</div>

            <div className="row" style={{ marginTop: 12 }}>
              <select
                className="input"
                style={{ minWidth: 160 }}
                value={scoreMode}
                onChange={(e) => setScoreMode(e.target.value as any)}
                disabled={!selectedUserId}
              >
                <option value="ADD">ADD</option>
                <option value="SUBTRACT">SUBTRACT</option>
                <option value="SET">SET</option>
              </select>
              <input
                className="input"
                type="number"
                value={Number.isFinite(scoreDelta) ? scoreDelta : 0}
                onChange={(e) => setScoreDelta(Number(e.target.value))}
                disabled={!selectedUserId}
                placeholder="Amount"
              />
              <button className="btn" onClick={applyScore} disabled={!selectedUserId}>
                Save Score
              </button>
            </div>

            <div className="row" style={{ marginTop: 12 }}>
              <input
                className="input"
                type="number"
                min={0}
                max={9}
                value={predefinedWheelNumber}
                onChange={(e) => {
                  const raw = e.target.value;
                  if (raw === "") return setPredefinedWheelNumber("");
                  const n = Number(raw);
                  if (Number.isInteger(n) && n >= 0 && n <= 9) setPredefinedWheelNumber(n);
                }}
                disabled={!selectedUserId}
                placeholder="Predefined wheel number (0-9)"
              />
              <button className="btn secondary" onClick={() => setPredefinedWheelNumber("")} disabled={!selectedUserId}>
                Clear
              </button>
              <button className="btn" onClick={applyWheel} disabled={!selectedUserId}>
                Save Wheel
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
