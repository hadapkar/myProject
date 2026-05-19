import type { NextConfig } from "next";
import path from "node:path";
import { fileURLToPath } from "node:url";

const configDir = path.dirname(fileURLToPath(import.meta.url));

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // Monorepo: avoid workspace-root lockfile warnings during build/output tracing.
  outputFileTracingRoot: configDir
};

export default nextConfig;
