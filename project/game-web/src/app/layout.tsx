import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "FunTarget",
  description: "FunTarget game (Supabase auth + state)",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

