import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./src/**/*.{js,ts,jsx,tsx,mdx}"],
  theme: {
    extend: {
      colors: {
        ink: "#1f2926",
        muted: "#6c7771",
        paper: "#f5f4ef",
        surface: "#fffefa",
        line: "#e5e6df",
        pine: {
          50: "#edf5f1",
          100: "#d9e9e1",
          200: "#b5d4c6",
          300: "#85b9a3",
          400: "#579a80",
          500: "#337d66",
          600: "#246651",
          700: "#145447",
          800: "#16443b",
          900: "#15382f"
        },
        amber: {
          50: "#faf4e9",
          100: "#f3e8d0",
          400: "#c89458",
          500: "#aa763c",
          700: "#80552f"
        }
      },
      boxShadow: {
        soft: "0 12px 32px rgba(31, 41, 38, 0.06)",
        panel: "0 1px 2px rgba(31, 41, 38, 0.04), 0 8px 24px rgba(31, 41, 38, 0.035)"
      },
      borderRadius: {
        xl: "0.9rem",
        "2xl": "1.15rem"
      },
      fontFamily: {
        sans: ["var(--font-geist-sans)", "ui-sans-serif", "system-ui"],
        mono: ["var(--font-geist-mono)", "ui-monospace", "monospace"]
      }
    }
  },
  plugins: []
};

export default config;
