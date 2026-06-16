import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // The shared workspace package ships TS sources directly (no build step).
  // Without this, Turbopack's prod build won't compile it.
  transpilePackages: ["@photoboot/shared"],

  experimental: {
    serverActions: {
      // Backgrounds can be a few MB; default 1MB body limit is too tight.
      bodySizeLimit: "10mb",
    },
  },
};

export default nextConfig;
