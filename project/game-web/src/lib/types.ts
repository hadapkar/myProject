export type FunTargetStateRow = {
  id: number;
  user_id: string;
  score: string | number;
  predefined_wheel_number: number | null;
  last10_results: number[];
  total_bet_amount: string | number;
  winner_amount: string | number;
  bets_json: Record<string, number>;
  last_updated_from: "Site" | "Mobile" | "Admin" | string;
  last_round_at: string | null;
  created_at: string;
  updated_at: string;
};

