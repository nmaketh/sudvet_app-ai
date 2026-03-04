import type { Config } from "tailwindcss";

const config: Config = {
  darkMode: ["class"],
  content: ["./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        border: "#D8E7DF",
        background: "#F5FAF8",
        foreground: "#1D2A25",
        primary: "#1F8A66",
        secondary: "#5F9D89",
        accent: "#BB8927",
        panel: "#FFFFFF",
        muted: "#65756F",
      },
      borderRadius: {
        lg: "1rem",
        xl: "1.25rem",
      },
      boxShadow: {
        panel: "0 8px 28px rgba(31, 38, 31, 0.07)",
      },
    },
  },
  plugins: [],
};

export default config;
